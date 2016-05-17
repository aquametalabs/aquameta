/******************************************************************************
 * Default permissions
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin

-- Anonymous permissions
grant usage on schema widget to anonymous;
grant usage on schema endpoint to anonymous;

insert into policy (name, schema_name, relation_name, command, "using")
values ( 'resource_anonymous', 'endpoint', 'resource', 'select', 'path in (''/login'', ''/register'', ''/register_confirm'')');

insert into policy_role (policy_name, schema_name, relation_name, role_name) values ('resource_anonymous', 'endpoint', 'resource', 'anonymous');

end;
