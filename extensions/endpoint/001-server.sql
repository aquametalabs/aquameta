/******************************************************************************
 * ENDPOINT SERVER
 * HTTP request handler for a datum REST interface
 * HTTP arbitrary resource server
 * Join graph thing
 * Authentication handlers
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/******************************************************************************
 *
 *
 * MIMETYPED RESOURCE TYPES
 *
 *
 ******************************************************************************/

create type endpoint.resource_bin as
(mimetype text, content bytea);

create type endpoint.resource_txt as
(mimetype text, content text);

create function endpoint.resource_bin(value json) returns endpoint.resource_bin as $$
select row(value->>'mimetype', value->>'content')::endpoint.resource_bin
$$ immutable language sql;

create cast (json as endpoint.resource_bin)
with function endpoint.resource_bin(json)
as assignment;

create function endpoint.resource_txt(value json) returns endpoint.resource_txt as $$
select row(value->>'mimetype', value->>'content')::endpoint.resource_txt
$$ immutable language sql;

create cast (json as endpoint.resource_txt)
with function endpoint.resource_txt(json)
as assignment;


/******************************************************************************
 *
 *
 * DATA MODEL
 *
 *
 ******************************************************************************/



/******************************************************************************
 * endpoint.mimetype
 ******************************************************************************/

create table mimetype (
    id uuid not null default public.uuid_generate_v4() primary key,
    mimetype text not null unique
);


/******************************************************************************
 * endpoint.mimetype_extension
 ******************************************************************************/

create table endpoint.mimetype_extension (
    id uuid not null default public.uuid_generate_v4() primary key,
    mimetype_id uuid not null references endpoint.mimetype(id),
    extension text unique
);


create table endpoint.column_mimetype (
    id uuid not null default public.uuid_generate_v4() primary key,
    column_id meta.column_id not null,
    mimetype_id uuid not null references endpoint.mimetype(id)
);


create table endpoint.function_field_mimetype (
    id uuid not null default public.uuid_generate_v4() primary key,
    schema_name text,
    function_name text,
    field_name text,
    mimetype_id uuid not null references endpoint.mimetype(id)
);

/******************************************************************************
 * endpoint.resource
 * these tables contain static resources that exist at a URL path, to be served
 * by the endpoint upon a GET request matching their path.
 ******************************************************************************/

create table endpoint."resource_binary" (
    id uuid not null default public.uuid_generate_v4() primary key,
    path text not null,
    mimetype_id uuid not null references endpoint.mimetype(id) on delete restrict on update cascade,
    active boolean default true,
    content bytea not null
);

create table endpoint.resource_file (
    id uuid not null default public.uuid_generate_v4() primary key,
    file_id text not null,
    active boolean default true,
    path text not null
);

create table endpoint.resource_directory (
    id uuid not null default public.uuid_generate_v4() primary key,
    directory_id text,
    path text,
    indexes boolean
);

create table endpoint.resource (
    id uuid not null default public.uuid_generate_v4() primary key,
    path text not null,
    mimetype_id uuid not null references mimetype(id) on delete restrict on update cascade,
    active boolean default true,
    content text not null default ''
);

/******************************************************************************
 * templates
 * - dynamic HTML fragments, parsed and rendered upon request.
 * - could possibly be non-HTML fragments as well.
 ******************************************************************************/

create table endpoint.template (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    mimetype_id uuid not null references mimetype(id) on delete restrict on update cascade, -- why on update cascade??
    content text not null default ''
);

create table endpoint.template_route (
    id uuid not null default public.uuid_generate_v4() primary key,
    template_id uuid not null references endpoint.template(id),
    url_pattern text not null default '', -- matching paths may contain arguments from the url to be passed into the template
    args text not null default '{}' -- this route's static arguments to be passed into the template
);



/******************************************************************************
 * plv8 module
 * libraries that plv8 can load in -- temporary until plv8 supports import
 * natively.
 ******************************************************************************/

create table endpoint.js_module (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    version text not null default '',
    code text not null default ''
);


/******************************************************************************
 * endpoint.site_settings
 ******************************************************************************/

create table endpoint.site_settings (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text,
    active boolean default false,

    site_title text,
    site_url text,

    smtp_server_id uuid not null,
    auth_from_email text
);

/*
insert into endpoint.site_settings (name, active, site_title, site_url, smtp_server_id, auth_from_email)
values ('development', true, '[ default site title ]', 'http://localhost/','ffb6e431-daa7-4a87-b3c5-1566fe73177c', 'noreply@localhost');
*/


create function endpoint.is_indexed(_path text) returns boolean as $$
begin
    return true;
    /*
    select *
    from (
        select path, parent_id, 'directory' as type
        from filesystem.directory
        where id=_path

        union

        select path, directory_id as parent_id, 'file' as type
        from filesystem.file
        where id=_path;
    ) a;


    with recursive t as (

        select indexes, path
        from endpoint.resource_directory
        where path = _path

        union all

        select t.indexes, d.parent_id as path from t
            join filesystem.directory d on d.path = t.path

    )
    select indexes from t;
   */

    /*

    select indexes from endpoint.resource_directory where directory_id=_path;

    if indexes then
        return true;
    else
        select indexes from endpoint.resource_directory where directory_id=(select parent_id from filesystem.directory where path=_path);
    end if;

    */


/*
we start with a single url

*/
end;
$$ language plpgsql;


/******************************************************************************
 *
 *
 * UTIL FUNCTIONS
 *
 *
 ******************************************************************************/

create function endpoint.set_mimetype(
    _schema name,
    _table name,
    _column name,
    _mimetype text
) returns void as $$
    insert into endpoint.column_mimetype (column_id, mimetype_id)
    select c.id, m.id
    from meta.relation_column c
    cross join endpoint.mimetype m
    where c.schema_name   = _schema and
          c.relation_name = _table and
          c.name          = _column and
          m.mimetype = _mimetype
$$
language sql;


/******************************************************************************
 * FUNCTION columns_json
 *****************************************************************************/

create type column_type as (
    name text,
    "type" text
);

