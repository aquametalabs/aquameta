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
create extension if not exists "pg_http";

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
        q text;
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

            q := 'insert into ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id).pk_column_id.relation_id.name) || ' select * from json_to_record (' || quote_literal(args->i->'row') || ')';
            -- raise notice '(NOT) QUERY: %', q;
            -- execute q;

            perform endpoint.row_insert((row_id::meta.schema_id).name, 'table', (row_id::meta.relation_id).name, args->i->'row');
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

--
create or replace function endpoint.row_insert(
    _schema_name text,
    relation_type text,
    _relation_name text,
    args json

) returns setof json as $$
    declare
       q text;
    begin
        q := '
            with inserted_row as (
                insert into ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) || ' (' || (
                    select string_agg(quote_ident(json_object_keys), ',' order by json_object_keys)
                    from json_object_keys(args)

                ) || ') values (' || (
                       select string_agg('
                               case when endpoint.is_json_array($4->>' || quote_literal(json_object_keys) || ') then ((
                                        select ''{'' || string_agg(value::text, '', '') || ''}''
                                        from json_array_elements(($4->>' || quote_literal(json_object_keys) || ')::json)
                                    ))
                                    when endpoint.is_json_object($4->>' || quote_literal(json_object_keys) || ') then
                                        ($4->' || quote_literal(json_object_keys) || ')::text
                                    else ($4->>' || quote_literal(json_object_keys) || ')::text
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
                "columns":'' || endpoint.columns_json($1, $3) || '',
                "result": [{
                    "row": '' || row_to_json(inserted_row.*) || '',
                    "selector": "'' || $1 || ''/'' || $2 || ''/'' || $3 || ''/rows/'' ||
                                ' || coalesce('coalesce(replace((inserted_row.' || endpoint.pk_name(_schema_name, _relation_name) || ')::text, ''"'', ''\"''), ''?'') || ''"', '''?'' || ''"') || '
                }]
            }'')::json
            from inserted_row
        '; 

        -- raise notice 'ROW_INSERT ############: %', q;
        return query execute q
	using _schema_name,
                relation_type,
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
    _schema_name text,
    relation_type text,
    _relation_name text,
    pk text,
    args json
) returns json as $$ -- FIXME: use json_to_row upon 9.4 release, alleviates all the destructuring below
    begin
        -- raise notice 'ROW_UPDATE ARGS: %, %, %, %, %', _schema_name, relation_type, _relation_name, pk, args::text;
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
    schema_name text,
    table_name text,
    queryable_type text,
    pk text
) returns json as $$

    declare
        row_query text;
        row_json text;
        columns_json text;

    begin
        -- raise notice 'ROW SELECT ARGS: %, %, %, %', schema_name, table_name, queryable_type, pk;
        set local search_path = endpoint;

        row_query := 'select ''[{"row": '' || row_to_json(t.*) || '',"selector":"' || schema_name || '/' || queryable_type || '/' || table_name || '/rows/' || pk || '"}]'' from '
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
    schema_name text,
    table_name text,
    queryable_type text,
    pk text,
    field_name text
) returns text as $$

    declare
        row_query text;
        row_json text;
        columns_json text;
        result text;

    begin
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
    schema_name text,
    table_name text,
    queryable_type text,
    args json
) returns json as $$
    declare
        row_query text;
        rows_json text;
        columns_json json;
        _limit text := '';
        _offset text := '';
        _order_by text := '';
        _where text := 'where true';
        r record;

    begin
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
                          select ''{
                              "row":'' || row_to_json(t.*) || '',
                              "selector": "' || schema_name || '/' || queryable_type || '/' || table_name || '/rows/'' || replace(' || coalesce(quote_ident(endpoint.pk_name(schema_name, table_name)), '''?''') || '::text, ''"'', ''\"'') || ''"
                          }'' js
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
    schema_name text,
    function_name text,
    args json
) returns json as $$

    declare
        _schema_name alias for schema_name;
        _function_name alias for function_name;
        function_args text;
        columns_json text;
        func_returns text;
        rows_json text[];
        row_is_composite boolean;
        _row record;
        function_row record;

    begin
        -- raise notice '###### ROW SELECT FUNCTION ARGS: %, %, %', schema_name, function_name, args;

        select *
        from meta.function f
        where f.schema_name = _schema_name and
              f.name = _function_name
        into function_row;

        -- replace with querying meta.type
        select typtype = 'c'
        from pg_catalog.pg_type
        into row_is_composite
        where pg_type.oid = function_row.return_type::regtype;

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
            from (select function_name as name, function_row.return_type as "type") q
            into columns_json;
        end if;

        select string_agg(quote_ident(r.key) || ':=' || quote_literal(r.value), ',')
        from json_each_text(args) r
        into function_args;

        for _row in execute 'select * from ' || quote_ident(schema_name) || '.' || quote_ident(function_name)
                            || '(' || function_args || ')'
        loop
            rows_json := array_append(rows_json, '{ "row": ' || row_to_json(_row) || ', "selector": "'
                                                 || schema_name || '/function/' || function_name || '/rows/?" }');  -- TODO if we pulled a single table from pg_class, give that selector
        end loop;

        return '{"columns":[' || columns_json || '],"result":' || coalesce('[' || array_to_string(rows_json,',') || ']', '[]') || '}';
    end;
