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
values 	('endpoint', 'mimetype', 'anonymous', 'select'), -- endpoint.mimetype
	('endpoint', 'session', 'anonymous', 'select'), -- endpoint.session
	('endpoint', 'resource', 'anonymous', 'select'), -- endpoint.resource
	('widget', 'dependency_js', 'anonymous', 'select'), -- widget.dependency_js
	('meta', 'function', 'anonymous', 'select') -- meta.function
);


-- function privileges
grant execute on function endpoint.login(text, text) to anonymous;
grant execute on function endpoint.register(text, text) to anonymous;
grant execute on function endpoint.register_confirm(text, text) to anonymous;


-- row level security permissions

-- endpoint.resource - RLS
insert into meta.policy (name, schema_name, relation_name, command, "using")
	values ( 'resource_anonymous', 'endpoint', 'resource', 'select', 'path in (''/login'', ''/register'', ''/register/confirm'') or path like ''%.js''');
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


-- table privileges
grant select on all tables in schema endpoint to "user";
grant select on all tables in schema filesystem to "user";
grant select on all tables in schema widget to "user";
grant select on all tables in schema meta to "user";
grant select on all tables in schema semantics to "user";


-- row level security permissions

-- endpoint.resource - RLS
insert into meta.policy (name, schema_name, relation_name, command, "using")
values ( 'resource_user', 'endpoint', 'resource', 'select', 'true');

insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_user', 'endpoint', 'resource', 'user');



end;
