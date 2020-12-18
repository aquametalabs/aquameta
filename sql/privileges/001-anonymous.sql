/******************************************************************************
 * Anonymous Permissions - Invite Only
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

-----------------------
-- anonymous privileges
-----------------------

-- schema usage privileges
grant usage on schema endpoint to anonymous;

-- anonymous table privileges
-- anonymous can read the contents of these tables
grant select on endpoint.mimetype to anonymous;
grant select on endpoint.mimetype_extension to anonymous;
grant select on endpoint.current_user to anonymous;
grant select on endpoint.resource to anonymous;
grant select on endpoint.resource_binary to anonymous;
grant select on endpoint.template to anonymous;
grant select on endpoint.template_route to anonymous;
grant select on endpoint.js_module to anonymous;
grant select on endpoint.session to anonymous; -- TODO: needs RLS

-- function privileges
-- grant execute on function endpoint.register(text, text, text, boolean) to anonymous;
-- grant execute on function endpoint.register_confirm(text, text, boolean) to anonymous;
grant execute on function endpoint.login(text, text) to anonymous;
-- grant execute on function widget.bundled_widget(text, text) to anonymous;


-- endpoint.resource
alter table endpoint.resource enable row level security;
create policy resource_anonymous on endpoint.resource for select to anonymous 
    using (path in ('/', '/login', '/confirm'));

/*
-- endpoint.resource_binary
grant select on endpoint.resource_binary to anonymous;
-- alter table endpoint.resource_binary enable row level security;
-- create policy resource_binary_anonymous on endpoint.resource_binary for select to anonymous using (true);

-- endpoint.resource_file
grant select on endpoint.resource_file to anonymous;
-- alter table endpoint.resource_file enable row level security;
-- create policy resource_file_anonymous on endpoint.resource_file for select to anonymous using (true);

-- endpoint.resource_directory
grant select on endpoint.resource_directory to anonymous;
-- alter table endpoint.resource_directory enable row level security;
-- create policy resource_directory_anonymous on endpoint.resource_directory for select to anonymous using (true);

-- endpoint.session
grant all on endpoint.session to anonymous;
-- alter table endpoint.session enable row level security;
-- create policy session_anonymous on endpoint.session for all to anonymous using ((role_id).name = CURRENT_USER);
-- create policy "session_user" on endpoint.session for all to "user" using ((role_id).name = CURRENT_USER);

-- filesystem.directory TODO fix this -- no RLS on foreign tables!! :(
grant select on filesystem.directory to anonymous;
grant select on filesystem.file to anonymous;

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

-- widget.widget
grant select on widget.input to anonymous;
grant select on widget.dependency_js to anonymous;
grant select on widget.widget_dependency_js to anonymous;
grant select on widget.widget_view to anonymous;
grant select on meta.column to anonymous;
*/



/*

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