$$
language plpgsql;

create function endpoint.rows_select_function(
    schema_name text,
    function_name text,
    args json,
    column_name text
) returns text as $$
    declare
        function_args text;
        columns_json text;
        func_returns text;
        rows_json text[];
        row_type regtype;
        row_is_composite boolean;
        _row record;
        result text;

    begin
        select case when substring(q.ret from 1 for 6) = 'SETOF ' then substring(q.ret from 6)
                    else q.ret
               end::regtype
        from (select pg_get_function_result((schema_name || '.' || function_name)::regproc) as ret) q
        into row_type;

        select typtype = 'c' from pg_type into row_is_composite where pg_type.oid = row_type;

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
              from (select function_name as name, row_type as "type") q
              into columns_json;
        end if;

        select string_agg(quote_ident(r.key) || ':=' || quote_literal(r.value), ',')
        from json_each_text(args) r
        into function_args;

        execute 'select ' || quote_ident(column_name) || ' from ' || quote_ident(schema_name) || '.' || quote_ident(function_name)
                || '(' || function_args || ')' into result;

        return result;
    end;
$$
language plpgsql;

/******************************************************************************
 * FUNCTION row_delete
 *****************************************************************************/

create function endpoint.row_delete(
    schema_name text,
    table_name text,
    queryable_type text,
    pk text
) returns json as $$
    begin
        execute 'delete from ' || quote_ident(schema_name) || '.' || quote_ident(table_name) ||
                ' where ' || (
                    select quote_ident(pk_name) || ' = ' || quote_literal(pk) || '::' || pk_type
                    from endpoint.pk(schema_name, table_name) p
                );

        return '{}';
    end;
$$ language plpgsql;



/****************************************************************************************************
 * FUNCTION request JSON VERSION FOR UWSGI woot. 
 ****************************************************************************************************/

create or replace function endpoint.request(
    verb text,
    path text,
    headers json,
    data json,
    out status integer,
    out message text,
    out data2 text --FIXME INOUT breaks meta
) returns setof record as $$
    declare
        path_parts text[];
        parts integer;
        args json;

    begin
        set local search_path = endpoint,meta,public;
        select string_to_array(path, '/') into path_parts;
        select array_length(path_parts, 1) into parts;
	args := headers;

        raise notice '###### endpoint.request % %', verb, path;
        raise notice '##### headers: %', headers::text;
        raise notice '##### data: %', data::text;
        raise notice '##### path_parts: %', path_parts::text;
        raise notice '##### parts: %', parts::text;

        if verb = 'GET' then
            if parts = 5 then
                if path_parts[3] = 'function' then
                    return query select 200, 'OK'::text, (select endpoint.rows_select_function(path_parts[2], path_parts[4], args))::text;
                else
                    return query select 200, 'OK'::text, (select endpoint.rows_select(path_parts[2], path_parts[4], path_parts[3], args))::text;
                end if;
            elsif parts = 6 then
                if path_parts[3] = 'function' then
                    return query select 200, 'OK'::text, (select endpoint.rows_select_function(path_parts[2], path_parts[4], args, path_parts[6]))::text;
                else
                    return query select 200, 'OK'::text, (select endpoint.row_select(path_parts[2], path_parts[4], path_parts[3], path_parts[6]))::text;
                end if;
            elsif parts = 7 then
                return query select 200, 'OK'::text, (select endpoint.field_select(path_parts[2], path_parts[4], path_parts[3], path_parts[6], path_parts[7]))::text;
            else
                raise notice '############## 404 not found ##############';
                return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found"}')::json;
            end if;

        elsif verb = 'POST' then
            if path_parts[2] = 'insert' then
                -- raise notice 'INSERT MULTIPLE';
                return query select 200, 'OK'::text, (select endpoint.rows_insert(data2::json))::text;
            else
                return query select 200, 'OK'::text, (select endpoint.row_insert(path_parts[2], path_parts[3], path_parts[4], data2::json))::text;
            end if;

        elsif verb = 'PATCH' then
            return query select 200, 'OK'::text, (select endpoint.row_update(path_parts[2], path_parts[3], path_parts[4], path_parts[6], data2::json))::text;

        elsif verb = 'DELETE' then
            return query select 200, 'OK'::text, (select endpoint.row_delete(path_parts[2], path_parts[4], path_parts[3], path_parts[6]))::text;
        else
            return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
        end if;


