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

-- meta temporal relations
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','function_parameter'));
insert into bundle.ignored_relation (relation_id) values (meta.relation_id('meta','connection'));
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

-- track the ignored_rows

-- track meta entities
select bundle.tracked_row_add('org.aquameta.core.bundle', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='schema' and (((row_id).pk_value)::meta.schema_id).name = 'bundle';
select bundle.tracked_row_add('org.aquameta.core.bundle', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='table' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'bundle';
select bundle.tracked_row_add('org.aquameta.core.bundle', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='column' and ((((row_id).pk_value)::meta.column_id)::meta.schema_id).name = 'bundle';

------------------------------------------------------------------------
-- email
------------------------------------------------------------------------
-- track meta entities
insert into bundle.bundle (name) values ('org.aquameta.core.email');
create extension email;

select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='schema' and (((row_id).pk_value)::meta.schema_id).name = 'email';
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='table' and ((((row_id).pk_value)::meta.relation_id)::meta.schema_id).name = 'email';
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='column' and ((((row_id).pk_value)::meta.column_id)::meta.schema_id).name = 'email';
select bundle.tracked_row_add('org.aquameta.core.email', row_id) from bundle.untracked_row where (row_id::meta.schema_id).name = 'meta' and (row_id::meta.relation_id).name='function' and ((((row_id).pk_value)::meta.column_id)::meta.schema_id).name = 'email';

select stage_row_add('org.aquameta.core.email', (row_id::meta.schema_id).name, (row_id::meta.relation_id).name, 'id', (row_id).pk_value) from tracked_row_added where bundle_id=(select id from bundle.bundle where name='org.aquameta.core.email');


select commit('org.aquameta.core.email','first commit of schema oh boy');
drop extension email;
drop schema email;

select bundle.checkout((select head_commit_id from bundle.bundle where name='org.aquameta.core.email'));



