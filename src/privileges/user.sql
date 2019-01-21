/******************************************************************************
 * Default permissions
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
set search_path=meta;

-- row level security permissions
alter table endpoint.resource enable row level security;

insert into meta.policy (name, schema_name, relation_name, command, "using")
    values ( 'resource_anonymous', 'endpoint', 'resource', 'select', 'path in (''/'', ''/login'', ''/register'', ''/confirm'') or path like ''%.js''');
insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_anonymous', 'endpoint', 'resource', 'anonymous');


------------------------
-- Anonymous permissions
------------------------

-- TODO: I think remove all of these??  Use RLS instead.

-- schema privileges
grant usage on schema widget to anonymous;
grant usage on schema endpoint to anonymous;
grant usage on schema meta to anonymous;
grant usage on schema bundle to anonymous;
grant usage on schema filesystem to anonymous; -- TODO: insecure


-- table privileges
insert into meta.table_privilege (schema_name, relation_name, role_name, "type")
values  ('endpoint',    'mimetype',               'anonymous', 'select'),
        ('endpoint',    'session',                'anonymous', 'select'),
        ('endpoint',    'resource',               'anonymous', 'select'),
        ('endpoint',    'mimetype_extension',     'anonymous', 'select'),
        ('endpoint',    'resource_file',          'anonymous', 'select'),
        ('endpoint',    'resource_binary',        'anonymous', 'select'),
        ('endpoint',    'resource_directory',     'anonymous', 'select'),
        ('endpoint',    'column_mimetype',        'anonymous', 'select'),
        ('endpoint',    'current_user',           'anonymous', 'select'),
	('endpoint',    'user',                   'anonymous', 'select'), -- TODO: insecure! -- do we need this?  endpoint.current_user gets permission denied when anon hits it but does so silently so hmmm.... we def don't want this turned on.
        ('bundle',      'bundle',                 'anonymous', 'select'),
        ('bundle',      'tracked_row',            'anonymous', 'select'),
        ('filesystem',  'file',                   'anonymous', 'select'), -- TODO: insecure?
        ('filesystem',  'directory',              'anonymous', 'select'), -- TODO: insecure?
        ('widget',      'dependency_js',          'anonymous', 'select'),
        ('widget',      'widget',                 'anonymous', 'select'),
        ('widget',      'widget_dependency_js',   'anonymous', 'select'),
        ('widget',      'widget_view',            'anonymous', 'select'),
        ('widget',      'input',                  'anonymous', 'select'),
        ('meta',        'column',                 'anonymous', 'select'),
        ('meta',        'function',               'anonymous', 'select');


-- function privileges
grant execute on function endpoint.register(text, text, text, boolean) to anonymous;
grant execute on function endpoint.register_confirm(text, text, boolean) to anonymous;
grant execute on function endpoint.login(text, text) to anonymous;
grant execute on function widget.bundled_widget(text, text) to anonymous;



---------------------------
-- Generic user permissions
---------------------------

-- schema privileges
grant usage on schema endpoint to "user";
grant usage on schema filesystem to "user";
grant usage on schema widget to "user";
grant usage on schema meta to "user";
grant usage on schema semantics to "user";
grant usage on schema bundle to "user";


-- table privileges
grant select on all tables in schema endpoint to "user";
grant select on all tables in schema filesystem to "user";
grant select on all tables in schema widget to "user";
grant select on all tables in schema meta to "user";
grant select on all tables in schema semantics to "user";
grant select on all tables in schema bundle to "user";
grant delete on endpoint.session to "user"; -- TODO: insecure

grant execute on all functions in schema widget to "user";


-- row level security permissions

-- endpoint.resource - RLS
insert into meta.policy (name, schema_name, relation_name, command, "using")
    values ( 'resource_user', 'endpoint', 'resource', 'select', 'true');
insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_user', 'endpoint', 'resource', 'user');

