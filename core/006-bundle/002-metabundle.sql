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
    meta.row_id('meta','relation','id',meta.relation_id('meta','trigger')::text)
);

insert into bundle.ignored_row(bundle_id, row_id) values (
    (select id from bundle.bundle where name='com.aquameta.bundle'),
    meta.row_id('meta','relation','id',meta.relation_id('meta','function_parameter')::text)
);


commit;
