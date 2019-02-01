create extension if not exists plpythonu;
create extension if not exists multicorn schema public;
create extension if not exists hstore schema public;
create extension if not exists hstore_plpythonu schema public;
create extension if not exists dblink schema public;
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto schema public;
create extension if not exists plv8;

create extension meta;
create extension bundle;

------------------------------------------------------------------------
-- bundle
------------------------------------------------------------------------
set search_path=bundle;

-- non-versioned meta relations
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','function_parameter'));
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','connection'));
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','relation_column'));

-- TODO: what do we do with these??  database-wide
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','cast'));
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','extension'));

-- untracked schemas
insert into bundle.ignored_schema (schema_id) values (meta.schema_id('public'));
insert into bundle.ignored_schema (schema_id) values (meta.schema_id('information_schema'));
insert into bundle.ignored_schema (schema_id) values (meta.schema_id('pg_catalog'));

-- bundle internal tables
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','commit'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row_field'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','blob'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','tracked_row_added'));

insert into bundle.bundle (name) values ('org.aquameta.core.bundle');

-- TODO: track the ignored_rows

-- track meta entities
select bundle.tracked_row_add('org.aquameta.core.bundle', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='schema' and (((row_id).pk_value)::meta.schema_id).name = 'bundle';
select bundle.tracked_row_add('org.aquameta.core.bundle', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='table' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'bundle';
select bundle.tracked_row_add('org.aquameta.core.bundle', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='column' and ((((row_id).pk_value)::meta.column_id)::meta.schema_id).name = 'bundle';

-- TODO: stage and commit


------------------------------------------------------------------------
-- email
------------------------------------------------------------------------
create extension email;


-- track meta entities
insert into bundle.bundle (name) values ('org.aquameta.core.email');

-- schema
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='schema' and (((row_id).pk_value)::meta.schema_id).name = 'email';
-- table
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='table' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'email';
-- view
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='view' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'email';
-- column
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='column' and ((((row_id).pk_value)::meta.column_id)::meta.schema_id).name = 'email';
-- function
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='function' and ((((row_id).pk_value)::meta.function_id).schema_id).name = 'email';
-- constraint_check
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='constraint_check' and (((((row_id).pk_value)::meta.constraint_id).table_id)::meta.schema_id).name = 'email';
-- foreign_key
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='foreign_key' and (((((row_id).pk_value)::meta.constraint_id).table_id)::meta.schema_id).name = 'email';

select bundle.stage_row_add('org.aquameta.core.email', (row_id::meta.schema_id).name, (row_id::meta.relation_id).name, 'id', (row_id).pk_value) from bundle.tracked_row_added where bundle_id=(select id from bundle.bundle where name='org.aquameta.core.email');


select bundle.commit('org.aquameta.core.email','initial import');

drop extension email;
drop schema email;

/*
select bundle.checkout((select head_commit_id from bundle.bundle where name='org.aquameta.core.email'));




------------------------------------------------------------------------
-- endpoint
------------------------------------------------------------------------
create extension endpoint;


-- track meta entities
insert into bundle.bundle (name) values ('org.aquameta.core.endpoint');

select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='schema' and (((row_id).pk_value)::meta.schema_id).name = 'endpoint';
select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='table' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'endpoint';
select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='view' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'endpoint';
select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='column' and ((((row_id).pk_value)::meta.column_id)::meta.schema_id).name = 'endpoint';
select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='function' and ((((row_id).pk_value)::meta.function_id).schema_id).name = 'endpoint';
select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='constraint_check' and (((((row_id).pk_value)::meta.constraint_id).table_id)::meta.schema_id).name = 'endpoint';
select bundle.tracked_row_add('org.aquameta.core.endpoint', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='foreign_key' and (((((row_id).pk_value)::meta.constraint_id).table_id)::meta.schema_id).name = 'endpoint';


select bundle.stage_row_add('org.aquameta.core.endpoint', (row_id::meta.schema_id).name, (row_id::meta.relation_id).name, 'id', (row_id).pk_value) from bundle.tracked_row_added where bundle_id=(select id from bundle.bundle where name='org.aquameta.core.endpoint');

select bundle.commit('org.aquameta.core.endpoint','initial import');

drop extension endpoint;
drop schema endpoint;

select bundle.checkout((select head_commit_id from bundle.bundle where name='org.aquameta.core.endpoint'));

*/
