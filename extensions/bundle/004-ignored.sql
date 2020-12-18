/*******************************************************************************
 * Bundle Ignored
 *
 * Relations that are not available for version control.
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

set search_path=bundle;
select bundle_create('org.aquameta.core.bundle');

-- don't try to version control these tables in the version control system
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','commit'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row_field'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','blob'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','tracked_row_added'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','stage_field_changed'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','stage_row_added'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','stage_row_deleted'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle_origin_csv'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle_origin_remote'));

-- don't try to version control anything in the built-in system catalogs
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('pg_catalog'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('public'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('information_schema'));

-- stage and commit the above rows
select tracked_row_add('org.aquameta.core.bundle', 'bundle','ignored_relation','id',id::text) from bundle.ignored_relation;
-- select stage_row_add('org.aquameta.core.bundle', 'bundle','ignored_relation','id',id::text) from bundle.ignored_relation;

select tracked_row_add('org.aquameta.core.bundle', 'bundle','ignored_schema','id',id::text) from bundle.ignored_schema;
-- select stage_row_add('org.aquameta.core.bundle', 'bundle','ignored_schema','id',id::text) from bundle.ignored_schema;

-- select commit('org.aquameta.core.bundle', 'bundle bundle');
