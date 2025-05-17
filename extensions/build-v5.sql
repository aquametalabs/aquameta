-- base install
create extension meta version '0.5.0';
create extension meta_triggers version '0.5.0';
\i bundle--0.5.0.sql

-- these still work or at least install
create extension event;
create extension endpoint;



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



/* 
recreate widget/endpoint tables (that are being used)
this code is just copy pasta from v4 widget schema def
*/

create table widget.widget (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    pre_js text default 'return {};'::text not null,
    css text default '.{{= name }} {
}'::text not null,
    html text default '<div id="{{= id }}" class="{{= name }}">
</div>'::text not null,
    server_js text not null default '', -- TODO default NULL on these?
    common_js text not null default '',
    post_js text default 'var w = $("#"+id);'::text not null,
    help text
);

create table widget.dependency_js (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    version varchar(255) not null,
    variable varchar(255),
    content text not null,
    unique(name, version)
);

create table widget.widget_dependency_js (
    id uuid not null default public.uuid_generate_v4() primary key,
    widget_id uuid not null references widget.widget(id) on delete cascade on update cascade,
    dependency_js_id uuid not null references widget.dependency_js(id) on delete cascade on update cascade,
    unique(widget_id, dependency_js_id)
);

select endpoint.set_mimetype('widget', 'dependency_js', 'content', 'text/javascript');




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
where name not like '%bundle%';

select bundle.track_untracked_row(name, meta.row_id(bc.schema_name, bc.relation_name, bc.pk_column_name, bc.pk_value))
from bundlev4.v4_bundle_contents bc
where bc.schema_name != 'documentation'
    and relation_name != 'ignored_relation'
    and relation_name != 'ignored_schema'
    and relation_name not like 'template%'
    and relation_name != 'snippet'
    and schema_name != 'semantics'
    and relation_name != 'js_module';

select stage_tracked_rows(name) from bundle.repository;

select commit(name, 'Initial import from v0.4', 'Eric Hanson', 'eric@aquameta.com')
from bundle.repository r
where r.name != 'io.bundle.core.repository';