-- returns the columns for a provided schema.relation as a json object
create function endpoint.columns_json(
    _schema_name text,
    _relation_name text,
    exclude text[],
    include text[],
    out json json
) returns json as $$
    begin
        execute
            'select (''['' || string_agg(row_to_json(row(c2.name, c2.type_name)::endpoint.column_type, true)::text, '','') || '']'')::json
            from (select * from meta.relation_column c
            where c.schema_name = ' || quote_literal(_schema_name) || ' and
                c.relation_name = ' || quote_literal(_relation_name) ||
                case when include is not null then
                    ' and c.name = any(' || quote_literal(include) || ')'
                else '' end ||
                case when exclude is not null then
                    ' and not c.name = any(' || quote_literal(exclude) || ')'
                else '' end ||
            ' order by position) c2'

            into json;
    end;
$$
language plpgsql;


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
    from meta.relation_column c --TODO: either use relation_column maybe?  Or go look up the pk of a view somewhere else if we ever add that
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
    from meta.relation_column c --TODO: either use relation_column maybe?  Or go look up the pk of a view somewhere else if we ever add that
    where c.schema_name = _schema_name and
          c.relation_name = _relation_name and
          c.primary_key
$$
language sql security definer;


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
(which is old and wrong)
select endpoint.construct_join_graph('foo',
    '{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "join_local_field": "id", "where_clause": "b.id = ''e2edb6c9-cb76-4b57-9898-2e08debe99ee''" }',
    '[
        {"schema_name": "bundle", "relation_name": "commit", "label": "c", "join_local_field": "bundle_id", "related_label": "b", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset", "label": "r", "join_local_field": "id", "related_label": "c", "related_field": "rowset_id"},
        {"schema_name": "bundle", "relation_name": "rowset_row", "label": "rr", "join_local_field": "rowset_id", "related_label": "r", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "join_local_field": "rowset_row_id", "related_label": "rr", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "blob", "label": "blb", "join_local_field": "hash", "related_label": "rrf", "related_field": "value_hash"}
     ]');

here is the json equiv of a current call. which also does not work, because meta id cast to text is perhaps going wonky?  FIXME
var start_rowset = {
    schema_name: "meta",
    relation_name: "table",
    label: "t",
    join_local_field: "id",
    pk_field: "id",
    join_pk_field: "id",
    where_clause: "t.schema_name='"+schema_name+"'"
};

var subrowsets = [
    {
        schema_name: "meta",
        relation_name: "column",
        label: "c",
        pk_field: "id",
        join_local_field: "relation_id",
        related_label: "t",
        related_field: "id"
    }
];

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
        schema_name := start_rowset->>'schema_name';
        relation_name := start_rowset->>'relation_name';
        label := start_rowset->>'label';
        join_local_field := start_rowset->>'join_local_field';
        pk_field:= start_rowset->>'pk_field';

        exclude:= coalesce(start_rowset->>'exclude', 'false');
        position := coalesce(start_rowset->>'position', '0');
        where_clause := coalesce ('where ' || (start_rowset->>'where_clause')::text, ''); -- def sql injection

        raise notice '#### construct_join_graph PHASE 1:  label: %, schema_name: %, relation_name: %, join_local_field: %, pk_field: %, exclude: %, position: %, where_clause: %',
           label, schema_name, relation_name, join_local_field, pk_field, exclude, position, where_clause;

        q := 'insert into ' || tmp || ' (label, row_id, row, position, exclude)  '
            || ' select distinct ' || quote_literal(label) || ','
            || '     meta.row_id('
                || quote_literal(schema_name) || ','
                || quote_literal(relation_name) || ','
                || quote_literal(pk_field) || ','
                || quote_ident(label) || '.' || quote_ident(pk_field) || '::text), '
            || '     row_to_json(' || label || ', true)::jsonb, '
            || '     ' || position || ', '
            || '     ' || exclude::boolean
            || ' from ' || quote_ident(schema_name) || '.' || quote_ident(relation_name) || ' ' || quote_ident(label)
            || ' ' || where_clause;

        raise notice 'QUERY PHASE 1: %', q;
        execute q;


        -- load up sub-relations
        for i in 0..(json_array_length(subrowsets) - 1) loop
            rowset := subrowsets->i;

            schema_name := rowset->>'schema_name';
            relation_name := rowset->>'relation_name';
            label := rowset->>'label';
            join_local_field:= rowset->>'join_local_field';
            join_pk_field:= rowset->>'join_local_field';

            related_label := rowset->>'related_label';
            related_field := rowset->>'related_field';

            where_clause := coalesce ('where ' || (rowset->>'where_clause')::text, '');
            exclude:= coalesce(rowset->>'exclude', 'false')::boolean;

            position := coalesce((rowset->>'position')::integer, 0::integer);

            raise notice '#### construct_join_graph PHASE 2:  label: %, schema_name: %, relation_name: %, join_local_field: %, related_label: %, related_field: %, where_clause: %',
            label, schema_name, relation_name, join_local_field, related_label, related_field, where_clause;


            q := format('insert into %1$I ( label, row_id, row, position, exclude)
                select distinct %2$I,
                    meta.row_id(%3$L,%4$L,%5$L,%2$I.%7$I::text),
                    row_to_json(%2$I, true)::jsonb,
                    %8$s,
                    %6$L::boolean
                from %3$I.%4$I %2$I
                join %1$I on %1$I.label = %9$L
                and (%1$I.row)->>%10$L = %2$I.%11$I::text %12$s',
                temp_table_name, -- 1
                label,
                schema_name,
                relation_name, --4
                join_pk_field,
                exclude,
                join_pk_field,
                position, --8
                related_label,
                related_field,
                join_local_field, --11
                where_clause
            );

            raise notice 'QUERY PHASE 2: %', q;
            execute q;

        end loop;

        execute 'delete from ' || tmp || ' where exclude = true';

        execute 'select * from ' || tmp || ' order by position';
    end;
$$
language plpgsql;


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
 * FUNCTION multiple_row_insert                                                                      *
 ****************************************************************************************************/

create or replace function endpoint.multiple_row_insert(
    relation_id meta.relation_id,
    args json
) returns setof json as $$

    declare
        _schema_name text;
        _relation_name text;
        r json;
        q text;

    begin
        select (relation_id).schema_id.name into _schema_name;
        select (relation_id).name into _relation_name;

        select array_to_json(array_agg(t.json_array_elements))
        from
            (
                select json_array_elements(endpoint.row_insert(relation_id, json_array_elements)->'result')
                from json_array_elements(args)
            ) t
        into r;

        q := 'select (''{' ||
                --"columns":'' || endpoint.columns_json($1, $2) || '',
                '"result":'' || ($3) || ''
            }'')::json';

        return query execute q
        using _schema_name,
            _relation_name,
            r;
    end;

