/*******************************************************************************
 * Ignored
 *
 * Relations that are not available for version control.
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/


-- don't try to version control these tables in the version control system
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','commit'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row_field'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','blob'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','tracked_row_added'));


-- don't try to version control anything in the built-in system catalogs
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('pg_catalog'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('public'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('information_schema'));
