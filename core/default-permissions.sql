/******************************************************************************
 * Default permissions
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;
set search_path=meta;

/*
Tables with RLS enabled
-- These tables need to have a policy defined for the user group that wants to use them, unless the user group is set to bypass RLS

- endpoint.resource 
*/

alter table endpoint.resource enable row level security;



------------------------
-- Anonymous permissions
------------------------

-- schema privileges
grant usage on schema widget to anonymous;
grant usage on schema endpoint to anonymous;
grant usage on schema meta to anonymous;


-- table privileges
insert into meta.table_privilege (schema_name, relation_name, role_name, "type")
values  ('endpoint',    'mimetype',               'anonymous', 'select'),
        ('endpoint',    'session',                'anonymous', 'select'),
        ('endpoint',    'resource',               'anonymous', 'select'),
        ('endpoint',    'mimetype_extension',     'anonymous', 'select'),
        ('endpoint',    'resource_file',          'anonymous', 'select'),
        ('endpoint',    'resource_binary',        'anonymous', 'select'),
        ('endpoint',    'resource_directory',     'anonymous', 'select'),
        ('filesystem',  'file',                   'anonymous', 'select'), -- TODO: insecure?
        ('filesystem',  'directory',              'anonymous', 'select'), -- TODO: insecure?
        ('widget',      'dependency_js',          'anonymous', 'select'),
        ('meta',        'function',               'anonymous', 'select');


-- function privileges
grant execute on function endpoint.login(text, text) to anonymous;
grant execute on function endpoint.register(text, text) to anonymous;
grant execute on function endpoint.register_confirm(text, text) to anonymous;


-- row level security permissions

-- endpoint.resource - RLS
insert into meta.policy (name, schema_name, relation_name, command, "using")
    values ( 'resource_anonymous', 'endpoint', 'resource', 'select', 'path in (''/'', ''/login'', ''/register'', ''/confirm'') or path like ''%.js''');
insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_anonymous', 'endpoint', 'resource', 'anonymous');



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

grant execute on all functions in schema widget to "user";


-- row level security permissions

-- endpoint.resource - RLS
insert into meta.policy (name, schema_name, relation_name, command, "using")
values ( 'resource_user', 'endpoint', 'resource', 'select', 'true');

insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_user', 'endpoint', 'resource', 'user');



end;