/*
        if verb = 'GET' then
		return query select 200, 'OK'::text, 'Hi mom'::text;
            
        else
                return query select 405, 'Method Not Allowed'::text, '{"status": 405, "message": "Method not allowed"}'::text;
        end if;
*/

    exception
        when undefined_table then
             return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found: '|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}')::text;
    end;
$$ language plpgsql;





/****************************************************************************************************
 * FUNCTION request                                                                                 *
 ****************************************************************************************************/

create or replace function endpoint.request(
    verb text,
    path text,
    headers public.hstore,
    data text,
    out status integer,
    out message text,
    out data2 text --FIXME INOUT breaks meta
) returns setof record as $$
    declare
        args_str text;
        path_parts text[];
        parts integer;
        args json;
        args_text text;

    begin
        set local search_path = endpoint,meta,public;
        select string_to_array(path, '/') into path_parts;
        select array_length(path_parts, 1) into parts;

        raise notice '###### endpoint.request % %', verb, path;
        -- raise notice '##### data: %', data::text;
        -- raise notice '##### verb: %', verb::text;
        -- raise notice '##### path: %', path::text;
        -- raise notice '##### headers: %', headers::text;
        -- raise notice '##### path_parts: %', path_parts::text;
        -- raise notice '##### parts: %', parts::text;

        with unnested as (
            select string_to_array(
                unnest(
                    string_to_array(headers->'Uri-Args:', '&')
                ),
                '='
            ) as arg_parts
        )
        select ('{' || string_agg('"' || replace(arg_parts[1], '"', '\"') || '":"' || replace(arg_parts[2], '"', '\"') || '"', ',') || '}')
        from unnested
        into args_text;
        -- raise notice '##### args: %', args_text;
        args := args_text::json;
        data2 := data; --FIXME use inout for efficiency
        -- raise notice '##### data2: %', data2::text;

        if verb = 'GET' then
            if parts = 5 then
                if path_parts[3] = 'function' then
                    return query select 200, 'OK'::text, (select endpoint.rows_select_function(path_parts[2], path_parts[4], args))::text;
                else
                    return query select 200, 'OK'::text, (select endpoint.rows_select(path_parts[2], path_parts[4], path_parts[3], args))::text;
                end if;
            elsif parts = 6 then
                if path_parts[3] = 'function' then
                    return query select 200, 'OK'::text, (select endpoint.rows_select_function(path_parts[2], path_parts[4], args, path_parts[6]))::text;
                else
                    return query select 200, 'OK'::text, (select endpoint.row_select(path_parts[2], path_parts[4], path_parts[3], path_parts[6]))::text;
                end if;
            elsif parts = 7 then
                return query select 200, 'OK'::text, (select endpoint.field_select(path_parts[2], path_parts[4], path_parts[3], path_parts[6], path_parts[7]))::text;
            else
                raise notice '############## 404 not found ##############';
                return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found"}')::json;
            end if;

        elsif verb = 'POST' then
            if path_parts[2] = 'insert' then
                -- raise notice 'INSERT MULTIPLE';
                return query select 200, 'OK'::text, (select endpoint.rows_insert(data2::json))::text;
            else
                return query select 200, 'OK'::text, (select endpoint.row_insert(path_parts[2], path_parts[3], path_parts[4], data2::json))::text;
            end if;

        elsif verb = 'PATCH' then
            return query select 200, 'OK'::text, (select endpoint.row_update(path_parts[2], path_parts[3], path_parts[4], path_parts[6], data2::json))::text;

        elsif verb = 'DELETE' then
            return query select 200, 'OK'::text, (select endpoint.row_delete(path_parts[2], path_parts[4], path_parts[3], path_parts[6]))::text;
        else
            return query select 405, 'Method Not Allowed'::text, ('{"status": 405, "message": "Method not allowed"}')::json;
        end if;

    exception
        when undefined_table then
--             return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found: '|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}')::text;
             return query select 404, 'Bad Request'::text, ('{"status": 404, "message": "Not Found: '|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}')::text;
--        when others then -- TODO map db exceptions to HTTP status and message here
 --            return query select 400, 'Bad Request'::text, ('{"status": 400, "message": "Bad Request: '|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}');
    end;
$$ language plpgsql;


/******************************************************************************
 *
 *
 * AUTH?
 *
 * these are very old and not thought out.
 ******************************************************************************/


-- create schema auth;
create function endpoint.login(encrypted_password character varying) RETURNS uuid
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    AS $$
    DECLARE
        token uuid;
        role_name varchar;
    BEGIN
        set local search_path = endpoint;

        EXECUTE 'SELECT rolname FROM pg_catalog.pg_authid WHERE rolpassword = ' || quote_literal(encrypted_password) INTO role_name;
        EXECUTE 'INSERT INTO endpoint.session (username) values (' || quote_literal(role_name) || ') RETURNING token' INTO token;
        RETURN token;
    END
$$;

create view endpoint."current_user" AS SELECT "current_user"() AS "current_user";

create table endpoint.session (
    id serial primary key,
    username character varying,
    token uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


commit;
