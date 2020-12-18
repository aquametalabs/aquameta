/******************************************************************************
 * Anonymous Privileges - Registration Scheme
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

-- schema usage privileges
grant usage on schema widget to anonymous;
grant usage on schema endpoint to anonymous;
grant usage on schema meta to anonymous;
grant usage on schema bundle to anonymous;
grant usage on schema semantics to anonymous;
grant usage on schema event to anonymous;


-- function privileges
grant execute on function endpoint.register(text, text, text, boolean) to anonymous;
grant execute on function endpoint.register_confirm(text, text, boolean) to anonymous;
grant execute on function endpoint.login(text, text) to anonymous;
grant execute on function endpoint.session(uuid) to anonymous;
grant execute on function widget.bundled_widget(text, text) to anonymous;



-- table privileges
-- endpoint.resource
grant select on endpoint.resource to anonymous;
/*
alter table endpoint.resource enable row level security;
create policy anonymous on endpoint.resource for select to anonymous
    using (path in ('/', '/login', '/register', '/confirm', '/system.js','/datum.js','/widget.js', '/jQuery.min.js','/doT.min.js'));

-- endpoint.resource_binary
grant select on endpoint.resource_binary to anonymous;
alter table endpoint.resource_binary enable row level security;
create policy anonymous on endpoint.resource_binary for select to anonymous using (false);
*/


-- TODO add security policies on these
grant select on meta.column to anonymous;
grant select on meta.function to anonymous;
grant select on meta.function_parameter to anonymous;
grant select on meta.relation_column to anonymous;
grant select on endpoint.mimetype to anonymous;
grant select on endpoint.mimetype_extension to anonymous;
grant select on endpoint.current_user to anonymous;
grant select on endpoint.column_mimetype to anonymous;
grant select on endpoint.resource to anonymous;
grant select on endpoint.resource_binary to anonymous;
grant select on endpoint.template_route to anonymous;
grant select on endpoint.template to anonymous;
grant select on endpoint.js_module to anonymous;
grant select on bundle.bundle to anonymous;
grant select on bundle.tracked_row to anonymous;
grant select on widget.widget to anonymous;
grant select on widget.widget_view to anonymous;
grant select on widget.dependency_js to anonymous;
grant select on widget.widget_dependency_js to anonymous;
grant select on widget.input to anonymous;


