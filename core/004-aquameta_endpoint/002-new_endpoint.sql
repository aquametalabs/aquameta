/******************************************************************************
 * ENDPOINT SERVER
 * HTTP request handler for a datum REST interface
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;


create extension if not exists "uuid-ossp";

create schema endpoint;

set search_path = endpoint;

/******************************************************************************
 *
 *
 * DATA MODEL
 *
 *
 ******************************************************************************/

create table mimetype (
    id uuid default public.uuid_generate_v4() primary key,
    mimetype text not null
);

-- pulled out: replaced by optional/DATA-endpoint.sql
-- insert into mimetype (mimetype) values ('text/html');
-- insert into mimetype (mimetype) values ('text/javascript');
-- insert into mimetype (mimetype) values ('text/css');

create table column_mimetype (
    id uuid default public.uuid_generate_v4() primary key,
    column_id meta.column_id not null,
    mimetype_id uuid not null references mimetype(id)
);

create table "resource_binary" (
    id uuid default public.uuid_generate_v4() primary key,
    path text not null unique,
    mimetype_id uuid not null references mimetype(id) on delete restrict on update cascade,
    content bytea not null
);

create table "resource_text" (
    id uuid default public.uuid_generate_v4() primary key,
    path text not null unique,
    mimetype_id uuid not null references mimetype(id) on delete restrict on update cascade,
    content text not null
);

create table "resource" (
    id uuid default public.uuid_generate_v4() primary key,
    path text not null unique,
    mimetype_id uuid not null references mimetype(id) on delete restrict on update cascade,
    content text not null
);




/******************************************************************************
 *
 *
 * UTIL FUNCTIONS
 *
 *
 ******************************************************************************/

create function set_mimetype(
    _schema name,
    _table name,
    _column name,
    _mimetype text
) returns void as $$
    insert into endpoint.column_mimetype (column_id, mimetype_id)
    select c.id, m.id
    from meta.column c
    cross join endpoint.mimetype m
    where c.schema_name   = _schema and
          c.relation_name = _table and
          c.name          = _column and
          m.mimetype = _mimetype
$$ language sql;


/******************************************************************************
 * FUNCTION columns_json
 *****************************************************************************/

create type column_type as (
    name text,
    "type" text
);

-- returns the columns for a provided schema.relation as a json object
create function columns_json(
    _schema_name text,
    _relation_name text,
    out json json
) returns json as $$
    select ('[' || string_agg(row_to_json(row(c.name, c.type_name)::endpoint.column_type)::text, ',') || ']')::json
    from meta.column c
    where c.schema_name = _schema_name and
          c.relation_name = _relation_name
$$
language sql;



/****************************************************************************************************
 * FUNCTION pk                                                                                      *
 ****************************************************************************************************/

-- returns the primary key name and type of the provided schema.relation
create function pk(
    _schema_name name,
    _relation_name name,
    out pk_name text,
    out pk_type text
) returns record as $$
    select c.name, c.type_name
    from meta.column c
    where c.schema_name = _schema_name and
          c.relation_name = _relation_name and
          c.primary_key
$$
language sql;



/****************************************************************************************************
 * FUNCTION pk_name                                                                                 *
 ****************************************************************************************************/

create function pk_name(
    _schema_name name,
    _relation_name name
) returns text as $$
    select c.name
    from meta.column c
    where c.schema_name = _schema_name and
          c.relation_name = _relation_name and
          c.primary_key
$$
language sql;



/*******************************************************************************
 *
 *
 * JOIN GRAPH
 * 
 * A multidimensional structure made up of rows from various tables connected
 * by their foreign keys, for non-tabular query results made up of rows, but
 * serialized into a table of type join_graph_row.
 *
 *
 *
 *******************************************************************************/



/*******************************************************************************
 * TYPE join_graph_row
 * 
 * label - the table being joined on's label/alias -- customers c
 * row_id - the meta.row_id for this row
 * row - the jsonb serialized row, whatever row_to_json outputs
 * position - the order in which the rows are inserted, if applicable 
 * exclude - when true, these rows are excluded from the join graph
 *******************************************************************************/
create type join_graph_row as (
    label text,
    row_id meta.row_id,
    row jsonb,
    position integer,
    exclude boolean
);


/*******************************************************************************
 * FUNCTION endpoint.construct_join_graph
 *
 * constructs a join graph table containing any rows matching the specified 
 * JOIN pattern
 *******************************************************************************/

