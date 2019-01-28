/******************************************************************************
 * Anonymous Privileges - Registration Scheme
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

-- schema usage privileges
grant usage on schema widget to anonymous;
grant usage on schema endpoint to anonymous;
grant usage on schema meta to anonymous;
grant usage on schema bundle to anonymous;
grant usage on schema semantics to anonymous;
grant usage on schema event to anonymous;


-- anonymous table privileges
-- anonymous can read the contents of these tables
grant select on endpoint.mimetype to anonymous;
grant select on endpoint.mimetype_extension to anonymous;
grant select on endpoint.current_user to anonymous;


-- function privileges
grant execute on function endpoint.register(text, text, text, boolean) to anonymous;
grant execute on function endpoint.register_confirm(text, text, boolean) to anonymous;
grant execute on function endpoint.login(text, text) to anonymous;
grant execute on function widget.bundled_widget(text, text) to anonymous;



----------------------------------
-- Row level security restrictions
----------------------------------

-- endpoint.resource
grant select on endpoint.resource to anonymous;
alter table endpoint.resource enable row level security;
create policy resource_anonymous on endpoint.resource for select to anonymous
    using (path in ('/', '/login', '/register', '/confirm', '/system.js','/datum.js','/widget.js', '/jQuery.min.js','/doT.min.js'));

-- endpoint.resource_binary
grant select on endpoint.resource_binary to anonymous;
alter table endpoint.resource_binary enable row level security;
create policy resource_binary_anonymous on endpoint.resource_binary for select to anonymous using (false);

-- endpoint.session
grant all on endpoint.session to anonymous;
alter table endpoint.session enable row level security;
create policy session_anonymous on endpoint.session for all to anonymous using ((role_id).name = CURRENT_USER);

-- bundle.bundle
grant select on bundle.bundle to anonymous;
-- alter table bundle.bundle enable row level security;
-- create policy bundle_anonymous on bundle.bundle for all to anonymous using (name in ('org.aquameta.ui.auth'));

-- bundle.tracked_row
grant select on bundle.tracked_row to anonymous;

-- widget.widget
grant select on widget.widget to anonymous;
-- alter table widget.widget enable row level security;
-- create policy bundle_anonymous on widget.widget for all to anonymous using (name in ('auth_manager'));

/*
-- widget.widget
grant select on widget.input to anonymous;
grant select on widget.dependency_js to anonymous;
grant select on widget.widget_dependency_js to anonymous;
grant select on widget.widget_view to anonymous;
grant select on meta.column to anonymous;


        ('endpoint',    'current_user',           'anonymous', 'select'),
	('endpoint',    'user',                   'anonymous', 'select'), -- TODO: insecure! -- do we need this?  endpoint.current_user gets permission denied when anon hits it but does so silently so hmmm.... we def don't want this turned on.
        ('bundle',      'bundle',                 'anonymous', 'select'),
        ('bundle',      'tracked_row',            'anonymous', 'select'),
        ('filesystem',  'directory',              'anonymous', 'select'), -- TODO: insecure?
        ('widget',      'dependency_js',          'anonymous', 'select'),
        ('widget',      'widget',                 'anonymous', 'select'),
        ('widget',      'widget_dependency_js',   'anonymous', 'select'),
        ('widget',      'widget_view',            'anonymous', 'select'),
        ('widget',      'input',                  'anonymous', 'select'),
        ('meta',        'column',                 'anonymous', 'select'),
        ('meta',        'function',               'anonymous', 'select');
*/