$$
language plpgsql;


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
        -- raise notice 'ROWS INSERT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
        -- raise notice 'TOTAL ROWS: %', json_array_length(args);
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
        _schema_name := (relation_id::meta.schema_id).name;
        _relation_name := (relation_id).name;

        q := '
            with inserted_row as (
                insert into ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) ||
                case when args::text = '{}'::text then
                    ' default values '
                else
                    ' (' || (
                        select string_agg(quote_ident(json_object_keys), ',' order by json_object_keys)
                        from json_object_keys(args)

                    ) || ') values (' || (
                           select string_agg('
                                   case when json_typeof($3->' || quote_literal(json_object_keys) || ') = ''array'' then ((
                                            select ''{'' || string_agg(value::text, '', '') || ''}''
                                            from json_array_elements(($3->>' || quote_literal(json_object_keys) || ')::json)
                                        ))
                                        when json_typeof($3->' || quote_literal(json_object_keys) || ') = ''object'' then
                                            ($3->' || quote_literal(json_object_keys) || ')::text
                                        else ($3->>' || quote_literal(json_object_keys) || ')::text
                                   end::' || case when json_typeof((args->json_object_keys)) = 'object' then 'json::'
                                                  else ''
                                             end || c.type_name, ',
                                   '
                                   order by json_object_keys
                           ) from json_object_keys(args)
                           inner join meta.relation_column c
                                   on c.schema_name = _schema_name and
                                      c.relation_name = _relation_name and
                                      c.name = json_object_keys
                           left join meta.type t on c.type_id = t.id
                    ) || ') '
                end ||
                'returning *
            )
            select (''{
                "columns": ' || endpoint.columns_json(_schema_name, _relation_name, null::text[], null::text[]) || ',
                "pk":"' || coalesce(endpoint.pk_name(_schema_name, _relation_name), 'null') || '",
                "result": [{ "row": '' || row_to_json(inserted_row.*, true) || '' }]
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
$$
immutable language plpgsql;
*/


/****************************************************************************************************
 * FUNCTION is_json_object                                                                          *
 ****************************************************************************************************/

create or replace function endpoint.is_json_object(
    value text
) returns boolean as $$

    begin
        if value is null then return false; end if;
        perform json_object_keys(value::json);
        return true;

        exception when invalid_parameter_value then
            return false;
        when invalid_text_representation then
            return false;
    end;
$$
immutable language plpgsql;


/****************************************************************************************************
 * FUNCTION is_json_array                                                                           *
 ****************************************************************************************************/

create function endpoint.is_json_array(
    value text
) returns boolean as $$

    begin
        perform json_array_length(value::json);
        return true;

        exception when invalid_parameter_value then
            return false;
        when invalid_text_representation then
            return false;
    end;
$$
immutable language plpgsql;


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
                               case when json_typeof($1->' || quote_literal(json_object_keys) || ') = ''array'' then ((
                                        select ''{'' || string_agg(value::text, '', '') || ''}''
                                        from json_array_elements(($1->>' || quote_literal(json_object_keys) || ')::json)
                                    ))
                                    when json_typeof($1->' || quote_literal(json_object_keys) || ') = ''object'' then
                                        ($1->' || quote_literal(json_object_keys) || ')::text
                                    else ($1->>' || quote_literal(json_object_keys) || ')::text
                               end::' || case when json_typeof((args->json_object_keys)) = 'object' then 'json::'
                                              else ''
                                         end || c.type_name, ',
                           '
                       ) from json_object_keys(args)
                       inner join meta.relation_column c
                               on c.schema_name = _schema_name and
                                  c.relation_name = _relation_name and
                                  c.name = json_object_keys
                   ) || ' where ' || (
                       select 'r.' || quote_ident((row_id).pk_column_id.name) || ' = ' || quote_literal((row_id).pk_value)
                   )
        ) using args;

        return '{}';
    end;
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION row_select                                                                              *
 ****************************************************************************************************/

create function endpoint.row_select(
    row_id meta.row_id,
    args json
) returns json as $$

    declare
        _schema_name text;
        _relation_name text;
        pk_column_name text;
        pk text;

        row_query text;
        row_json text;
        columns_json text;

        exclude text[];
        include text[];
        column_list text;

    begin
        -- raise notice 'ROW SELECT ARGS: %, %, %, %', schema_name, table_name, queryable_type, pk;
        set local search_path = endpoint;

        select (row_id::meta.schema_id).name into _schema_name;
        select (row_id::meta.relation_id).name into _relation_name;
        select (row_id).pk_column_id.name into pk_column_name;
        select row_id.pk_value into pk;


        -- Column list
        -- Exclude
        select array_agg(val)
        from ((
            select json_array_elements_text(value::json) as val
            from json_array_elements_text(args->'exclude')
        )) q
        into exclude;

        -- Include
        select array_agg(val)
        from ((
            select json_array_elements_text(value::json) as val
            from json_array_elements_text(args->'include')
        )) q
        into include;

        if exclude is not null or include is not null then
            select endpoint.column_list(_schema_name, _relation_name, '', exclude, include) into column_list;
        else
            select '*' into column_list;
        end if;


        row_query := 'select ''[{"row": '' || row_to_json(t.*, true) || ''}]'' from ' ||
                        '(select ' || column_list || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) ||
                        ' where ' || quote_ident(pk_column_name) || '=' || quote_literal(pk) ||
                            (
                                select '::' || c.type_name
                                from meta.relation_column c
                                where c.schema_name = _schema_name and
                                   c.relation_name = _relation_name and
                                   c.name = pk_column_name -- FIXME column integration
                            ) ||
                    ') t';
/*
-- This pk lookup only works if relation has a primary key in meta.column... what about foreign tables and views?
-- Also foreign data does not show up unless you use a subquery to get it to run first... Not sure why

        row_query := 'select ''[{"row": '' || row_to_json(t.*) || ''}]'' from '
                     || quote_ident(schema_name) || '.' || quote_ident(relation_name)
                     || ' as t where ' || (
                         select quote_ident(pk_name) || ' = ' || quote_literal(pk) || '::' || pk_type
                         from endpoint.pk(schema_name, relation_name) p
                     );
*/
        execute row_query into row_json;

        --return '{"columns":' || columns_json(_schema_name, _relation_name) || ',"result":' || coalesce(row_json::text, '[]') || '}';
        return '{' ||
               case when args->>'meta_data' = '["true"]' then
                   '"columns":' || endpoint.columns_json(_schema_name, _relation_name, exclude, include) || ',' ||
                   '"pk":"' || endpoint.pk_name(_schema_name, _relation_name) || '",'
               else ''
               end ||
               '"result":' || coalesce(row_json::text, '[]') || '}';
    end;
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION field_select                                                                            *
 ****************************************************************************************************/

