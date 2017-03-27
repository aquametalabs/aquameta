/*******************************************************************************
 * Meta-bundle
 * Global bundle settings
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquametalabs.com/
 * Project: http://aquameta.org/
 ******************************************************************************/


/* 
 * This bundle contains the version control settings for the version control
 * system itself.  It does things like ignore the bundle schema, so that you
 * can't verson control the version control system.
 *
 * We also currently ignore everything in meta, until that can be tested 
 * and worked out.
 */

begin;

delete from bundle.bundle where name='com.aquameta.bundle';
insert into bundle.bundle (name) values ('com.aquameta.bundle');
insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','schema','id',meta.schema_id('bundle')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','schema','id',meta.schema_id('pg_catalog')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','schema','id',meta.schema_id('information_schema')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','function')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','function_parameter')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','trigger')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','cast')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','column')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','connection')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','constraint_check')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','constraint_unique')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','extension')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','foreign_column')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','foreign_data_wrapper')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','foreign_key')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','foreign_server')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','foreign_table')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','policy')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','policy_role')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','relation')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','role')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','role_inheritance')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','schema')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','table')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','table_privilege')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','type')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','view')::text)
);

commit;
