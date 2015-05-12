/*******************************************************************************
 * Meta Identifiers
 * A set of types that identify PostgreSQL DDL entities.
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;

create extension if not exists hstore schema public;

create schema meta;
set search_path=meta,public;


/******************************************************************************
 * meta.schema_id
 *****************************************************************************/

create type meta.schema_id AS (
    name text
);


create function meta.schema_id(name text) returns meta.schema_id as $$
    select row(name)::meta.schema_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.schema_id,
    rightarg json
) returns boolean as $$
    select (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.schema_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.schema_id(value json) returns meta.schema_id as $$
    select row(value->>'name')::meta.schema_id
$$ immutable language sql;


create cast (json as meta.schema_id)
with function meta.schema_id(json)
as assignment;


/******************************************************************************
 * meta.type_id
 *****************************************************************************/
create type meta.type_id as (
    schema_id meta.schema_id,
    name text
);


create function meta.type_id(schema_name text, name text) returns meta.type_id as $$
    select row(row(schema_name), name)::meta.type_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.type_id,
    rightarg json
) returns boolean as $$
    select (leftarg).schema_id = rightarg->'schema_id' and
           (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.type_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.type_id(value json) returns meta.type_id as $$
    select row(row(value->'schema_id'->>'name'), value->>'name')::meta.type_id
$$ immutable language sql;


create cast (json as meta.type_id)
with function meta.type_id(json)
as assignment;

/******************************************************************************
 * meta.cast_id
 *****************************************************************************/
create type meta.cast_id as (
    source_type meta.type_id,
    target_type meta.type_id
);

create function meta.cast_id(source_type_schema_name text, source_type_name text, target_type_schema_name text, target_type_name text) returns meta.cast_id as $$
    select row(row(row(source_type_schema_name), source_type_name),
               row(row(target_type_schema_name), target_type_name))::meta.cast_id
$$ language sql immutable;



create function meta.eq(
    leftarg meta.cast_id,
    rightarg json
) returns boolean as $$
--TODO
    select (leftarg).source_type = rightarg->'source_type' and
           (leftarg).target_type = rightarg->'target_type';
$$ language sql;


create operator = (
    leftarg = meta.cast_id,
    rightarg = json,
    procedure = meta.eq
);


/*
create function meta.cast_id(value json) returns meta.cast_id as $$
--TODO
    select row(row(value->'schema_id'->>'name'), value->>'name')::meta.cast_id
$$ immutable language sql;


create cast (json as meta.cast_id)
with function meta.cast_id(json)
as assignment;
*/


/******************************************************************************
 * meta.operator_id
 *****************************************************************************/

create type meta.operator_id as (
    schema_id meta.schema_id,
    name text,
    left_arg_type_id meta.type_id,
    right_arg_type_id meta.type_id
);

create function meta.operator_id(
    schema_name text,
    name text,
    left_arg_type_schema_name text,
    left_arg_type_name text,
    right_arg_type_schema_name text,
    right_arg_type_name text
) returns meta.operator_id as $$
    select row(
        meta.schema_id(schema_name),
        name, 
        meta.type_id(left_arg_type_schema_name, left_arg_type_name),
        meta.type_id(right_arg_type_schema_name, right_arg_type_name)
    )::meta.operator_id
$$ language sql immutable;

create function meta.eq(
    leftarg meta.operator_id,
    rightarg json
) returns boolean as $$
    select (leftarg).schema_id = rightarg->'schema_id' and
           (leftarg).name = rightarg->>'name' and
           (leftarg).left_arg_type_id = rightarg->'left_arg_type_id' and
           (leftarg).right_arg_type_id = rightarg->'right_arg_type_id';
$$ language sql;


create operator = (
    leftarg = meta.operator_id,
    rightarg = json,
    procedure = meta.eq
);

create function meta.operator_id(value json) returns meta.operator_id as $$
    select row(
        row(value->'schema_id'->>'name'),
        value->>'name',
        row(row(value->'left_arg_type_id'->'schema_id'->>'name'), value->>'name'),
        row(row(value->'right_arg_type_id'->'schema_id'->>'name'), value->>'name')
    )::meta.operator_id
$$ immutable language sql;


create cast (json as meta.operator_id)
with function meta.operator_id(json)
as assignment;


/******************************************************************************
 * meta.sequence_id
 *****************************************************************************/

create type meta.sequence_id as (
    schema_id meta.schema_id,
    name text
);


create function meta.sequence_id(
    schema_name text,
    name text
) returns meta.sequence_id as $$
    select row(row(schema_name), name)::meta.sequence_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.sequence_id,
    rightarg json
) returns boolean as $$
    select (leftarg).schema_id.name = rightarg->'schema_id'->>'name' and
           (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.sequence_id,
    rightarg = json,
    procedure = meta.eq
);