create or replace function endpoint.field_select(
    field_id meta.field_id,
    out field text,
    out mimetype text
) returns record as $$

    declare
        _schema_name text;
        _relation_name text;
        pk text;
        pk_column_name text;
        pk_type text;
        field_name text;
        field_type text;

    begin
        -- raise notice 'FIELD SELECT ARGS: %, %, %, %, %', schema_name, table_name, queryable_type, pk, field_name;
        set local search_path = endpoint;

        select (field_id).column_id.relation_id.schema_id.name into _schema_name;
        select (field_id).column_id.relation_id.name into _relation_name;
        select (field_id).row_id.pk_value into pk;
        select (field_id).row_id.pk_column_id.name into pk_column_name;
        select (field_id).column_id.name into field_name;

        -- Find pk_type
        select type_name
        from meta.column
        where id = (field_id).row_id.pk_column_id
        into pk_type;

        -- Find field_type
        select type_name
        from meta.column
        where schema_name = _schema_name
            and relation_name = _relation_name
            and name = field_name
        into field_type;

        if field_type <> 'endpoint.resource_bin' then
            -- Find mimetype for this field
            select m.mimetype
            from endpoint.column_mimetype cm
                join endpoint.mimetype m on m.id = cm.mimetype_id
            where cm.column_id = (field_id).column_id
            into mimetype;
        end if;

        -- Default mimetype
        mimetype := coalesce(mimetype, 'application/json');
        if field_type = 'endpoint.resource_bin' then
            execute 'select (' || quote_ident(field_name) || ').mimetype, encode((' || quote_ident(field_name) || ').content, ''escape'')'
                || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where ' || quote_ident(pk_column_name) || ' = ' || quote_literal(pk) || '::' || pk_type into mimetype, field;
        elsif field_type = 'pg_catalog.bytea' then
            execute 'select encode(' || quote_ident(field_name) || ', ''escape'') from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where ' || quote_ident(pk_column_name) || ' = ' || quote_literal(pk) || '::' || pk_type into field;
        else
            execute 'select ' || quote_ident(field_name) || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where ' || quote_ident(pk_column_name) || ' = ' || quote_literal(pk) || '::' || pk_type into field;
        end if;

        -- implicitly returning field and mimetype
    end;
$$
language plpgsql;


/****************************************************************************************************
 *
 * FUNCTION suffix_clause
 *
 * Builds limit, offset, order by, and where clauses from json
 *
 ****************************************************************************************************/

create or replace function endpoint.suffix_clause(
    args json
) returns text as $$

    declare
        _limit text := '';
        _offset text := '';
        _order_by text := '';
        _where text := 'where true';
        r record;

    begin
        for r in select * from json_each(args) loop

            -- Limit clause
            -- URL
            -- /endpoint?$limit=10
            if r.key = 'limit' then
                select ' limit ' || quote_literal(json_array_elements_text)
                from json_array_elements_text(r.value::text::json)
                into _limit;

            -- Offset clause
            -- URL
            -- /endpoint?$offest=5
            elsif r.key = 'offset' then
                select ' offset ' || quote_literal(json_array_elements_text)
                from json_array_elements_text(r.value::text::json)
                into _offset;

            -- Order by clause
            -- URL
            -- /endpoint?$order_by=city
            -- /endpoint?$order_by=[city,-state,-full_name]
            elsif r.key = 'order_by' then
                if pg_typeof(r.value) = 'json'::regtype then
                    select ' order by ' ||
                        string_agg(case substring(q.val from 1 for 1)
                                       when '-' then substring(q.val from 2) || ' desc'
                                       else q.val end,
                        ', ')
                    from (select json_array_elements_text as val from json_array_elements_text(r.value)) q
                    into _order_by;
                else
                    select ' order by ' ||
                        case substring(r.value::text from 1 for 1)
                            when '-' then substring(r.value::text from 2) || ' desc'
                            else r.value::text
                            end
                    into _order_by;
                end if;

            -- Where clause
            -- URL
            -- /endpoint?$where={name=NAME1,op=like,value=VALUE1}
            -- /endpoint?$where=[{name=NAME1,op=like,value=VALUE1},{name=NAME2,op='=',value=VALUE2}]
            elsif r.key = 'where' then

                if pg_typeof(r.value) = 'json'::regtype then

                    if json_typeof(r.value) = 'array' then -- { where: JSON array }

                        /*
                        select json->>'name' as name, json->>'op' as op, json->>'value' as value from
                            (select json_array_elements_text(value)::json as json from
                                (( select value from json_each('{"where": ["{\"name\":\"bundle_name\",\"op\":\"=\",\"value\":\"com.aquameta.core.ide\"}", "{\"name\":\"name\",\"op\":\"=\",\"value\":\"development\"}"]}'))
                                ) v)
                            b;
                        */
                        select _where || ' and ' || string_agg( quote_ident(name) || ' ' || op || ' ' ||


                            case when op = 'in' then
                                -- Value is array
                                case when json_typeof(json) = 'array' then
                                   (select '(' || string_agg(quote_literal(array_val), ',') || ')'
                                   from json_array_elements_text(json) as array_val)
                                -- Value is object
                                when json_typeof(json) = 'object' then
                                   quote_literal(json) || '::json'
                                else
                                    quote_literal(value)
                                end
                            else
                                quote_literal(value)
                            end

                            , ' and ' )

                        from (
                            select element->>'name' as name, element->>'op' as op, element->'value' as json, element->>'value' as value
                            from (select json_array_elements_text::json as element from json_array_elements_text(r.value)) j
                            ) v
                        into _where;

                    elsif json_typeof(r.value) = 'object' then -- { where: JSON object }
                        select _where || ' and ' || quote_ident(name) || ' ' || op || ' ' ||

                            case when op = 'in' then
                                -- Value is array
                                case when json_typeof(value::json) = 'array' then
                                   (select '(' || string_agg(quote_literal(array_val), ',') || ')'
                                   from json_array_elements_text(value::json) as array_val)
                                -- Value is object
                                when json_typeof(value::json) = 'object' then
                                   quote_literal(value) || '::json'
                                else
                                    quote_literal(value)
                                end
                            end

                        from json_to_record(r.value::json) as x(name text, op text, value text)
                        into _where;

                    end if;

                else -- Else { where: regular value } -- This is not used in the client

                    select _where || ' and ' || quote_ident(name) || ' ' || op || ' ' || quote_literal(value)
                    from json_to_record(r.value::json) as x(name text, op text, value text)
                    into _where;

                end if;

            else
            end if;
        end loop;
        return  _where || _order_by || _limit || _offset;
    end;
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION column_list
 ****************************************************************************************************/

create function endpoint.column_list(
    _schema_name text,
    _relation_name text,
    table_alias text,
    exclude text[],
    include text[],
    out column_list text
) as $$
    begin
        if table_alias = '' then
            table_alias := _schema_name || '.' || _relation_name;
        end if;

        execute
            'select string_agg(' || quote_literal(table_alias) || ' || ''.'' || name, '', '')
            from meta.relation_column
            where schema_name = ' || quote_literal(_schema_name) || ' and
                relation_name = ' || quote_literal(_relation_name) ||
                case when include is not null then
                    ' and name = any(' || quote_literal(include) || ')'
                else '' end ||
                case when exclude is not null then
                    ' and not name = any(' || quote_literal(exclude) || ')'
                else '' end
            -- || ' group by position order by position' wrong.
            into column_list;

    end;
