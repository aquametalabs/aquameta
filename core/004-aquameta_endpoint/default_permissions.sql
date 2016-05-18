/******************************************************************************
 * Default permissions
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;

set search_path=meta;

-- Anonymous permissions


-- schema
grant usage on schema widget to anonymous;
grant usage on schema endpoint to anonymous;
grant usage on schema meta to anonymous;


-- endpoint.resource
grant select on endpoint.resource to anonymous;
alter table endpoint.resource enable row level security;

insert into meta.policy (name, schema_name, relation_name, command, "using")
values ( 'resource_anonymous', 'endpoint', 'resource', 'select', 'path in (''/login'', ''/register'', ''/register/confirm'') or path like ''%.js''');

insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_anonymous', 'endpoint', 'resource', 'anonymous');


-- endpoint.mimetype
grant select on endpoint.mimetype to anonymous;


-- endpoint.session
grant select on endpoint.session to anonymous;


-- endpoint functions
grant execute on function endpoint.login(text, text) to anonymous;
grant execute on function endpoint.register(text, text) to anonymous;
grant execute on function endpoint.register_confirm(text, text) to anonymous;

-- meta
grant select on meta.function to anonymous;


-- Generic user permissions
grant usage on schema endpoint to "user";
grant usage on schema filesystem to "user";
grant usage on schema widget to "user";
grant usage on schema meta to "user";

grant select on all tables in schema endpoint to "user";
grant select on all tables in schema filesystem to "user";
grant select on all tables in schema widget to "user";
grant select on all tables in schema meta to "user";

-- endpoint.resource
insert into meta.policy (name, schema_name, relation_name, command, "using")
values ( 'resource_user', 'endpoint', 'resource', 'select', 'true');

insert into meta.policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_user', 'endpoint', 'resource', 'user');



end;
