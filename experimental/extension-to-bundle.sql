\timing on

begin;

create extension if not exists hstore schema public;
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto schema public;

create extension meta;
create extension meta_triggers;
create extension bundle;

set search_path=bundle;

------------------------------------------------------------------------
-- track meta entities
------------------------------------------------------------------------
insert into bundle.trackable_nontable_relation (pk_column_id) values

-- here are all the views in the meta extension, along with reasons why they may not be supported

-- (meta.column_id('meta','cast','id')),
(meta.column_id('meta','column','id')),
-- (meta.column_id('meta','connection','id')), -- makes no sense
(meta.column_id('meta','constraint_check','id')),
(meta.column_id('meta','constraint_unique','id')),
-- (meta.column_id('meta','extension','id')), -- right now extensions are managed manually
-- (meta.column_id('meta','foreign_column','id')),
-- (meta.column_id('meta','foreign_data_wrapper','id')),
(meta.column_id('meta','foreign_key','id')),
-- (meta.column_id('meta','foreign_server','id')),
-- (meta.column_id('meta','foreign_table','id')),
(meta.column_id('meta','function','id')),
-- (meta.column_id('meta','function_parameter','id')), -- " "
(meta.column_id('meta','operator','id')),
-- (meta.column_id('meta','policy','id')), -- haven't thought through how vcs on permissions would work
-- (meta.column_id('meta','policy_role','id')),
-- (meta.column_id('meta','relation','id')), -- no update handlers on relation, never will be.  handled by table, view etc.
-- (meta.column_id('meta','relation_column','id')),
-- (meta.column_id('meta','role','id')), -- not sure how vcs on roles would work
-- (meta.column_id('meta','role_inheritance','id')),
(meta.column_id('meta','schema','id')),
(meta.column_id('meta','sequence','id')),
(meta.column_id('meta','table','id')),
-- (meta.column_id('meta','table_privilege','id')),
(meta.column_id('meta','trigger','id')),
(meta.column_id('meta','type','id')),
(meta.column_id('meta','view','id'));


create or replace function bundle.extension_to_bundle(extension_name text, bundle_name text) returns void as $$
declare
    prefix text;
begin
    raise notice 'extension_to_bundle(): Converting extension % to bundle %', extension_name, bundle_name;

    -- craete the extensions
    execute format ('create extension %I', extension_name);

    -- create bundle
    execute format ('select bundle.bundle_create(%L)', bundle_name);

    -- track meta entities
    prefix := 'select bundle.tracked_row_add(%L, row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = ''meta''';
    execute format (prefix || 'and (row_id::meta.relation_id).name=''schema''               and (((row_id).pk_value)::meta.schema_id).name = %L',                      bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''type''                 and (((row_id).pk_value)::meta.type_id).schema_name = %L',                 bundle_name, extension_name);
--    execute format (prefix || 'and (row_id::meta.relation_id).name=''cast''                 and (((row_id).pk_value)::meta.cast_id).schema_name = %L',                 bundle_name, extension_name); -- no schema_id
    execute format (prefix || 'and (row_id::meta.relation_id).name=''operator''             and (((row_id).pk_value)::meta.operator_id).schema_name = %L',             bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''table''                and (((row_id).pk_value)::meta.relation_id).schema_name = %L',             bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''column''               and (((row_id).pk_value)::meta.column_id).schema_name = %L',               bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''foreign_key''          and (((row_id).pk_value)::meta.foreign_key_id).schema_name = %L',          bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''constraint''           and (((row_id).pk_value)::meta.constraint_id).schema_name = %L',           bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''sequence''             and (((row_id).pk_value)::meta.sequence_id).schema_name = %L',             bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''constraint_unique''    and (((row_id).pk_value)::meta.constraint_unique_id).schema_name = %L',    bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''constraint_check''     and (((row_id).pk_value)::meta.constraint_check_id).schema_name = %L',     bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''view''                 and (((row_id).pk_value)::meta.relation_id).schema_name = %L',             bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''foreign_data_wrapper'' and (((row_id).pk_value)::meta.foreign_data_wrapper_id).schema_name = %L', bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''foreign_table''        and (((row_id).pk_value)::meta.foreign_table_id).schema_name = %L',        bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''foreign_column''       and (((row_id).pk_value)::meta.foreign_column_id).schema_name = %L',       bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''table_privilege''      and (((row_id).pk_value)::meta.table_privilege_id).schema_name = %L',      bundle_name, extension_name);
    -- execute format (prefix || 'and (row_id::meta.relation_id).name=''policy''               and (((row_id).pk_value)::meta.policy_id).schema_name = %L',             bundle_name, extension_name);
    execute format (prefix || 'and (row_id::meta.relation_id).name=''function''                and (((row_id).pk_value)::meta.function_id).schema_name = %L',             bundle_name, extension_name);

    -- stage 'em
    execute format ('select bundle.stage_row_add(%L, row_id) from bundle.tracked_row_added where bundle_id=(select id from bundle.bundle where name=%L)', bundle_name, bundle_name);

    -- commit
    execute format ('select bundle.commit(%L,''initial import'')', bundle_name);

    -- drop the extension
    execute format ('drop extension %I', extension_name);
    execute format ('drop schema %I', extension_name);

    -- check it out
    execute format ('select bundle.checkout((select head_commit_id from bundle.bundle where name=%L))', bundle_name);

end
$$ language plpgsql;


select bundle.extension_to_bundle('event', 'org.aquameta.ext.event');
select bundle.extension_to_bundle('endpoint', 'org.aquameta.ext.endpoint');
select bundle.extension_to_bundle('widget', 'org.aquameta.ext.widget');
select bundle.extension_to_bundle('semantics', 'org.aquameta.ext.semantics');
select bundle.extension_to_bundle('ide', 'org.aquameta.ext.ide');
select bundle.extension_to_bundle('documentation', 'org.aquameta.ext.documentation');


-- rollback;
commit;