$$ language plpgsql;


/****************************************************************************************************
 * FUNCTION rows_select                                                                             *
 ****************************************************************************************************/

create function endpoint.rows_select(
    relation_id meta.relation_id,
    args json
) returns json as $$
    declare
        schema_name text;
        relation_name text;
        row_query text;
        rows_json text;
        suffix text;
        exclude text[];
        include text[];
        column_list text;

    begin
        select (relation_id).schema_id.name into schema_name;
        select (relation_id).name into relation_name;

        -- Suffix
        select endpoint.suffix_clause(args) into suffix;

        -- Column list
        -- Exclude
        select array_agg(val)
        from ((
            select json_array_elements_text(value::json) as val
            from json_array_elements_text(args->'exclude')
        )) q
        into exclude;

        -- Include
        select array_agg(val)
        from ((
            select json_array_elements_text(value::json) as val
            from json_array_elements_text(args->'include')
        )) q
        into include;

        if exclude is not null or include is not null then
            select endpoint.column_list(schema_name, relation_name, 'r'::text, exclude, include) into column_list;
        else
            select 'r.*' into column_list;
        end if;

        row_query := 'select ''['' || string_agg(q.js, '','') || '']'' from (
                          select ''{ "row":'' || row_to_json(t.*, true) || '' }'' js
                          from ((select ' || column_list || ' from ' || quote_ident(schema_name) || '.' || quote_ident(relation_name) || ' r ' || suffix || ')) as t
                     ) q';

        execute row_query into rows_json;

        return '{' ||
               case when args->>'meta_data' = '["true"]' then
                   '"columns":' || endpoint.columns_json(schema_name, relation_name, exclude, include) || ',' ||
                   '"pk":"' || coalesce(endpoint.pk_name(schema_name, relation_name), 'null') || '",'
               else ''
               end ||
               '"result":' || coalesce(rows_json, '[]') || '}';
    end;
$$
language plpgsql;


/******************************************************************************
 * FUNCTION rows_select_function

some_function?args={ vals: [] } -- Array
some_function?args={ kwargs: {} } -- Key/value object
some_function?args={ kwargs: {} }&column=name

This function should do some much smarter stuff with return type
Should be able to select a single column when not returning SETOF
Some of the logic from the column-specific rows_select_function()
We also want to use column_mimetype if we are only sending one column back

 *****************************************************************************/

create function endpoint.rows_select_function(
    function_id meta.function_id,
    args json,
    out result text,
    out mimetype text
) returns record as $$

    declare
        _function_id alias for function_id;
        function_return_type text;
        row_is_composite boolean;
        columns_json text;
        function_args text;
        _row record;
        rows_json text[];
        suffix text;
        return_column text;
        meta_data text;
        result_type text;

    begin
        -- Get function row
        select return_type
        from meta.function f
        where f.schema_name = (_function_id).schema_id.name
            and f.name = (_function_id).name
            and f.parameters = (_function_id).parameters
        into function_return_type;

        -- Meta data
        meta_data := args->>'meta_data';
        if meta_data = '["true"]' then

            -- Find is return type is composite
            select t.composite
            from meta.function f
                join meta.type t on t.id = f.return_type_id
            where f.id = _function_id
            into row_is_composite;


            -- Build columns_json
            if row_is_composite or result_type = 'record' then

              select string_agg(row_to_json(q.*, true)::text, ',')
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
                    where pgt.oid = function_return_type::regtype
                        and pga.attname not in ('tableoid','cmax','xmax','cmin','xmin','ctid')
              ) q
              into columns_json;

            else

                select row_to_json(q.*)
                from (select (_function_id).name as name, function_return_type as "type") q
                into columns_json;

            end if;
        end if;

        -- Suffix clause: where, order by, offest, limit
        suffix := endpoint.suffix_clause(args);

        -- Return column
        return_column := json_array_elements_text(args->'column');

        -- Args
        select json_array_elements_text::json
        from json_array_elements_text(args->'args') into args;

        -- Function Arguments
        if args->'kwargs' is not null then

            -- Build function arguments string
            -- Cast to type_name found in meta.function_parameter
            -- Using coalesce(function_args, '') so we can call function without arguments
            select coalesce(
                string_agg(quote_ident(r.key) || ':=' ||
                case when -- pg_typeof(r.value) = 'json'::regtype and
                    json_typeof(r.value) = 'object' then
                    quote_literal(r.value) || '::json::'
                else
                    quote_literal(btrim(r.value::text, '"')) || '::'
                end ||
                fp.type_name, ','),
            '')
            from json_each(args->'kwargs') r
                join meta.function_parameter fp on
                    fp.schema_name = (_function_id).schema_id.name and -- Trick to speed up query
                    fp.function_id = _function_id and
                    fp.name = r.key
            into function_args;

        elsif args->'vals' is not null then
            -- Transpose JSON array to comma-separated string
            select string_agg(quote_literal(value), ',')
            from json_array_elements_text(args->'vals') into function_args;
        else
            -- No arguments
            select '' into function_args;
        end if;


        if return_column is null then

            -- Default mimetype
            mimetype := 'application/json';

            /*** FIXME: this is broken */

            -- Loop through function call results
            for _row in execute 'select * from ' || quote_ident((_function_id).schema_id.name) || '.' || quote_ident((_function_id).name)
                                || '(' || function_args || ') ' || suffix
            loop
                rows_json := array_append(rows_json, '{ "row": ' || row_to_json(_row, true) || ' }');
            end loop;

            -- Result JSON object
            select '{' ||
                case when meta_data = '["true"]' then
                    '"columns":[' || columns_json || '],'
                else ''
                end ||
                '"result":' || coalesce('[' || array_to_string(rows_json,',') || ']', '[]') || '}'
             into result;

        else

            execute 'select ' || return_column || ', pg_typeof(' || return_column || ') from ' ||
                quote_ident((_function_id).schema_id.name) || '.' || quote_ident((_function_id).name) ||
                '(' || function_args || ') ' || suffix into result, result_type;

            if result_type <> 'resource_bin' and result_type <> 'endpoint.resource_bin' then

                -- Get mimetype
                select m.mimetype
                from endpoint.function_field_mimetype ffm
                    join endpoint.mimetype m on m.id = ffm.mimetype_id
                where ffm.schema_name = (_function_id).schema_id.name
                    and ffm.function_name = (_function_id).name
                    and field_name = return_column
                into mimetype;

                -- Default mimetype
                mimetype := coalesce(mimetype, 'application/json');

                if result_type = 'bytea' or result_type = 'pg_catalog.bytea' then
                    result := encode(result::bytea, 'escape');
                end if;

            else

                mimetype := (result::endpoint.resource_bin).mimetype;
                result := encode((result::endpoint.resource_bin).content, 'escape');

            end if;

        end if;


        -- implicitly returning function result and mimetype

    end;
