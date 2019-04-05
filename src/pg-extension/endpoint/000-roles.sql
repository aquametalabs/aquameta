/******************************************************************************
 * Default permissions
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/
set search_path=endpoint;

/******************************************************************************
 * auth roles
 ******************************************************************************/
DO
$$
begin
   -- anonymous
   if not exists (select from pg_catalog.pg_roles where rolname = 'user') then
      create role "anonymous" login;
   end if;

   -- user
   if not exists (select from pg_catalog.pg_roles where rolname = 'user') then
      create role "user" nologin;
   end if;
end
$$;
