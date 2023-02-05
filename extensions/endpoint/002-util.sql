/******************************************************************************
 * ENDPOINT SERVER
 * Filesystem import functions
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/*
 * These functions take a filesystem directory path, and import all files in
 * that directory into endpoint.resource or endpoint.resource_binary.
 *
 * TODO: recurse the folders
 * TODO: combine the functions by per-file, checking endpoint.mimetype.binary
 * (once it exists), to determine if the file is binary based on it's extension
 */

/*
create function endpoint.import_directory_to_resource( directory text, base_path text )
returns setof text as $$
insert into endpoint.resource (path, mimetype_id, content)
select base_path || '/' || name, m.id, content
from filesystem.file f
    join endpoint.mimetype_extension me on me.extension = substring(name from '\.([^\.]*)$')
    join endpoint.mimetype m on me.mimetype_id=m.id
where directory_id=directory
returning path;
$$ language sql;


create function endpoint.import_directory_to_resource_binary( directory text, base_path text )
returns setof text as $$
insert into endpoint.resource_binary (path, mimetype_id, content)
select base_path || '/' || name, m.id, filesystem.bytea_import(path) as content
from filesystem.file f
    join endpoint.mimetype_extension me on me.extension = substring(name from '\.([^\.]*)$')
    join endpoint.mimetype m on me.mimetype_id=m.id
where directory_id=directory
returning path;
$$ language sql;
*/


create function endpoint.get_mimetype_id(_mimetype text) returns uuid as $$
select id from endpoint.mimetype where mimetype=_mimetype;
$$ language sql;



/******************************************************************************
 *
 *
 * UTIL FUNCTIONS
 *
 *
 ******************************************************************************/

create function endpoint2.set_mimetype(
    _schema name,
    _table name,
    _column name,
    _mimetype text
) returns void as $$
insert into endpoint2.column_mimetype (column_id, mimetype_id)
select c.id, m.id
from meta2.relation_column c
         cross join endpoint2.mimetype m
where c.schema_name   = _schema and
        c.relation_name = _table and
        c.name          = _column and
        m.mimetype = _mimetype
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
from meta2.relation_column c --TODO: either use relation_column maybe?  Or go look up the pk of a view somewhere else if we ever add that
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
from meta2.relation_column c --TODO: either use relation_column maybe?  Or go look up the pk of a view somewhere else if we ever add that
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
                                  row_id meta2.row_id,
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

create or replace function endpoint2.construct_join_graph (temp_table_name text, start_rowset json, subrowsets json) returns setof endpoint2.join_graph_row
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

create or replace function endpoint2.is_json_object(
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

create function endpoint2.is_json_array(
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
 * FUNCTION column_list
 ****************************************************************************************************/

create function endpoint2.column_list(
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
 *
 * FUNCTION suffix_clause
 *
 * Builds limit, offset, order by, and where clauses from json
 *
 ****************************************************************************************************/

create or replace function endpoint2.suffix_clause(
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
                        select _where || ' and ' || string_agg( name || ' ' || op || ' ' ||


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
                        select _where || ' and ' || name || ' ' || op || ' ' ||

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
