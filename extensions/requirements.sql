begin;
create extension if not exists plpythonu;
create extension if not exists multicorn schema public;
create extension if not exists hstore schema public;
create extension if not exists hstore_plpythonu schema public;
create extension if not exists dblink schema public;
create extension if not exists "uuid-ossp" schema public;

commit;
