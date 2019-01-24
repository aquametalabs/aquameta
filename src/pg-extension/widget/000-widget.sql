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

create table widget (
    id uuid not null default public.uuid_generate_v4() primary key,
    name varchar(255) not null,
    pre_js text default 'return {};'::text not null,
    css text default '.{{= name }} {
}'::text not null,
    html text default '<div id="{{= id }}" class="{{= name }}">
</div>'::text not null,
    post_js text default 'var w = $("#"+id);'::text not null,
    server_js text default null,
    help text
);


create or replace function widget.bundled_widget (
	bundle_name text,
	widget_name text
    -- args json optional default '{}'
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
* FUNCTION render
*******************************************************************************/

create extension if not exists plv8;
create or replace function widget.render(
    widget_id uuid,
    args json
) returns text as $$
    // fetch the widget
    try {
        var widget_rows = plv8.execute('select * from widget.widget where id=$1', [ widget_id ]);
        var widget = widget_rows[0];
    }
    catch( e ) {
        plv8.elog( ERROR, e, e)
        return false;
    }

    // setup javascript scope
    var context = {};

    // generate a unique id for this widget
    var id_rows = plv8.execute('select public.uuid_generate_v4() as id');
    context.id = id_rows[0].id;
    context.name = widget.name;

    // run server_js
    var server_js = widget.server_js;
    var datums = {};
    eval(server_js);
    for(var key in datums){
        context[key] = datums[key];
    }

    // grab doT.js
    var doT_rows = plv8.execute("select * from endpoint.resource where path='/doT.min.js'");
    eval(doT_rows[0].content);

    // render the template
    var htmlTemplate = doT.template(widget.html);
    var html = htmlTemplate(context);

    // add post_js
    html += '<script type="application/javascript">var id=' + context.id + '; var name = '+context.name+';\n'+widget.post_js+'</script>';

    // add css
    var cssTemplate = doT.template(widget.css);
    var css = cssTemplate(context);
    html += '<link rel="stylesheet">'+css+'</link>';

    return html;
    
$$ language plv8;


create table endpoint.resource_widget (
    id uuid not null default public.uuid_generate_v4() primary key,
    path text not null default '',
    widget_id uuid references widget.widget(id)
);