$$
language plpgsql;


create function endpoint.anonymous_rows_select_function(
    _schema_name text,
    _function_name text,
    args json,
    out result text,
    out mimetype text
) returns record as $$

    declare
        _mimetype alias for mimetype;
        columns_json text;
        function_args text;
        suffix text;
        _row record;
        rows_json text[];
        return_column text;
        result_type text;

    begin
        -- Build columns_json TODO ?
        columns_json := '';

        -- Return column
        return_column := json_array_elements_text(args->'column');

        -- Suffix clause: where, order by, offest, limit
        suffix := endpoint.suffix_clause(args);

        -- Args
        select json_array_elements_text::json
        from json_array_elements_text(args->'args') into args;

        -- Function Arguments
        if  args->'vals' is not null then
            -- Transpose JSON array to comma-separated string
            select string_agg(quote_literal(value), ',') from json_array_elements_text(args->'vals') into function_args;
        else
            -- No arguments
            function_args := '';
        end if;

        if return_column is null then

            -- Default mimetype
            mimetype := 'application/json';

            -- Loop through function call results
            for _row in execute 'select * from ' || quote_ident(_schema_name) || '.' || quote_ident(_function_name)
                                || '(' || function_args || ') ' || suffix
            loop
                rows_json := array_append(rows_json, '{ "row": ' || row_to_json(_row, true) || ' }');
            end loop;

            -- Result JSON object
            select '{"result":' || coalesce('[' || array_to_string(rows_json,',') || ']', '[]') || '}' into result;

        else

            execute 'select ' || return_column || ', pg_typeof(' || return_column || ') from ' || quote_ident(_schema_name) || '.' || quote_ident(_function_name)
                                || '(' || function_args || ') ' || suffix into result, result_type;

            if result_type <> 'resource_bin' and result_type <> 'endpoint.resource_bin' then

                -- Get mimetype
                select m.mimetype
                from endpoint.function_field_mimetype ffm
                    join endpoint.mimetype m on m.id = ffm.mimetype_id
                where ffm.schema_name = _schema_name
                    and ffm.function_name = _function_name
                    and field_name = return_column
                into mimetype;

                -- Default mimetype
                mimetype := coalesce(mimetype, 'application/json');

                if result_type = 'bytea' or result_type = 'pg_catalog.bytea' then
                    result := encode(result::bytea, 'escape');
                end if;

            else

                mimetype := (result::endpoint.resource_bin).mimetype;
                result := encode((result::endpoint.resource_bin).content, 'escape');

            end if;

        end if;

        -- implicitly returning function result and mimetype
    end;
$$
language plpgsql;


-- This function should disappear. Factor column selection into previous rows_select_function()
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

            select string_agg(row_to_json(q.*, true)::text, ',')
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

            select row_to_json(q.*, true)
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
        _schema_name text;
        _table_name text;
        pk text;

    begin
        select (row_id::meta.schema_id).name into _schema_name;
        select (row_id::meta.relation_id).name into _table_name;
        select row_id.pk_value::text into pk;

        execute 'delete from ' || quote_ident(_schema_name) || '.' || quote_ident(_table_name) ||
                ' where ' || (
                    select quote_ident(c.name) || ' = ' || quote_literal(pk) || '::' || c.type_name
                    from meta.relation_column c
                    where schema_name = _schema_name
                       and relation_name = _table_name
                       and name = (row_id).pk_column_id.name
                );

        return '{}';
    end;

$$
language plpgsql;

/****************************************************************************************************
 * FUNCTION rows_delete                                                                             *
 ****************************************************************************************************/

create function endpoint.rows_delete(
    relation_id meta.relation_id,
    args json
) returns json as $$

    declare
        _schema_name text;
        _table_name text;
        pk text;
        suffix text;

    begin
        select (relation_id::meta.schema_id).name into _schema_name;
        select (relation_id::meta.relation_id).name into _table_name;

        -- Suffix
        select endpoint.suffix_clause(args) into suffix;

        execute 'delete from ' || quote_ident(_schema_name) || '.' || quote_ident(_table_name) || ' ' || suffix;

        return '{}';
    end;

$$
language plpgsql;

/****************************************************************************************************
 * FUNCTION request
 ****************************************************************************************************/