/*
sample usage:
select endpoint.construct_join_graph('foo',
    '{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "join_local_field": "id", "where_clause": "b.id = ''e2edb6c9-cb76-4b57-9898-2e08debe99ee''" }',
    '[
        {"schema_name": "bundle", "relation_name": "commit", "label": "c", "join_local_field": "bundle_id", "related_label": "b", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset", "label": "r", "join_local_field": "id", "related_label": "c", "related_field": "rowset_id"},
        {"schema_name": "bundle", "relation_name": "rowset_row", "label": "rr", "join_local_field": "rowset_id", "related_label": "r", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "join_local_field": "rowset_row_id", "related_label": "rr", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "blob", "label": "blb", "join_local_field": "hash", "related_label": "rrf", "related_field": "value_hash"}
     ]');
*/

create or replace function endpoint.construct_join_graph (temp_table_name text, start_rowset json, subrowsets json) returns setof endpoint.join_graph_row
as $$
declare
    tmp text;

    schema_name text;
    relation_name text;
    label text;
    pk_field text;
    join_pk_field text;
    join_local_field text;

    related_label text;
    related_field text;

    where_clause text;

    position integer;
    exclude boolean;

    rowset json;
    q text;
    ct integer;
begin
    raise notice '######## CONSTRUCT_JSON_GRAPH % % %', temp_table_name, start_rowset, subrowsets;
    -- create temp table
    tmp := quote_ident(temp_table_name);
    execute 'create temp table '
        || tmp
