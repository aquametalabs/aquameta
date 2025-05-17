-- postgres_fdw server to v4 instance
create extension postgres_fdw schema public;

create server v4
    foreign data wrapper postgres_fdw
    options (host 'localhost', dbname 'v4', port '5432');

create user mapping for current_user
    server v4
    options (user 'eric', password 'whatevz');

-- map widget
create schema widgetv4;
import foreign schema widget except (module)
    from server v4
    into widgetv4;

-- map bundle
/*
-- create this view on the v4 server
create view v4_bundle_contents as
select b.name, (tr.row_id).schema_name,  (tr.row_id).relation_name, (tr.row_id).pk_column_name, (tr.row_id).pk_value from bundle b join tracked_row tr on tr.bundle_id = b.id order by b.name;
*/

create schema bundlev4;
import foreign schema bundle
    from server v4
    into bundlev4;


-- map endpoint
create schema endpointv4;
import foreign schema endpoint
    from server v4
    into endpointv4;


-- map documentation
create schema documentationv4;
import foreign schema documentation
    from server v4
    into documentationv4;



-- transfer widget.* and endpoint.* from foreign server to local
insert into widget.widget select * from widgetv4.widget;
insert into widget.dependency_js select * from widgetv4.dependency_js;
insert into widget.widget_dependency_js select * from widgetv4.widget_dependency_js;

insert into endpoint.mimetype select * from endpointv4.mimetype;
insert into endpoint.mimetype_extension select * from endpointv4.mimetype_extension;
insert into endpoint.resource select * from endpointv4.resource;
insert into endpoint.resource_binary select * from endpointv4.resource_binary;


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
where name not like '%bundle%';  --skip old bundle internal ignores

select bundle.track_untracked_row(name, meta.row_id(bc.schema_name, bc.relation_name, bc.pk_column_name, bc.pk_value))
from bundlev4.v4_bundle_contents bc
where bc.schema_name != 'documentation'
    and relation_name != 'ignored_relation'
    and relation_name != 'ignored_schema'
    and relation_name not like 'template%'
    and relation_name != 'snippet'
    and schema_name != 'semantics'
    and relation_name != 'js_module';

select bundle.stage_tracked_rows(name) from bundle.repository;

select bundle.commit(name, 'Initial import from v0.4', 'Eric Hanson', 'eric@aquameta.com')
from bundle.repository r
where r.name != 'io.bundle.core.repository';



-- fix all the widgets
/*
vi -p  \
pgfs/widget/widget/d31ba103-3129-4780-b723-4c92299e89a1/post_js \
pgfs/widget/widget/927efac6-a523-445e-a6ac-4f7c8a76d7f1/post_js \
pgfs/widget/widget/76354157-7b96-49fc-98fe-6b953a0c7c56/post_js
*/