create or replace function endpoint.request(
    version text,
    verb text,
    path text,
    query_args json,
    post_data json,
    out status integer,
    out message text,
    out response text,
    out mimetype text
) returns setof record as $$

    declare
        session_id uuid; -- null if not evented
        row_id meta.row_id;
        relation_id meta.relation_id;
        function_id meta.function_id;
        field_id meta.field_id;
        relation_subscribable boolean;
        op text;
        op_params text;

    begin
        set local search_path = endpoint,meta,public;

        -- GET/POST requests are synonymous. Long query strings are converted to POST in the client
        -- We will only be subscribing to something on a GET or POST request
        if verb = 'GET' then

            -- Look for session_id in query string
            select btrim(json_array_elements_text, '"')::uuid
            from json_array_elements_text(query_args->'session_id')
            into session_id;

        elsif verb = 'POST' then

            -- Look for session_id in post data
            select btrim(json_array_elements_text, '"')::uuid
            from json_array_elements_text(post_data->'session_id')
            into session_id;

        end if;

        op := substring(path from '([^/]+)(/{1})'); -- row, relation, function, etc.
        op_params := substring(path from char_length(op) + 2); -- everything after {op}/

        raise notice '##### endpoint.request % % %', version, verb, path;
        raise notice '##### op and params: % %', op, op_params;
        raise notice '##### query string args: %', query_args::text;
        raise notice '##### POST data: %', post_data::text;

        case op
        when 'row' then

            -- URL /endpoint/row/{row_id}
            row_id := op_params::meta.row_id;

            if verb = 'GET' then

                -- Subscribe to row
                if session_id is not null then
                    perform event.subscribe_row(session_id, row_id);
                end if;

                -- Get single row
                return query select 200, 'OK'::text, (select endpoint.row_select(row_id, query_args))::text, 'application/json'::text;

            elsif verb = 'POST' then

                -- Subscribe to row
                if session_id is not null then
                    perform event.subscribe_row(session_id, row_id);
                end if;

                -- Get single row
                return query select 200, 'OK'::text, (select endpoint.row_select(row_id, post_data))::text, 'application/json'::text;

            elsif verb = 'PATCH' then

                -- Update row
                return query select 200, 'OK'::text, (select endpoint.row_update(row_id, post_data))::text, 'application/json'::text;

            elsif verb = 'DELETE' then

                -- Delete row
                return query select 200, 'OK'::text, (select endpoint.row_delete(row_id))::text, 'application/json'::text;

            else
                -- HTTP method not allowed for this resource: 405
                return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;
            end if;

        when 'relation' then

            -- URL /endpoint/relation/{relation_id}
            relation_id := op_params::meta.relation_id;

            if verb = 'GET' then

                -- Subscribe to relation
                if session_id is not null then

                    -- TODO: Fix when views become subscribable
                    -- If relation is subscribable
                    select type='BASE TABLE' from meta.relation where id = relation_id into relation_subscribable;
                    if relation_subscribable then
                        perform event.subscribe_table(session_id, relation_id);
                    end if;

                end if;

                -- Get rows
                return query select 200, 'OK'::text, (select endpoint.rows_select(relation_id, query_args))::text, 'application/json'::text;

            elsif verb = 'POST' then

                -- Subscribe to relation
                if session_id is not null then

                    -- TODO: Fix when views become subscribable
                    -- If relation is subscribable
                    select type='BASE TABLE' from meta.relation where id = relation_id into relation_subscribable;
                    if relation_subscribable then
                        perform event.subscribe_table(session_id, relation_id);
                    end if;

                end if;

                -- Get rows
                return query select 200, 'OK'::text, (select endpoint.rows_select(relation_id, post_data))::text, 'application/json'::text;

            elsif verb = 'PATCH' then

                if json_typeof(post_data) = 'object' then
                    -- Insert single row
                    return query select 200, 'OK'::text, (select endpoint.row_insert(relation_id, post_data))::text, 'application/json'::text;
                elsif json_typeof(post_data) = 'array' then
                    -- Insert multiple rows
                    return query select 200, 'OK'::text, (select endpoint.multiple_row_insert(relation_id, post_data))::text, 'application/json'::text;
                end if;

            elsif verb = 'DELETE' then

                -- Delete rows
                return query select 200, 'OK'::text, (select endpoint.rows_delete(relation_id, query_args))::text, 'application/json'::text;

            else
                -- HTTP method not allowed for this resource: 405
                return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;
            end if;

        when 'function' then

            -- If function is called without a parameter type list
            if array_length((string_to_array(op_params, '/')), 1) = 2 then

                op_params := op_params || '/{}';
                function_id := op_params::meta.function_id;

                if verb = 'GET' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.anonymous_rows_select_function((function_id::meta.schema_id).name, function_id.name, query_args) as rsf;

                elsif verb = 'POST' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.anonymous_rows_select_function((function_id::meta.schema_id).name, function_id.name, post_data) as rsf;

                else
                    -- HTTP method not allowed for this resource: 405
                    return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;

                end if;

            -- Calling a function with a specified parameter type list -- Exact function id known
            else

                -- URL /endpoint/function/{function_id}
                function_id := op_params::meta.function_id;

                if verb = 'GET' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.rows_select_function(function_id, query_args) as rsf;

                elsif verb = 'POST' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.rows_select_function(function_id, post_data) as rsf;

                else
                    -- HTTP method not allowed for this resource: 405
                    return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;

                end if;

            end if;

        when 'field' then

            -- URL /endpoint/field/{field_id}
            field_id := op_params::meta.field_id;

            if verb = 'GET' or verb = 'POST' then

                -- Subscribe to field
                if session_id is not null then
                    perform event.subscribe_field(session_id, field_id);
                end if;

                -- Get field
                return query select 200, 'OK'::text, fs.field::text, fs.mimetype::text from endpoint.field_select(field_id) as fs;

            else
                -- HTTP method not allowed for this resource: 405
                return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;
            end if;

        else
            -- Resource not found: 404
            return query select 404, 'Not Found'::text, ('{"status_code": 404, "title": "Not Found"}')::text, 'application/json'::text;

        end case;

        exception when undefined_table then
        return query select 404, 'Not Found'::text, ('{"status_code": 404, "title": "Not Found", "message":"'|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}')::text, 'application/json'::text;

    end;
$$
language plpgsql;


/******************************************************************************
 * endpoint.user
 ******************************************************************************/

create table endpoint.user (
    id uuid not null default public.uuid_generate_v4() primary key,
    role_id meta.role_id not null default public.uuid_generate_v4()::text::meta.role_id,
    email text not null unique,
    name text not null default '',
    active boolean not null default false,
    activation_code uuid not null default public.uuid_generate_v4(),
    created_at timestamp not null default now()
);


/*

regarding triggers on the user table:
this behavior appears to be wrong.  user should be considered a metadata table
on role.  i could see creating a new role when you insert into user (which is
what the insert trigger does) but switching a user from one role to the other
should actually create that role.

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
        insert into meta.role(name, can_login, inherit) values((NEW.role_id).name, true, true);

        return NEW;
    end;
$$
language plpgsql;


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

                    -- This could be accomplished with one query?:
                    -- update meta.role set id = NEW.role_id where id = OLD.role_id;

        end if;

        return NEW;
    end;
$$
language plpgsql;


-- Trigger on endpoint.user for delete
create or replace function endpoint.user_delete() returns trigger as $$
    begin
        -- Delete old role
        delete from meta.role where id = OLD.role_id;
        return OLD;
    end;
$$
language plpgsql;


create trigger endpoint_user_insert_trigger before insert on endpoint.user for each row execute procedure endpoint.user_insert();
create trigger endpoint_user_update_trigger before update on endpoint.user for each row execute procedure endpoint.user_update();
create trigger endpoint_user_delete_trigger before delete on endpoint.user for each row execute procedure endpoint.user_delete();
*/


/******************************************************************************
 * endpoint.current_user
 ******************************************************************************/

-- create view endpoint."current_user" AS SELECT "current_user"() AS "current_user";
create view endpoint."current_user" as
    SELECT id, role_id, email, name from endpoint."user" where role_id=current_user::text::meta.role_id;

create function endpoint."current_user"() returns uuid as $$
    SELECT id from endpoint."user" as "current_user"  where role_id=current_user::text::meta.role_id;
$$ language sql;


/******************************************************************************
 * endpoint.session
 ******************************************************************************/

create table endpoint.session (
    id uuid not null default public.uuid_generate_v4() primary key,
    role_id meta.role_id not null,
    user_id uuid references endpoint.user(id) on delete cascade
);

create function endpoint.session(session_id uuid)
returns setof endpoint.session as $$
    select * from endpoint.session where id=session_id;
$$
language sql security definer;


/******************************************************************************
 * endpoint.register
 ******************************************************************************/

