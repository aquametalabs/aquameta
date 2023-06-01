/*******************************************************************************
 * Widget
 * Modular user interface component system
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/*******************************************************************************
* TABLE widget
*******************************************************************************/

create table widget (
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


create or replace function widget.bundled_widget (
	bundle_name text,
	widget_name text /*,
    args json default '{}' */
) returns setof widget.widget as $$
        select w.*
        from bundle.bundle b
            join bundle.tracked_row tr on tr.bundle_id=b.id
            join widget.widget w on w.id = (tr.row_id).pk_value::uuid
        where ((tr.row_id)::meta.schema_id).name = 'widget'
            and ((tr.row_id)::meta.relation_id).name = 'widget'
            and w.name=widget_name
            and b.name = bundle_name
$$ language sql;


create view widget.bundled_widget as
    select b.name as bundle_name, w.* from bundle.bundle b
        join bundle.tracked_row tr on tr.bundle_id = b.id
        join widget.widget w on w.id::text = (tr.row_id).pk_value
    where ((tr.row_id)::meta.schema_id).name = 'widget'
        and ((tr.row_id)::meta.relation_id).name = 'widget';



/*******************************************************************************
* TABLE dependency_css
*******************************************************************************/

create table dependency_css (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    version varchar(255) not null,
    content text not null,
    unique(name, version)
);

select endpoint.set_mimetype('widget', 'dependency_css', 'content', 'text/css');



/*******************************************************************************
* TABLE dependency_js
*******************************************************************************/

create table dependency_js (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    version varchar(255) not null,
    variable varchar(255),
    content text not null,
    unique(name, version)
);

select endpoint.set_mimetype('widget', 'dependency_js', 'content', 'text/javascript');



/*******************************************************************************
* TABLE input
*******************************************************************************/

create table input (
    id uuid not null default public.uuid_generate_v4() primary key,
    widget_id uuid not null references widget(id) on delete cascade on update cascade,
    name varchar(255) not null,
    optional boolean default false not null,
    test_value text,
    default_value text,
    doc_string text,
    help text,
    unique(widget_id, name)
);



/*******************************************************************************
* TABLE widget_dependency_css
*******************************************************************************/

create table widget_dependency_css (
    id uuid not null default public.uuid_generate_v4() primary key,
    widget_id uuid not null references widget(id) on delete cascade on update cascade,
    dependency_css_id uuid not null references dependency_css(id) on delete cascade on update cascade,
    unique(widget_id, dependency_css_id)
);



/*******************************************************************************
* TABLE widget_dependency_js
*******************************************************************************/

create table widget_dependency_js (
    id uuid not null default public.uuid_generate_v4() primary key,
    widget_id uuid not null references widget(id) on delete cascade on update cascade,
    dependency_js_id uuid not null references dependency_js(id) on delete cascade on update cascade,
    unique(widget_id, dependency_js_id)
);



/*******************************************************************************
* TABLE widget_view
*******************************************************************************/

create table widget_view (
    id uuid not null default public.uuid_generate_v4() primary key,
    widget_id uuid not null references widget(id) on delete cascade on update cascade,
    view_id meta.relation_id,
    unique(widget_id, view_id)
);



/*******************************************************************************
* TABLE snippet
*******************************************************************************/

create table snippet (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    type text not null default '',
    snippet text not null default ''
);



/*******************************************************************************
* fsm
*******************************************************************************/

create table machine (
    id uuid not null default public.uuid_generate_v4() primary key
);

create table widget_fsm (
    id uuid not null default public.uuid_generate_v4() primary key,
    widget_id uuid not null references widget(id) on delete cascade on update cascade,
    machine_id uuid references machine(id),
    unique(widget_id, machine_id)
);



/*******************************************************************************
* FUNCTION get_dependency_js
*******************************************************************************/

create function get_dependency_js(
    _name varchar,
    _version varchar
) returns setof dependency_js as $$
    select *
    from widget.dependency_js
    where name = _name
      and version = _version
$$
language sql stable rows 1;



/*******************************************************************************
* VIEW widget_name
*******************************************************************************/
create view widget_name as
select id, name from widget.widget;


/*******************************************************************************
* TABLE component
*******************************************************************************/

-- TODO: All "not null" constraints have been removed for flexibility.
--  Consider if this is should be widget creed.
-- TODO: Insert trigger on table. Validate widget name and use it in the
--  defaults.
create table component (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    html text default '<div>
</div>'::text,
    css text default ':host {
}'::text,
    js text default 'import { register, WidgetElement } from ''/org.aquameta.core.widget/widget.module/widget-element.js'';
import db from ''/org.aquameta.core.endpoint/widget.module/datum.js'';

export default register(
    class MyWidget extends WidgetElement(import.meta) {
        constructor() {
            super();
            // Widget has been created
        }
        onWidgetConnected() {
            // Widget is in the DOM
        }
        disconnectedCallback() {
            // Widget has been removed from the DOM
        }
    }
);'::text,
    help text
);



/*******************************************************************************
* ENUM module_type
*******************************************************************************/

create type module_type as enum ('js', 'css');



/*******************************************************************************
* TABLE module
*******************************************************************************/

create table module (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    content text not null,
    type module_type not null
);



/*******************************************************************************
* FUNCTION get_component
*******************************************************************************/

create or replace function widget.get_component(column_name text, bundle_name text, component_name text)
returns record
language plpgsql
as $$
  declare
    row_query text;
    ret record;
  begin
    row_query := '
      select c.' || quote_ident(column_name) || ',
        ''{}''::jsonb
      from bundle.bundle b
        join bundle.tracked_row tr on tr.bundle_id=b.id
        join widget.component c on c.id=(tr.row_id).pk_value::uuid
      where tr.row_id::meta.relation_id=meta.relation_id(''widget'', ''component'')
        and b.name=' || quote_literal(bundle_name) || '
        and c.name=' || quote_literal(component_name);

    execute row_query into ret;
    return ret;
  end;
$$;

insert into endpoint.resource_function
  (function_id, path_pattern, default_args, mimetype_id)
values
(
  (select meta.function_id('widget', 'get_component', '{text, text, text}')),
  '/${2}/widget.component/${3}.html',
  '{"html"}',
  (select id from endpoint.mimetype where mimetype='text/html')
),
(
  (select meta.function_id('widget', 'get_component', '{text, text, text}')),
  '/${2}/widget.component/${3}.css',
  '{"css"}',
  (select id from endpoint.mimetype where mimetype='text/css')
),
(
  (select meta.function_id('widget', 'get_component', '{text, text, text}')),
  '/${2}/widget.component/${3}.js',
  '{"js"}',
  (select id from endpoint.mimetype where mimetype='application/javascript')
);



/*******************************************************************************
* FUNCTION get_component
*******************************************************************************/

create or replace function widget.get_module(type text, bundle_name text, module_name text, version text)
returns record
language plpgsql
as $$
  declare
    row_query text;
    ret record;
  begin
    -- TODO: version is ignored until releases are figured out
    -- TODO: if version does not exist, fallback to versionless query
    --  maybe can add a header that contains a warning, or a 301
    row_query := '
      select m.content,
        ''{}''::jsonb
      from bundle.bundle b
        join bundle.tracked_row tr on tr.bundle_id=b.id
        join widget.module m on m.id=(tr.row_id).pk_value::uuid
      where tr.row_id::meta.relation_id=''widget.module''::meta.relation_id
        and b.name=' || quote_literal(bundle_name) || '
        and m.name=' || quote_literal(module_name) || '
        and m."type"=' || quote_literal(type) || '::widget.module_type';

    execute row_query into ret;
    return ret;
  end;
$$;
