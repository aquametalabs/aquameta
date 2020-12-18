/******************************************************************************
 * User Privileges
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

-- user should inherit all anonymous privileges
begin;

grant anonymous to "user";

-- schema usage privileges
-- TODO: replace this with a single insert query into meta.schema_privilege
grant usage on schema meta to "user";
grant usage on schema event to "user";
-- grant usage on schema filesystem to "user";
grant usage on schema bundle to "user";
grant usage on schema endpoint to "user";
grant usage on schema widget to "user";
grant usage on schema semantics to "user";



-- table privileges
insert into meta.table_privilege (schema_name, table_name, role_name, type)
select schema_name, name, 'user', 'select'
    from meta.relation
    where schema_name != 'pg_catalog' and schema_name != 'information_schema';



-- TODO: replace this with a single insert query into meta.function_privilege
-- `user` can execute all functions in these schemas
grant execute on all functions in schema meta to "user";
grant execute on all functions in schema event to "user";
-- grant execute on all functions in schema filesystem to "user";
grant execute on all functions in schema bundle to "user";
grant execute on all functions in schema endpoint to "user";
grant execute on all functions in schema widget to "user";
grant execute on all functions in schema semantics to "user";



-- select RLS policy and policy_role for each relation

-- create select policy for every table
insert into meta.policy (name, relation_name, schema_name, command, "using")
select 'user:' || schema_name || '/' || name, name, schema_name, 'select', 'true'
    from meta.table
    where schema_name != 'pg_catalog' and schema_name != 'information_schema';

-- assign this policy to the "user" role
insert into meta.policy_role (policy_name, relation_name, schema_name, role_name)
select 'user:' || schema_name || '/' || name, name, schema_name, 'user'
    from meta.table
    where schema_name != 'pg_catalog' and schema_name != 'information_schema';


commit;
