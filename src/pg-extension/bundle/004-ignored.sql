insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','commit'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row_field'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','blob'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','tracked_row_added'));

insert into bundle.ignored_schema(schema_id) values (meta.schema_id('pg_catalog'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('public'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('information_schema'));