|| ' of endpoint.join_graph_row';

    -- load up the starting relation
    schema_name := quote_ident(start_rowset->>'schema_name');
    relation_name := quote_ident(start_rowset->>'relation_name');
    label := quote_ident(start_rowset->>'label');
    join_local_field := quote_ident(start_rowset->>'join_local_field');
    pk_field:= quote_ident(start_rowset->>'pk_field');
    exclude:= coalesce(start_rowset->>'exclude', 'false');

    position := coalesce(start_rowset->>'position', '0');

    where_clause := coalesce ('where ' || (start_rowset->>'where_clause')::text, '');

    -- raise notice '#### construct_join_graph PHASE 1:  label: %, schema_name: %, relation_name: %, join_local_field: %, where_clause: %',
    --    label, schema_name, relation_name, join_local_field, where_clause;

    q := 'insert into ' || tmp || ' (label, row_id, row, position, exclude)  '
        || ' select distinct ''' || label || ''','
        || '     meta.row_id(''' || schema_name || ''',''' || relation_name || ''',''' || pk_field || ''',' || label || '.' || pk_field || '::text), '
        || '     row_to_json(' || label || ')::jsonb, '
        || '     ' || position || ', '
        || '     ' || exclude
        || ' from ' || schema_name || '.' || relation_name || ' ' || label
        || ' ' || where_clause;

        -- raise notice 'QUERY PHASE 1: %', q;
    execute q;


    -- load up sub-relations
    for i in 0..(json_array_length(subrowsets) - 1) loop
        rowset := subrowsets->i;

        schema_name := quote_ident(rowset->>'schema_name');
        relation_name := quote_ident(rowset->>'relation_name');
        label := quote_ident(rowset->>'label');
        join_local_field:= quote_ident(rowset->>'join_local_field');
        join_pk_field:= quote_ident(rowset->>'join_local_field');

        related_label := quote_ident(rowset->>'related_label');
        related_field := quote_ident(rowset->>'related_field');

        where_clause := coalesce ('where ' || (rowset->>'where_clause')::text, '');
        exclude:= coalesce(rowset->>'exclude', 'false');

        position := coalesce(rowset->>'position', '0');

        -- raise notice '#### construct_join_graph PHASE 2:  label: %, schema_name: %, relation_name: %, join_local_field: %, related_label: %, related_field: %, where_clause: %',
        -- label, schema_name, relation_name, join_local_field, related_label, related_field, where_clause;


        q := 'insert into ' || tmp || ' ( label, row_id, row, position, exclude) '
            || ' select distinct ''' || label || ''','
            || '     meta.row_id(''' || schema_name || ''',''' || relation_name || ''',''' || join_pk_field || ''',' || label || '.' || join_pk_field || '::text), '
            || '     row_to_json(' || label || ')::jsonb, '
            || '     ' || position || ', '
            || '     ' || exclude
            || ' from ' || schema_name || '.' || relation_name || ' ' || label
            || ' join ' || tmp || ' on ' || tmp || '.label = ''' || related_label || ''''
            || '  and (' || tmp || '.row)->>''' || related_field || ''' = ' || label || '.' || join_local_field || '::text'
            || ' ' || where_clause;
        -- raise notice 'QUERY PHASE 2: %', q;
        execute q;

    end loop;

    execute 'delete from ' || tmp || ' where exclude = true';

    execute 'select * from ' || tmp || ' order by position';
end;
$$ language plpgsql;






/******************************************************************************
 *
 *
 * REQUEST HANDLERS
 *
 * Functions called by endpoint.request, returning JSON/REST responses
 *
 *
 *
 ******************************************************************************/


/****************************************************************************************************
 * FUNCTION rows_insert                                                                              *
 ****************************************************************************************************/

create or replace function endpoint.rows_insert(
    args json
) returns void as $$
    declare
        row_id meta.row_id;
        --q text;
    begin
        raise notice 'ROWS INSERT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
        raise notice 'TOTAL ROWS: %', json_array_length(args);
        -- raise notice 'da json: %', args;

        -- insert rows
        for i in 0..json_array_length(args) - 1 loop
            row_id := (args->i->'row_id')::meta.row_id;
            -- raise notice '########################### inserting row %: % @@@@@ %', i, row_id, args->i;
            -- raise notice '% =  %', row_id, args->i->'row';

            -- disable triggers (except blob... hack hack)
            if row_id::meta.relation_id != meta.relation_id('bundle','blob') then
                execute 'alter table ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) || ' disable trigger all';
            end if;

            -- Doesn't seem to be used
            --q := 'insert into ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) || ' select * from json_to_record (' || quote_literal(args->i->'row') || ')';
            -- raise notice '(NOT) QUERY: %', q;
            -- execute q;

            perform endpoint.row_insert(row_id::meta.relation_id, args->i->'row');
            --perform endpoint.row_insert((row_id::meta.schema_id).name, 'table', (row_id::meta.relation_id).name, args->i->'row');
        end loop;

        -- enable triggers
        for i in 0..json_array_length(args) - 1 loop
            row_id := (args->i->'row_id')::meta.row_id;
            execute 'alter table ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) || ' enable trigger all';
        end loop;
    end
$$
language plpgsql;




/****************************************************************************************************
 * FUNCTION row_insert                                                                              *
 ****************************************************************************************************/

create or replace function endpoint.row_insert(
    relation_id meta.relation_id,
    args json
) returns setof json as $$
    declare
       _schema_name text;
       _relation_name text;
       q text;
    begin
        select (relation_id).schema_id.name into _schema_name;
        select (relation_id).name into _relation_name;

        q := '
            with inserted_row as (
                insert into ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) || ' (' || (
                    select string_agg(quote_ident(json_object_keys), ',' order by json_object_keys)
                    from json_object_keys(args)

                ) || ') values (' || (
                       select string_agg('
                               case when endpoint.is_json_array($3->>' || quote_literal(json_object_keys) || ') then ((
                                        select ''{'' || string_agg(value::text, '', '') || ''}''
                                        from json_array_elements(($3->>' || quote_literal(json_object_keys) || ')::json)
                                    ))
                                    when endpoint.is_json_object($3->>' || quote_literal(json_object_keys) || ') then
                                        ($3->' || quote_literal(json_object_keys) || ')::text
                                    else ($3->>' || quote_literal(json_object_keys) || ')::text
                               end::' || case when endpoint.is_json_object((args->>json_object_keys)) then 'json::'
                                              else ''
                                         end || c.type_name, ',
                               '
                               order by json_object_keys
                       ) from json_object_keys(args)
                       inner join meta.column c
                               on c.schema_name = _schema_name and
                                  c.relation_name = _relation_name and
                                  c.name = json_object_keys
                       left join meta.type t on c.type_id = t.id
                ) || ')
                returning *
            )
            select (''{
                "columns":'' || endpoint.columns_json($1, $2) || '',
                "result": [{ "row": '' || row_to_json(inserted_row.*) || '' }]
            }'')::json
            from inserted_row
        '; 

        -- raise notice 'ROW_INSERT ############: %', q;
        return query execute q
	using _schema_name,
                _relation_name,
                args;
    end
$$
language plpgsql;



/****************************************************************************************************
 * FUNCTION is_composite_type
 ****************************************************************************************************/

/*
                                    when endpoint.is_composite_type($4->>' || quote_literal(json_object_keys) || ') then
                                        ($4->' || quote_literal(json_object_keys) || ')::text

create function endpoint.is_composite_type(value text) returns boolean as $$
begin
    perform json_object_keys(value::json);
    return true;

exception when invalid_parameter_value then
    return false;
          when invalid_text_representation then
    return false;
end;
$$ immutable language plpgsql;
*/



/****************************************************************************************************
 * FUNCTION is_json_object                                                                          *
 ****************************************************************************************************/

create or replace function endpoint.is_json_object(value text) returns boolean as $$
begin
    if value is null then return false; end if;
    perform json_object_keys(value::json);
    return true;

exception when invalid_parameter_value then
    return false;
          when invalid_text_representation then
    return false;
end;
$$ immutable language plpgsql;



/****************************************************************************************************
 * FUNCTION is_json_array                                                                           *
 ****************************************************************************************************/

create function endpoint.is_json_array(value text) returns boolean as $$
begin
    perform json_array_length(value::json);
    return true;

exception when invalid_parameter_value then
    return false;
          when invalid_text_representation then
    return false;
end;
$$ immutable language plpgsql;



/****************************************************************************************************
 * FUNCTION row_update                                                                              *
 ****************************************************************************************************/

create or replace function endpoint.row_update(
    row_id meta.row_id,
    args json
) returns json as $$ -- FIXME: use json_to_row upon 9.4 release, alleviates all the destructuring below
    declare
        _schema_name text;
        _relation_name text;
        pk text;
    begin
        -- raise notice 'ROW_UPDATE ARGS: %, %, %, %, %', _schema_name, relation_type, _relation_name, pk, args::text;
        select (row_id::meta.schema_id).name into _schema_name;
        select (row_id::meta.relation_id).name into _relation_name;
        select row_id.pk_value::text into pk;

        execute (
            select 'update ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) || ' as r
                    set ' || (
                       select string_agg(
                           quote_ident(json_object_keys) || ' =
                               case when endpoint.is_json_array($1->>' || quote_literal(json_object_keys) || ') then ((
                                        select ''{'' || string_agg(value::text, '', '') || ''}''
                                        from json_array_elements(($1->>' || quote_literal(json_object_keys) || ')::json)
                                    ))
                                    when endpoint.is_json_object($1->>' || quote_literal(json_object_keys) || ') then
                                        ($1->' || quote_literal(json_object_keys) || ')::text
                                    else ($1->>' || quote_literal(json_object_keys) || ')::text
                               end::' || case when endpoint.is_json_object((args->>json_object_keys)) then 'json::'
                                              else ''
                                         end || c.type_name, ',
                           '
                       ) from json_object_keys(args)
                       inner join meta.column c
                               on c.schema_name = _schema_name and
                                  c.relation_name = _relation_name and
                                  c.name = json_object_keys
                   ) || ' where ' || (
                       select 'r.' || quote_ident(pk_name) || ' = ' || quote_literal(pk) || '::' || pk_type
                       from endpoint.pk(_schema_name, _relation_name) p
                   )
        ) using args;

        return '{}';
    end;
$$
language plpgsql;



/****************************************************************************************************
 * FUNCTION row_select                                                                              *
 ****************************************************************************************************/

create function row_select(
    row_id meta.row_id
) returns json as $$

    declare
        schema_name text;
        table_name text;
        pk text;

        row_query text;
        row_json text;
        columns_json text;

    begin
        -- raise notice 'ROW SELECT ARGS: %, %, %, %', schema_name, table_name, queryable_type, pk;
        set local search_path = endpoint;

        select (row_id::meta.schema_id).name into schema_name;
        select (row_id::meta.relation_id).name into relation_name;
        select row_id.pk_value::text into pk;

        row_query := 'select ''[{"row": '' || row_to_json(t.*) || ''}]'' from '
                     || quote_ident(schema_name) || '.' || quote_ident(table_name)
                     || ' as t where ' || (
                         select quote_ident(pk_name) || ' = ' || quote_literal(pk) || '::' || pk_type
                         from endpoint.pk(schema_name, table_name) p
                     );

        execute row_query into row_json;

        return '{"columns":' || columns_json(schema_name, table_name) || ',"result":' || coalesce(row_json::text, '[]') || '}';
    end;
$$
language plpgsql;



/****************************************************************************************************
 * FUNCTION field_select                                                                            *
 ****************************************************************************************************/

create or replace function endpoint.field_select(
    field_id meta.field_id
) returns text as $$

    declare
        schema_name text;
        table_name text;
        pk text;
        field_name text;

        row_query text;
        row_json text;
        columns_json text;
        result text;

    begin

        select (field_id::meta.schema_id).name into schema_name;
        select (field_id::meta.relation_id).name into table_name;
        select (field_id::meta.row_id).pk_value into pk;
        select (field_id::meta.column_id).name into field_name;

        -- raise notice 'FIELD SELECT ARGS: %, %, %, %, %', schema_name, table_name, queryable_type, pk, field_name;

        set local search_path = endpoint;

        execute 'select ' || quote_ident(field_name) || ' from ' || quote_ident(schema_name) || '.' || quote_ident(table_name)
                || ' as t where ' || quote_ident(endpoint.pk_name(schema_name, table_name)) || ' = ' || quote_literal(pk) into result;

        return result;
    end;
$$
language plpgsql;



/****************************************************************************************************
 * FUNCTION rows_select                                                                             *
 ****************************************************************************************************/

create function endpoint.rows_select(
    relation_id meta.relation_id,
    args json
) returns json as $$
    declare
        schema_name text;
        table_name text;
        row_query text;
        rows_json text;
        columns_json json;
        _limit text := '';
        _offset text := '';
        _order_by text := '';
        _where text := 'where true';
        r record;

    begin
        select (relation_id).schema_id.name into schema_name;
        select (relation_id).name into table_name;

        for r in select * from json_each_text(args) loop
            if r.key = '$limit' then
                _limit := ' limit ' || quote_literal(r.value);

            elsif r.key = '$offset' then
                _offset := ' offset ' || quote_literal(r.value);

            elsif r.key = '$order_by' then
                select ' order by ' ||
                       string_agg(case substring(r.value from 1 for 1)
                                  when '-' then substring(r.value from 2) || ' desc'
                                  else r.value end, ', ')
                from (select unnest(string_to_array(r.value, ','))) q
                into _order_by;
            else
                if endpoint.is_json_array(r.value) then
                    _where := _where || ' and ' || quote_ident(r.key) || '=' || (
                        select quote_literal('{' || string_agg(value::text, ', ') || '}')
                        from json_array_elements(r.value::json)
                    );
                else
                    _where := _where || ' and ' || quote_ident(r.key) || '=' ||
                              case when endpoint.is_json_object(r.value) then quote_literal(r.value) || '::json'
                                   else quote_literal(r.value)
                              end;
                end if;
            end if;
        end loop;

        row_query := 'select ''['' || string_agg(q.js, '','') || '']'' from (
                          select ''{ "row":'' || row_to_json(t.*) || '' }'' js
                          from ' || quote_ident(schema_name) || '.' || quote_ident(table_name) || ' as t '
                          || _where || _order_by || _limit || _offset || '
                     ) q';

        execute row_query into rows_json;

        return '{"columns":' || endpoint.columns_json(schema_name, table_name) || ','
               || '"result":' || coalesce(rows_json, '[]') || '}';
    end;
$$
language plpgsql;



/******************************************************************************
 * FUNCTION rows_select_function
 *****************************************************************************/

create function rows_select_function(
    function_id meta.function_id,
    args json
) returns json as $$

    declare
        function_row record;
        row_is_composite boolean;
        columns_json text;
        function_args text;
        _row record;
        rows_json text[];

    begin
        -- Get function row
        select *
        from meta.function f
        where f.id = function_id
        into function_row;

        -- Find is return type is composite
        select t.composite
        from meta.function f
		join meta.type t on t.id = f.return_type_id
        where f.id = function_id
	into row_is_composite;

        -- Build columns_json
        if row_is_composite then
          select string_agg(row_to_json(q.*)::text, ',')
            from (
		select pga.attname as name,
			pgt2.typname as "type"
		from pg_catalog.pg_type pgt
			inner join pg_class pgc
				on pgc.oid = pgt.typrelid
			inner join pg_attribute pga
				on pga.attrelid = pgc.oid
			inner join pg_type pgt2
				on pgt2.oid = pga.atttypid
		where pgt.oid = function_row.return_type::regtype
			and pga.attname not in ('tableoid','cmax','xmax','cmin','xmin','ctid')
            ) q
            into columns_json;
        else
            select row_to_json(q.*)
            from (select (function_id).name as name, function_row.return_type as "type") q
            into columns_json;
        end if;

        -- Build function arguments string
        -- Cast to type_name found in meta.function_parameter
        -- Using coalesce(function_args, '') so we can call function without arguments
        select coalesce(
            string_agg(quote_ident(r.key) || ':=' || quote_literal(r.value) || '::' || fp.type_name, ','),
        '')
        from json_each_text(args) r
	join meta.function_parameters fp on
		fp.function_id = function_id and
		fp.name = r.key
        into function_args;

        -- Loop through function call results
        for _row in execute 'select * from ' || quote_ident((function_id::meta.schema_id).name) || '.' || quote_ident((function_id).name)
                            || '(' || function_args || ')'
        loop
            rows_json := array_append(rows_json, '{ "row": ' || row_to_json(_row) || ' }');
        end loop;

        return '{"columns":[' || columns_json || '],"result":' || coalesce('[' || array_to_string(rows_json,',') || ']', '[]') || '}';
    end;
$$
language plpgsql;


create function endpoint.rows_select_function(
    function_id meta.function_id,
    args json,
    column_name text
) returns text as $$
    declare
        row_type regtype;
        row_is_composite boolean;
        columns_json text;
        function_args text;
        result text;

    begin
        select case when substring(q.ret from 1 for 6) = 'SETOF ' then substring(q.ret from 6)
                    else q.ret
               end::regtype
        from (select pg_get_function_result(((function_id::meta.schema_id).name || '.' || (function_id).name)::regproc) as ret) q
        into row_type;

        -- Find is return type is composite
        select t.composite
        from meta.function f
		join meta.type t on t.id = f.return_type_id
        where f.id = function_id
	into row_is_composite;

        -- select typtype = 'c' from pg_type into row_is_composite where pg_type.oid = row_type;

	-- Build columns_json
        if row_is_composite then
                select string_agg(row_to_json(q.*)::text, ',')
                  from (
			select pga.attname as name,
				pgt2.typname as "type"
			from pg_type pgt
				inner join pg_class pgc
					on pgc.oid = pgt.typrelid
				inner join pg_attribute pga
					on pga.attrelid = pgc.oid
				inner join pg_type pgt2
					on pgt2.oid = pga.atttypid
			where pgt.oid = row_type
				and pga.attname not in ('tableoid','cmax','xmax','cmin','xmin','ctid')
                  ) q
                  into columns_json;
        else
            select row_to_json(q.*)
              from (select (function_id).name as name, row_type as "type") q
              into columns_json;
        end if;


        -- Build function arguments string
        select coalesce(
		string_agg(quote_ident(r.key) || ':=' || quote_literal(r.value) || '::' || fp.type_name, ','),
        '')
        from json_each_text(args) r
	join meta.function_parameters fp on
		fp.function_id = function_id and
		fp.name = r.key
        into function_args;


        -- Loop through function call results
        execute 'select ' || quote_ident(column_name) || ' from ' || quote_ident((function_id::meta.schema_id).name) || '.' || quote_ident((function_id).name)
                || '(' || function_args || ')' into result;

        return result;
    end;
$$
language plpgsql;

/******************************************************************************
 * FUNCTION row_delete
 *****************************************************************************/

create function endpoint.row_delete(
    row_id meta.row_id
) returns json as $$
    declare
        schema_name text,
        table_name text,
        pk text;
    begin
        select (row_id::meta.schema_id).name into schema_name;
        select (row_id::meta.relation_id).name into table_name;
        select row_id.pk_value::text into pk;

        execute 'delete from ' || quote_ident(schema_name) || '.' || quote_ident(table_name) ||
                ' where ' || (
                    select quote_ident(pk_name) || ' = ' || quote_literal(pk) || '::' || pk_type
                    from endpoint.pk(schema_name, table_name) p
                );

        return '{}';
    end;
$$ language plpgsql;



/****************************************************************************************************
 * FUNCTION request  NEW VERSION!!!!
 ****************************************************************************************************/

create or replace function endpoint.request(
    verb text,
    path text,
    query_args json,
    post_data json,
    out status integer,
    out message text,
    out response text
) returns setof record as $$
        declare
                row_id meta.row_id;
                relation_id meta.relation_id;
                function_id meta.function_id;
                field_id meta.field_id;

        begin
                set local search_path = endpoint,meta,public;

    /*
     URL					VERB(s)			RESPONSE TYPE
     ----------------------------------------------------------------------------------------------------
     /endpoint/row/{row_id}          	GET, DELETE, PATCH	row
     /endpoint/relation/{relation_id}	GET, POST		rows
     /endpoint/function/{function_id}	GET			variable????
     /endpoint/field/{field_id}		GET			value????

        unnecessary?
     /endpoint/table/{relation_id}	GET, POST		rows
     /endpoint/view/{relation_id}	GET			rows


        questions: 
        does a single row format exist?
        do we include meta-data for the data
                - columns / types / primary key ?   --- YES
                - row_ids ?  (aka selectors)        --- NO



{
	"columns": [
		{
			"name": "id",
			"type": "meta.relation_id"
		},
		...
	],
	"result": [
		{
			"row": {
				"id": {
					"schema_id": {
						"name": "meta"
					},
					"name": "schema"
				},
				"overview_widget_id": null,
				"grid_view_widget_id": null,
				"list_view_widget_id": null,
				"list_item_identifier_widget_id": "b842d2af-4869-4119-955f-02b8e522a5df",
				"row_detail_widget_id": null,
				"grid_view_row_widget_id": null,
				"new_row_widget_id": null
			},
			"selector": "semantics\/table\/relation\/rows\/(\"(meta)\",schema)"
		},
		...
	]
}



   */
/*
 All 9 subroutines
-- needs new where clause to be used in rows_select function

-done- rows_select_function(function_id, query_args)

- what to do with column?
rows_select_function(function_id, query_args, path_parts[6])

-done- row_select(row_id)
-done- row_update(row_id, post_data)
-done- row_delete(row_id)
-done- rows_select(relation_id, query_args)
-done- row_insert(relation_id, post_data)
-done- rows_insert(post_data)
-done- field_select(field_id)

*/

                raise notice '###### endpoint.request % %', verb, path;
                raise notice '##### query string args: %', query_args::text;
                raise notice '##### POST data: %', post_data::text;

                case
                when path like '/endpoint/row/%' then

                        -- URL /endpoint/row/{row_id}
                        row_id := substring(path from 15)::meta.row_id;

                        if verb = 'GET' then

                                -- Get single row
                                return query select 200, 'OK'::text, (select endpoint.row_select(row_id))::text;

                        elsif verb = 'PATCH' then

                                -- Update row
                                return query select 200, 'OK'::text, (select endpoint.row_update(row_id, post_data))::text;

                        elsif verb = 'DELETE' then

                                -- Delete row
                                return query select 200, 'OK'::text, (select endpoint.row_delete(row_id))::text;

                        else
                                -- HTTP method not allowed for this resource: 405
                                return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
                        end if;

               when path like '/endpoint/relation%' then

                        -- URL /endpoint/relation/{relation_id}
                        relation_id := substring(path from 20)::meta.relation_id;

                        if verb = 'GET' then

                                -- Get rows 
                                return query select 200, 'OK'::text, (select endpoint.rows_select(relation_id, query_args))::text;

                        elsif verb = 'POST' then

                                if json_array_length(post_data) = 1 then
                                        -- Insert single row
                                        return query select 200, 'OK'::text, (select endpoint.row_insert(relation_id, post_data))::text;
                                else
                                        -- Insert multiple rows
                                        return query select 200, 'OK'::text, (select endpoint.rows_insert(post_data))::text;
                                end if;

                        else
                                -- HTTP method not allowed for this resource: 405
                                return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
                        end if;

                when path like '/endpoint/function%' then

                        -- URL /endpoint/function/{function_id}
                        function_id := substring(path from 20)::meta.function_id;

                        if verb = 'GET' then
                                -- Get record from function call
                                return query select 200, 'OK'::text, (select endpoint.rows_select_function(function_id, query_args))::text;

                                -- I'm not sure this is possible in a clean way
                                -- Get single column from function call
                                -- old - return query select 200, 'OK'::text, (select endpoint.rows_select_function(path_parts[2], path_parts[4], args, path_parts[6]))::text;
                                return query select 200, 'OK'::text, (select endpoint.rows_select_function(function_id, query_args, /*??*/path_parts[6]))::text;

                        else
                                -- HTTP method not allowed for this resource: 405
                                return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
                        end if;

                when path like '/endpoint/field%' then

                        -- URL /endpoint/field/{field_id}
                        field_id := substring(path from 20)::meta.field_id;

                        if verb = 'GET' then

                                -- Get field
                                return query select 200, 'OK'::text, (select endpoint.field_select(field_id))::text;

                        else
                                -- HTTP method not allowed for this resource: 405
                                return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
                        end if;
/*
                when path like '/endpoint/table%' then

                        relation_id := substring(path from 17)::meta.relation_id;

                        if verb = 'GET' then
                        elsif verb = 'POST' then
                        else
                                -- HTTP method not allowed for this resource: 405
                                --raise exception 'HTTP method not allowed for this resource';
                                return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
                        end if;

                when path like '/endpoint/view%' then

                        relation_id := substring(path from 16)::meta.relation_id;

                        if verb = 'GET' then
                        elsif verb = 'POST' then
                        else
                                -- HTTP method not allowed for this resource: 405
                                --raise exception 'HTTP method not allowed for this resource';
                                return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
                        end if;
*/
                else
                        -- Resource not found: 404
                        return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found"}')::json;

                end case;

                exception when undefined_table then
                return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found: '|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}')::text;

        end;
$$ language plpgsql;


/******************************************************************************
 * endpoint.user
 ******************************************************************************/
create table endpoint.user (
	id uuid default public.uuid_generate_v4() primary key,
	role_id meta.role_id not null default public.uuid_generate_v4()::text::meta.role_id,
	email text not null unique,
	name text not null default '',
	active boolean not null default false,
	activation_code uuid not null default public.uuid_generate_v4()
);


-- Trigger on endpoint.user for insert
create or replace function endpoint.user_insert() returns trigger as $$
declare
	role_exists boolean;
begin
	-- If a role_id is supplied (thus not generated), make sure this role does not exist
	select exists(select 1 from meta.role where id = NEW.role_id) into role_exists;
	if role_exists then
		raise exception 'Role already exists';
	end if;

	-- Create a new role
	insert into meta.role(name) values((NEW.role_id).name);

	return NEW;
end;
$$ language plpgsql;


-- Trigger on endpoint.user for update
create or replace function endpoint.user_update() returns trigger as $$
declare
	role_exists boolean;
begin
	if OLD.role_id != NEW.role_id then

		-- If a role_id is supplied (thus not generated), make sure this role does not exist
		select exists(select 1 from meta.role where id = NEW.role_id) into role_exists;
		if role_exists then
			raise exception 'Role already exists';
		end if;

		-- Delete old role
		delete from meta.role where id = OLD.role_id;

		-- Create a new role
		insert into meta.role(name) values((NEW.role_id).name);

	end if;

	return NEW;
end;
$$ language plpgsql;


-- Trigger on endpoint.user for delete
create or replace function endpoint.user_delete() returns trigger as $$
begin
	-- Delete old role
	delete from meta.role where id = OLD.role_id;
	return OLD;
end;
$$ language plpgsql;


create trigger endpoint_user_insert_trigger before insert on endpoint.user for each row execute procedure endpoint.user_insert();
create trigger endpoint_user_update_trigger before update on endpoint.user for each row execute procedure endpoint.user_update();
create trigger endpoint_user_delete_trigger before delete on endpoint.user for each row execute procedure endpoint.user_delete();


/******************************************************************************
 * auth roles
 ******************************************************************************/
-- User-defined roles inherit from "user" role
create role "user" nologin;


-- Guest role
-- To find default permissions further up the stack
-- `cd aquameta/core && grep -R default_permissions`
create role anonymous login;


-- Superuser is aquameta
create role aquameta superuser createdb createrole login replication bypassrls;


/******************************************************************************
 * endpoint.current_user
 ******************************************************************************/
create view endpoint."current_user" AS SELECT "current_user"() AS "current_user";


/******************************************************************************
 * endpoint.session
 ******************************************************************************/

-- Could this be renamed to endpoint.cookie?

create table endpoint.session (
	id uuid default public.uuid_generate_v4() not null,
	role_id meta.role_id not null,
	user_id uuid references endpoint.user(id)
);


/******************************************************************************
 * endpoint.register
 ******************************************************************************/
create function endpoint.register (_email text, _password text) returns void
	language plpgsql strict security definer
as $$
	declare
		_role_id meta.role_id;
	begin
		-- Create user
		insert into endpoint.user (email, active) values (_email, false) returning (role_id).name into _role_id;

		-- Set role password
		update meta.role set password = _password where id = _role_id;

		-- Inherit from generic user
		insert into meta.role_inheritance (role_id, member_role_id) values (meta.role_id('user'), _role_id);

		-- Send email to {email}
		-- TODO: call email function or insert into queued emails

		return;

	end
$$;


/******************************************************************************
 * endpoint.register_confirm
 ******************************************************************************/
create function endpoint.register_confirm (_email text, _confirmation_code text) returns void
	language plpgsql strict security definer
as $$
	declare
		_user_row record;
		_role_id meta.role_id;
	begin
		-- 1. check for existing user.  throw exceptions for
		  -- a. non-matching code
		execute 'select * from endpoint.user where email=' || quote_literal(_email) || ' and activation_code=' || quote_literal(_confirmation_code) into _user_row;
		if _user_row is null then
			raise exception 'Invalid confirmation code';
		end if;

		  -- b. already active user
		if _user_row.active then
			raise exception 'User already activated';
		end if;


		-- 2. update user set active=true;
		update endpoint.user set active = true where email = _email and activation_code = _confirmation_code::uuid returning (role_id).name into _role_id;


		-- 3. update role set login=true
		update meta.role set can_login = true where id = _role_id; 


		-- 4. send email?
		-- TODO: call email function or insert into queued emails

		return;
	end
$$;


/******************************************************************************
 * endpoint.login
 ******************************************************************************/
create function endpoint.login (_email text, _password text) returns uuid
	language plpgsql strict security definer
as $$
	declare
		_role_name text;
		_encrypted_password text;
		_session_id uuid := null;
	begin
		-- Build encrypted password by getting role name associated with this email
		select 'md5' || md5(_password || (role_id).name) from endpoint.user where email=_email into _encrypted_password;

		-- Email does not exists in endpoint.user table
		if _encrypted_password is null then
			raise exception 'No user with this email';
		end if;

		-- Look for role with this password
		execute 'select rolname from pg_catalog.pg_authid where rolpassword = ' || quote_literal(_encrypted_password) into _role_name;

		-- _role_name is null if rolpassword does not exist in pg_catalog.pg_auth_id table -- invalid password

		-- Create cookie session for this role/user
		if _role_name is not null then
			insert into endpoint.session (role_id, user_id) values (meta.role_id(_role_name), (select id from endpoint.user where email=_email)) returning id into _session_id;
		end if;

		-- Return cookie
		return _session_id;
	end
$$;


/******************************************************************************
 * endpoint.logout
 ******************************************************************************/
create function endpoint.logout (_email text) returns void
	language sql strict security definer
as $$
	-- Should this delete all sessions associated with this user? I think so
	delete from endpoint.session where user_id = (select id from endpoint."user" where email = _email);
$$;


/******************************************************************************
 * endpoint.email
 ******************************************************************************/
create table endpoint.email (
	id serial primary key,
	recipient_email text,
	sender_email text,
	body text
);


create function endpoint.email_insert () returns trigger
as $$

	perform endpoint.email_send(NEW.to, NEW.from, NEW.subject, NEW.body);
	return NEW;

$$ language plpgsql;


create trigger endpoint_email_insert_trigger after insert on endpoint.email for each row execute procedure endpoint.email_insert();


create function endpoint.email_send (to text, from text, subject text, body text) returns void
as $$
$$ language plpython;


commit;
