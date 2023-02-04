/*******************************************************************************
 * Bundle Ignored
 *
 * Relations that are not available for version control.
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

begin;

set search_path=bundle2;

select bundle_create('org.aquameta.core.bundle');

-- don't try to version control these tables in the version control system
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','bundle'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','commit'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','rowset'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','rowset_row'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','rowset_row_field'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','blob'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','tracked_row_added'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','stage_field_changed'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','stage_row_added'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','stage_row_deleted'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','bundle_csv'));
insert into ignored_relation(relation_id) values (meta2.relation_id('bundle','bundle_remote_database'));

-- don't try to version control anything in the built-in system catalogs
insert into ignored_schema(schema_id) values (meta2.schema_id('pg_catalog'));
insert into ignored_schema(schema_id) values (meta2.schema_id('public'));
insert into ignored_schema(schema_id) values (meta2.schema_id('information_schema'));

-- stage and commit the above rows
select tracked_row_add('org.aquameta.core.bundle', 'bundle','ignored_relation','id',id::text) from ignored_relation;
-- select stage_row_add('org.aquameta.core.bundle', 'bundle','ignored_relation','id',id::text) from ignored_relation;

select tracked_row_add('org.aquameta.core.bundle', 'bundle','ignored_schema','id',id::text) from ignored_schema;
-- select stage_row_add('org.aquameta.core.bundle', 'bundle','ignored_schema','id',id::text) from ignored_schema;

-- select commit('org.aquameta.core.bundle', 'bundle bundle');

commit;