/******************************************************************************
 * meta.relation_id
 *****************************************************************************/

create type meta.relation_id as (
    schema_id meta.schema_id,
    name text
);


create function meta.relation_id(schema_name text, name text) returns meta.relation_id as $$
    select row(row(schema_name), name)::meta.relation_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.relation_id,
    rightarg json
) returns boolean as $$
    select (leftarg).schema_id = rightarg->'schema_id' and
           (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.relation_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.relation_id(value json) returns meta.relation_id as $$
    select row(row(value->'schema_id'->>'name'), value->>'name')::meta.relation_id
$$ immutable language sql;


create cast (json as meta.relation_id)
with function meta.relation_id(json)
as assignment;



/******************************************************************************
 * meta.column_id
 *****************************************************************************/

create type meta.column_id as (
    relation_id meta.relation_id,
    name text
);


create function meta.column_id(schema_name text, relation_name text, name text) returns meta.column_id as $$
    select row(row(row(schema_name), relation_name), name)::meta.column_id;
$$ language sql;


create function meta.eq(
    leftarg meta.column_id,
    rightarg json
) returns boolean as $$
    select (leftarg).relation_id = rightarg->'relation_id' and
           (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.column_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.column_id(value json) returns meta.column_id as $$
    select row(row(row(value->'relation_id'->'schema_id'->>'name'), value->'relation_id'->>'name'), value->>'name')::meta.column_id
$$ immutable language sql;


create cast (json as meta.column_id)
with function meta.column_id(json)
as assignment;




/******************************************************************************
 * meta.foreign_key_id
 *****************************************************************************/

create type meta.foreign_key_id as (
    relation_id meta.relation_id,
    name text
);


create function meta.foreign_key_id(schema_name text, relation_name text, name text) returns meta.foreign_key_id as $$
    select row(row(row(schema_name), relation_name), name)::meta.foreign_key_id
$$ language sql;


create function meta.eq(
    leftarg meta.foreign_key_id,
    rightarg json
) returns boolean as $$
    select (leftarg).relation_id = rightarg->'relation_id' and
           (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.foreign_key_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.foreign_key_id(value json) returns meta.foreign_key_id as $$
    select row(row(row(value->'relation_id'->'schema_id'->>'name'), value->'relation_id'->>'name'), value->>'name')::meta.foreign_key_id
$$ immutable language sql;


create cast (json as meta.foreign_key_id)
with function meta.foreign_key_id(json)
as assignment;



/******************************************************************************
 * meta.row_id
 *****************************************************************************/

create type meta.row_id as (
    pk_column_id meta.column_id,
    pk_value text
);

create function meta.row_id(schema_name text, relation_name text, pk_column_name text, pk_value text) returns meta.row_id as $$
    select row(
           row(row(row(schema_name), relation_name), pk_column_name),
               pk_value
           )::meta.row_id
    -- TODO: check for not existing row
$$ language sql;

create function exec(statements text[]) returns setof record as $$
   declare
       statement text;
   begin
       foreach statement in array statements loop
           -- raise info 'EXEC statement: %', statement;
           return query execute statement;
       end loop;
    end;
$$ language plpgsql volatile returns null on null input;


/*
-- TODO should this include views?  meta only?
create or replace view row as
select r.row_id as id / *, schema_name, table_name, pk_column_name  FIXME pk_value * /
from exec((
    select array_agg (stmt) from (
       
        select s.name as schema_name,
            r.name as table_name,
            c.name as pk_column_name,
            quote_ident((r.primary_key_column_ids[1]).name) as pk_value,
            'select meta.row_id(' ||
                quote_literal(s.name) || ', ' ||
                quote_literal(t.name) || ', ' ||
                quote_literal((r.primary_key_column_ids[1]).name) || ', ' ||
                quote_ident((r.primary_key_column_ids[1]).name) || '::text ' ||
                ') as row_id from ' ||
                quote_ident(s.name) || '.' || quote_ident(t.name) as stmt
        from meta.schema s
        join meta.table t on t.schema_id=s.id
        join meta.relation r on t.id=r.id
        join meta.column c on r.primary_key_column_ids[1] = c.id
       
    ) stmts
)) r(
    row_id meta.row_id
);
*/

create or replace function row_exists(in row_id meta.row_id, out answer boolean) as $$
    declare
        stmt text;
    begin
        execute 'select (count(*) = 1) from ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) ||
                ' where ' || quote_ident((row_id.pk_column_id).name) || '::text = ' || quote_literal(row_id.pk_value)
            into answer;
    exception
        when others then answer := false;

    end;
$$ language plpgsql;

/*
create function meta.eq(
    leftarg meta.row_id,
    rightarg json
) returns boolean as $$
    select (leftarg).schema_id = rightarg->'schema_id' and
           (leftarg).name = rightarg->>'name';
$$ language sql;

create operator = (
    leftarg = meta.relation_id,
    rightarg = json,
    procedure = meta.eq
);

("
    (""
        (widget)"",widget
    )",
    "(
        ""(
            """"(widget)"""",
            widget
        )"",
        id
    )",
    2533
)
*/

-- {"pk_column_id":{"relation_id":{"schema_id":{"name":"bundle"},"name":"bundle"},"name":"id"}
create function meta.row_id(value json) returns meta.row_id as $$
    select 
    row(
        row(
            row(
                row(
                    value->'pk_column_id'->'relation_id'->'schema_id'->>'name'
                ), 
                value->'pk_column_id'->'relation_id'->>'name'
            ),
            value->'pk_column_id'->>'name'
        )::meta.column_id,
        value->'pk_value'
    )::meta.row_id
$$ immutable language sql;

create cast (json as meta.row_id)
with function meta.row_id(json)
as assignment;


create or replace function meta.row_id_to_json(row_id meta.row_id, out row_json json) as $$
declare
    row_as_json json;
begin

    execute 'with r as (select * from ' || quote_ident ((row_id::meta.schema_id).name) || '.'
                             || quote_ident ((row_id::meta.relation_id).name) 
                             || ' where ' || quote_ident ((row_id.pk_column_id).name) 
                             || ' = ' || quote_literal (row_id.pk_value) || ') SELECT row_to_json(r.*) FROM r'
        into row_json;
    return;

end;
$$ language plpgsql;


/******************************************************************************
 * meta.field_id
 *****************************************************************************/

create type meta.field_id as (
    row_id meta.row_id,
    column_id meta.column_id
);

create function meta.field_id(schema_name text, relation_name text, pk_column_name text, pk_value text, column_name text) returns meta.field_id as $$
    select row(
               meta.row_id(schema_name, relation_name, pk_column_name, pk_value),
               meta.column_id(schema_name, relation_name, column_name)
           )::meta.field_id
$$ language sql;

create or replace function meta.field_id_literal_value(field_id meta.field_id) returns text as $$
declare
    literal_value text;
begin
    execute 'select ' || quote_ident(((field_id).column_id).name) || '::text'
            || ' from ' || quote_ident((field_id::meta.schema_id).name) || '.'
                        || quote_ident((field_id::meta.relation_id).name)
            || ' where ' || quote_ident((((field_id).row_id).pk_column_id).name)
                         || '::text =' || quote_literal(((field_id).row_id).pk_value)
    into literal_value;

    return literal_value;
exception when others then return null;
end
$$ language plpgsql;

/******************************************************************************
 * meta.function_id
 *****************************************************************************/

/* FIXME not needed in PG 9.4 */
create function meta.json_array_elements_text(json json, out value text) returns setof text as $$
    select json->>i
    from generate_series(0, json_array_length(json)-1) as i
$$ language sql immutable;


create type meta.function_id as (
    schema_id meta.schema_id,
    name text,
    parameters text[]
);


create function meta.function_id(schema_name text, name text, parameters text[]) returns meta.function_id as $$
    select row(row(schema_name), name, parameters)::meta.function_id;
$$ language sql;


create function meta.eq(
    leftarg meta.function_id,
    rightarg json
) returns boolean as $$
    select (leftarg).schema_id = rightarg->'schema_id' and
           (leftarg).name = rightarg->>'name' and
           (leftarg).parameters = (
               select array_agg(value)
               from meta.json_array_elements_text(rightarg->'parameters')
           );
$$ language sql;


create operator = (
    leftarg = meta.function_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.function_id(value json) returns meta.function_id as $$
    select row(row(value->'schema_id'->>'name'), value->>'name',
           (select array_agg(value) from json_array_elements(value->'parameters')))::meta.function_id
$$ immutable language sql;


create cast (json as meta.function_id)
with function meta.function_id(json)
as assignment;



/******************************************************************************
 * meta.trigger_id
 *****************************************************************************/

create type meta.trigger_id as (
    relation_id meta.relation_id,
    name text
);


create function meta.trigger_id(schema_name text, relation_name text, name text) returns meta.trigger_id as $$
    select row(row(row(schema_name), relation_name), name)::meta.trigger_id;
$$ language sql;



/******************************************************************************
 * meta.role_id
 *****************************************************************************/

create type meta.role_id as (
    name text
);


create function meta.role_id(name text) returns meta.role_id as $$
    select row(name)::meta.role_id;
$$ language sql;


create function meta.eq(
    leftarg meta.role_id,
    rightarg json
) returns boolean as $$
    select (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.role_id,
    rightarg = json,
    procedure = meta.eq
);


create function meta.role_id(value json) returns meta.role_id as $$
    select row(value->>'name')::meta.role_id
$$ immutable language sql;


create cast (json as meta.role_id)
with function meta.role_id(json)
as assignment;


/******************************************************************************
 * meta.connection_id
 *****************************************************************************/

create type meta.connection_id as (
    pid integer,
    connection_start timestamp with time zone
);


create function meta.connection_id(pid integer, connection_start timestamp with time zone) returns meta.connection_id as $$
    select row(pid, connection_start)::meta.connection_id;
$$ language sql;



/******************************************************************************
 * meta.constraint_id
 *****************************************************************************/

create type meta.constraint_id as (
    table_id meta.relation_id,
    name text
);

create function meta.constraint_id(schema_name text, relation_name text, name text) returns meta.constraint_id as $$
    select row(row(row(schema_name), relation_name), name)::meta.constraint_id;
$$ language sql;



/******************************************************************************
 * meta.extension_id
 *****************************************************************************/

create type meta.extension_id as (
    name text
);


create function meta.extension_id(
    name text
) returns meta.extension_id as $$
    select row(name)::meta.extension_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.extension_id,
    rightarg json
) returns boolean as $$
    select (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.extension_id,
    rightarg = json,
    procedure = meta.eq
);



/******************************************************************************
 * meta.foreign_data_wrapper_id
 *****************************************************************************/

create type meta.foreign_data_wrapper_id as (
    name text
);


create function meta.foreign_data_wrapper_id(
    name text
) returns meta.foreign_data_wrapper_id as $$
    select row(name)::meta.foreign_data_wrapper_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.foreign_data_wrapper_id,
    rightarg json
) returns boolean as $$
    select (leftarg).name = rightarg->>'name';
$$ language sql;


create operator = (
    leftarg = meta.foreign_data_wrapper_id,
    rightarg = json,
    procedure = meta.eq
);



/******************************************************************************
 * meta.foreign_server_id
 *****************************************************************************/

create type meta.foreign_server_id as (
    name text
);


create function meta.foreign_server_id(
    name text
) returns meta.foreign_server_id as $$
    select row(name)::meta.foreign_server_id
$$ language sql immutable;


create function meta.eq(
    leftarg meta.foreign_server_id,
    rightarg json
) returns boolean as $$
    select (leftarg).name = rightarg->>'name';
$$ language sql immutable;


create operator = (
    leftarg = meta.foreign_server_id,
    rightarg = json,
    procedure = meta.eq
);



/******************************************************************************
 * Casts between meta-types
 *****************************************************************************/
-- relation to schema
create function meta.relation_id_to_schema_id(in meta.relation_id, out meta.schema_id) as $$
    select $1.schema_id
$$
language sql;

create cast (relation_id as schema_id)
    with function relation_id_to_schema_id(relation_id) as assignment;


-- column to relation
create function column_id_to_relation_id(in meta.column_id, out meta.relation_id) as $$
    select $1.relation_id
$$
language sql;

create cast (column_id as relation_id)
    with function column_id_to_relation_id(column_id) as assignment;


-- column to schema
create function schema_id(in meta.column_id, out meta.schema_id) as $$
    select $1.relation_id.schema_id
$$
language sql;

create cast (column_id as schema_id)
    with function schema_id(column_id) as assignment;


-- row to relation
create function row_id_to_relation_id(in meta.row_id, out meta.relation_id) as $$
    select ($1.pk_column_id).relation_id
$$
language sql;

create cast (row_id as relation_id)
    with function row_id_to_relation_id(row_id) as assignment;


-- row to schema
create function schema_id(in meta.row_id, out meta.schema_id) as $$
    select (($1.pk_column_id).relation_id).schema_id
$$
language sql;

create cast (row_id as schema_id)
    with function schema_id(row_id) as assignment;


-- field to relation
create function relation_id(in meta.field_id, out meta.relation_id) as $$
       select ($1.column_id).relation_id
       $$
       language sql;

create cast (field_id as relation_id)
       with function relation_id(field_id) as assignment;


-- field to schema
create function schema_id(in meta.field_id, out meta.schema_id) as $$
       select (($1.column_id).relation_id).schema_id
       $$
       language sql;

create cast (field_id as schema_id)
       with function schema_id(field_id) as assignment;


-- field to column
/* we can't make these, because 
ERR0R:  "column_id" is already an attribute of type field_id

create function column_id(in meta.field_id, out meta.column_id) as $$
       select ($1.column_id)
       $$
       language sql;

create cast (field_id as column_id)
       with function column_id(field_id) as assignment;

*/


commit;
