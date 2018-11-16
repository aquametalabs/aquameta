/******************************************************************************
 * Default permissions
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
set search_path=endpoint;

/******************************************************************************
 * auth roles
 ******************************************************************************/

-- User-defined roles inherit from "user" role
DO
$body$
BEGIN
   IF NOT EXISTS (
      SELECT                       -- SELECT list can stay empty for this
      FROM   pg_catalog.pg_roles
      WHERE  rolname = 'user') THEN

      CREATE ROLE "user" nologin;
   END IF;

   IF NOT EXISTS (
      SELECT                       -- SELECT list can stay empty for this
      FROM   pg_catalog.pg_roles
      WHERE  rolname = 'anonymous') THEN

      CREATE ROLE anonymous login;
   END IF;

   IF NOT EXISTS (
      SELECT                       -- SELECT list can stay empty for this
      FROM   pg_catalog.pg_roles
      WHERE  rolname = 'aquameta') THEN

      CREATE ROLE aquameta LOGIN;
   END IF;


END
$body$;

/*
if not exists (select from pg_catalog.pg_roles where rolname = 'user')
then
    create role "user" nologin;
end if;

-- anonymous (guest role)
if not exists (select from pg_catalog.pg_roles where rolname = 'anonymous') 
then
    -- TODO: don't make anonymous a superuser -- enable security in 0.2
    create role anonymous superuser login;
end if;


-- aquameta
if not exists (select from pg_catalog.pg_roles where rolname = 'aquameta') 
then
    create role aquameta superuser login;
end if;
*/
