/*******************************************************************************
 * Widget
 * Modular user interface component system
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

/*******************************************************************************
* TABLE widget
*******************************************************************************/

create schema widget;
set search_path=widget;

create table widget (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    pre_js text default 'return {};'::text not null,
    css text default '.{{= name }} {
}'::text not null,
    html text default '<div id="{{= id }}" class="{{= name }}">
</div>'::text not null,
    post_js text default 'var w = $("#"+id);'::text not null,
    help text
);


create function widget.bundled_widget (
	bundle_name text,
	widget_name text
) returns setof widget.widget as $$
    select * from (
        select w.*
        from bundle.head_rows(bundle_name) hr
            join widget.widget w on w.id = hr.pk_value::uuid
        where hr.schema_name='widget'
            and hr.relation_name='widget'
            and w.name=widget_name
    
        union
    
        select w.*
        from bundle.bundle b
            join bundle.stage_row_added sra on b.id = sra.bundle_id
            join widget.widget w on w.id = (sra.row_id).pk_value::uuid
        where ((sra.row_id)::meta.schema_id).name='widget'
            and ((sra.row_id)::meta.relation_id).name='widget'
            and w.name=widget_name
            and b.name=bundle_name
    ) r
    limit 1;
$$ language sql;


create view widget.bundled_widget as
    select b.name as bundle_name, w.*
    from bundle.bundle b
        join bundle.commit c on c.id = b.head_commit_id
        join bundle.rowset r on r.id = c.rowset_id
        join bundle.rowset_row rr on rr.rowset_id = r.id
        join widget.widget w on w.id = (rr.row_id).pk_value::uuid
    where ((rr.row_id)::meta.schema_id).name = 'widget'
        and ((rr.row_id)::meta.relation_id).name = 'widget'
    
    union
    
    select b.name as bundle_name, w.*
    from bundle.bundle b
        join bundle.stage_row_added sra on sra.bundle_id = b.id
        join widget.widget w on w.id = (sra.row_id).pk_value::uuid
    where ((sra.row_id)::meta.schema_id).name = 'widget'
        and ((sra.row_id)::meta.relation_id).name = 'widget';



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
