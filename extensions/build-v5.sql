-- create this view on the v4 server
/*
create view bundle.v4_bundle_contents as
select b.name, (tr.row_id).schema_name, (tr.row_id).relation_name, (tr.row_id).pk_column_name, (tr.row_id).pk_value
from bundle.bundle b
    join bundle.tracked_row tr on tr.bundle_id = b.id
order by b.name;
*/

-- postgres_fdw server to v4 instance
create extension if not exists postgres_fdw schema public;

/*

setup server

*/

create server v4
    foreign data wrapper postgres_fdw
    options (host 'localhost', dbname 'v4', port '5432');

create user mapping for current_user
    server v4
    options (user 'eric', password 'whatevz');


/*

create foreign tables to v4 instance

*/

-- map all of widget
create schema widgetv4;
import foreign schema widget
    from server v4
    into widgetv4;

-- map all of bundle
create schema bundlev4;
import foreign schema bundle
    from server v4
    into bundlev4;

-- map all of semantics 
create schema semanticsv4;
import foreign schema semantics
    from server v4
    into semanticsv4;

-- map all of endpoint
create schema endpointv4;
import foreign schema endpoint
    from server v4
    into endpointv4;

-- map all of documentation
create schema documentationv4;
import foreign schema documentation
    from server v4
    into documentationv4;


/*

copy all live db data from v4 instance into same tables in v5

*/

-- transfer data from foreign server to local
insert into widget.widget select * from widgetv4.widget;
insert into widget.dependency_js select * from widgetv4.dependency_js;
insert into widget.widget_dependency_js select * from widgetv4.widget_dependency_js;
insert into widget.module select * from widgetv4.module;
insert into widget.component select * from widgetv4.component;

insert into endpoint.mimetype select * from endpointv4.mimetype;
insert into endpoint.mimetype_extension select * from endpointv4.mimetype_extension;
insert into endpoint.resource select * from endpointv4.resource;
insert into endpoint.resource_binary select * from endpointv4.resource_binary;
insert into endpoint.resource_function select * from endpointv4.resource_function;

insert into semantics.column_purpose select * from semanticsv4.column_purpose;
insert into semantics.relation_purpose select * from semanticsv4.relation_purpose;
insert into semantics.unique_identifier select * from semanticsv4.unique_identifier;
insert into semantics.column select * from semanticsv4.column;
insert into semantics.type select * from semanticsv4.type;
insert into semantics.foreign_key select * from semanticsv4.foreign_key;
insert into semantics.relation select * from semanticsv4.relation;
insert into semantics.relation_component select * from semanticsv4.relation_component;
insert into semantics.column_component select * from semanticsv4.column_component;
insert into semantics.type_component select * from semanticsv4.type_component;

-- transfer documentation
/*
this fouls up everything and should be part of bundle anyway.
insert into documentation.bundle_doc (bundle_id, title, content)
select r.id, d4.title, d4.content
from documentationv4.bundle_doc d4
    join bundlev4.bundle b on d4.bundle_id = b.id
    join bundle.repository r on b.name = r.name;
*/

/*
IMPORT EVERYTHING
*/
-- create all the new bundles
select bundle.create_repository(name) from bundlev4.bundle
where name != 'org.aquameta.core.bundle';  --skip old bundle internal ignores

select bundle.track_untracked_row(name, meta.row_id(bc.schema_name, bc.relation_name, bc.pk_column_name, bc.pk_value))
from bundlev4.v4_bundle_contents bc
where bc.schema_name != 'documentation'
    and relation_name != 'ignored_relation'
    and relation_name != 'ignored_schema'
    and relation_name not like 'template%'
    and relation_name != 'snippet'
    and relation_name != 'js_module';

select bundle.stage_tracked_rows(name) from bundle.repository;

select bundle.commit(name, 'Initial import from v0.4', 'Eric Hanson', 'eric@aquameta.com')
from bundle.repository r
where r.name != 'io.bundle.core.repository';



-- fix all the widgets
/*
-- top level widgets to fix
widget/widget/d31ba103-3129-4780-b723-4c92299e89a1/post_js
widget/widget/927efac6-a523-445e-a6ac-4f7c8a76d7f1/post_js
widget/widget/76354157-7b96-49fc-98fe-6b953a0c7c56/post_js

-- grep
eric@thunk:~/dev/aquameta/pgfs/widget/widget$ grep "table('bundle')" * /post_js
05642077-3e03-40e9-b1e0-c679b283f6a4/post_js:endpoint.schema('bundle').table('bundle').row('id', bundle.get('id')).then(function(bundle) {
05642077-3e03-40e9-b1e0-c679b283f6a4/post_js:endpoint.schema('bundle').table('bundle').row('id', bundle.get('id')).then(function(bundle) {
5958da09-33b4-455c-a50f-05896aa1a7cc/post_js:endpoint.schema('bundle').table('bundle').rows({
7a7ca3d4-2188-4c4e-9526-b0e3b9cddd9d/post_js:endpoint.schema('bundle').table('bundle').rows({
8f0690e2-7883-48d2-898f-e4ce3406b0cc/post_js:            endpoint.schema('bundle').table('bundle').row('id',bundle_id)
927efac6-a523-445e-a6ac-4f7c8a76d7f1/post_js:endpoint.schema('bundle').table('bundle').row({
a9d024a5-7e7e-4435-9a06-692f09752e37/post_js:    endpoint.schema('bundle').table('bundle').insert({
b7468ec6-d896-49c3-b5b8-ca8662349ecd/post_js:endpoint.schema('bundle').table('bundle').rows({
d31ba103-3129-4780-b723-4c92299e89a1/post_js:endpoint.schema('bundle').table('bundle').rows({
d3c72a98-efd3-48bf-848b-6200af3e2429/post_js:    endpoint.schema('bundle').table('bundle').row('id', stage_row.get('bundle_id')).then(function(bundle) {
e74a4129-6e37-49d2-9391-0f6d99d8fd79/post_js:            endpoint.schema('bundle').table('bundle').rows({ order_by: {
*/