create function endpoint.register (_email text,
    _password text,
    fullname text default '',
    send_email boolean default true,
    out code integer,
    out message text,
    out role_name text
) returns record language plpgsql strict security definer
as $$

    declare
	_user_row record;
        _role_id meta.role_id;

    begin
        begin
            insert into endpoint.user (email, name, active) values (_email, fullname, false) returning * into _user_row;
        exception when others then
            code := 1;
            message := 'A user with this email address already exists';
            role_name := null;
            return;
        end;

        select (_user_row.role_id).name into _role_id;

        -- Set role password
        update meta.role set password = _password where id = _role_id;

        -- Inherit from generic user
        insert into meta.role_inheritance (role_id, member_role_id) values (meta.role_id('user'), _role_id);

        -- Send email to {email}
/*
        if send_email = true then
            perform email.send(
                (select smtp_server_id from endpoint.site_settings where active=true),
                (select auth_from_email from endpoint.site_settings where active=true),
                array[_user_row.email],
                'Activate your new account',
                'Use this code to activate your account ' || _user_row.activation_code
            );
        end if;
*/

        code := 0;
        role_name := (_role_id).name;
        message := 'Success';
    end
$$;


/******************************************************************************
 * endpoint.register_confirm
 ******************************************************************************/

create function endpoint.register_confirm (_email text, _confirmation_code text, send_email boolean default true) returns void
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
        update endpoint.user set active=true, activation_code=null::uuid where email=_email and activation_code=_confirmation_code::uuid returning (role_id).name into _role_id;


        -- 3. update role set login=true
        update meta.role set can_login = true where id = _role_id;

        -- 4. send email?
/*
        if send_email then
            perform email.send(
                (select smtp_server_id from endpoint.site_settings where active=true),
                (select auth_from_email from endpoint.site_settings where active=true),
                array[_user_row.email],
                'Welcome!',
                'Your account is now active.'
            );
        end if;
*/

        return;
    end
$$;


/******************************************************************************
 * endpoint.register_superuser
 ******************************************************************************/

create function endpoint.register_superuser (
    _email text,
    _password text,
    fullname text,
    role_name text,
    out code integer,
    out message text
) returns record language plpgsql
as $$
    begin
        begin
            insert into endpoint.user (email, name, active, role_id) values (_email, fullname, true, meta.role_id(role_name));
        exception when others then
            code := 1;
            message := 'A user with this email address or role already exists';
            role_name := null;
            return;
        end;

        -- Set role password and superuser
        update meta.role
            set superuser=true, password = _password
            where id = meta.role_id(role_name);

        -- Inherit from generic user
        insert into meta.role_inheritance (role_id, member_role_id) values (meta.role_id('user'), meta.role_id(role_name));

        code := 0;
        message := 'Success';
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
 * endpoint.superuser
 ******************************************************************************/

create function endpoint.superuser (_email text) returns void
    language sql strict security invoker
as $$
    insert into meta.role_inheritance (role_name, member_role_name) values ('aquameta', (select (role_id).name from endpoint."user" where email=_email));
    update meta.role set superuser=true where name=(select (role_id).name from endpoint."user" where email=_email);
$$;


/******************************************************************************
 * endpoint.email
 ******************************************************************************/

/*
create function endpoint.email (from_email text, to_email text[], subject text, body text) returns void as $$

# -- Import smtplib for the actual sending function
import smtplib
from email.mime.text import MIMEText

# -- Create the container (outer) email message.
msg = MIMEText(body)
msg['Subject'] = subject
msg['From'] = from_email
msg['To'] = ', '.join(to_email)

# -- Send the email via our own SMTP server.
s = smtplib.SMTP("localhost")
s.sendmail(from_email, to_email, msg.as_string())
s.quit()

$$ language plpythonu;
*/



/*******************************************************************************
 * template stuff
 * templates can be invoked in two ways:
 *
 * - via template_route
 * - from one template, via a call to the template() function
 *
 */


/*******************************************************************************
 * bundled_template()
 * grabs a template by bundle_name + name
 *******************************************************************************/

create or replace function endpoint.bundled_template (
    bundle_name text,
    template_name text
) returns setof endpoint.template as $$
        select t.*
        from bundle.bundle b
            join bundle.tracked_row tr on tr.bundle_id=b.id
            join endpoint.template t on t.id = (tr.row_id).pk_value::uuid
        where ((tr.row_id)::meta.schema_id).name = 'endpoint'
            and ((tr.row_id)::meta.relation_id).name = 'template'
            and t.name=template_name
            and b.name = bundle_name
$$ language sql;



/*******************************************************************************
 * FUNCTION template_render
 * Renders a template
 *******************************************************************************/

/*
create or replace function endpoint.template_render(
    template_id uuid,
    route_args json default '{}', -- these are the args passed in from the template_route record
    url_args json default '[]' -- these are args that matched a regex part in parentheses
) returns text as $$
    // fetch the template
    var template;
    try {
        var template_rows = plv8.execute('select * from endpoint.template where id=$1', [ template_id ]);
        template_row = template_rows[0];
        plv8.elog(NOTICE, ' template is ' + template_row.id);
    }
    catch( e ) {
        plv8.elog( ERROR, e, e);
        return false;
    }
    plv8.elog(NOTICE, 'template '+template_row.name+' called with route_args '+JSON.stringify(route_args)+', url_args'+JSON.stringify(url_args));

    // setup javascript scope
    var context = {};
    // url_args is an array of vals extracted from the matching url_pattern
    context.url_args = url_args;
    // route_args is an object passed in from template_route.args json
    for (var key in route_args) { context[key] = route_args[key]; }
    plv8.elog(NOTICE, 'context set to '+JSON.stringify(context));

    // doT.js
    var doT_rows = plv8.execute("select * from endpoint.js_module where name='doT'");
    eval( doT_rows[0].code );
    // context.doT = doT;


    plv8.elog(NOTICE, 'done with doT');

    // aquameta-template-plv8
    var aq_template = plv8.execute("select * from endpoint.js_module where name='aquameta-template-plv8'");
    eval( aq_template[0].code );
    // import template() funciton into context, so doT can see it
    context.template = AQ.Template.template;
    plv8.elog(NOTICE, 'done with template: '+template_row.id);


    // render the template
    var htmlTemplate = doT.template(template_row.content);
    var html = htmlTemplate(context);
    plv8.elog(NOTICE, 'html = '+html);

    return html;
$$ language plv8;

*/


/*******************************************************************************
* FUNCTION template_render
* Renders a template
*******************************************************************************/

/*

this will be called by the client-side template lib, whenever that's completed.

create or replace function endpoint.template_render(
    bundle_name text,
    template_name text,
    args json default '{}'
) returns text as $$
    // eval doT.js
    var doT_rows = plv8.execute("select * from endpoint.plv8_module where name='doT' and version='1.1.0'");
    eval(doT_rows[0].code);


    return template( bundle_name, template_name, args);
$$ language plv8;
*/
