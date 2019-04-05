/******************************************************************************
 * Filesystem Foreign Data Wrapper
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/
-- begin;

-- create extension if not exists multicorn schema public;
-- create schema filesystem;

set search_path=filesystem,public;

-- drop foreign data wrapper if exists filesystem_fdw cascade;

create foreign data wrapper filesystem_fdw
  handler public.multicorn_handler
  validator public.multicorn_validator;

create server filesystem_fdw_srv foreign data wrapper filesystem_fdw options (
	wrapper 'filesystem_fdw.FilesystemForeignDataWrapper'
);

create foreign table filesystem.file (
	id text,
	directory_id text,
	name text,
	path text,
	content text,
	permissions text,
	links integer,
	size integer,
	owner text,
	"group" text,
	last_mod text
) server filesystem_fdw_srv options (table_name 'file');

create foreign table filesystem.directory (
	id text,
	parent_id text,
	name text,
	path text,
	permissions text,
	links integer,
	size integer,
	owner text,
	"group" text,
	last_mod text
) server filesystem_fdw_srv options (table_name 'directory');

-- http://dba.stackexchange.com/questions/1742/how-to-insert-file-data-into-a-postgresql-bytea-column
create or replace function filesystem.bytea_import(p_path text, p_result out bytea)
language plpgsql as $$
declare
  l_oid oid;
  r record;
begin
  p_result := '';
  select lo_import(p_path) into l_oid;
  for r in ( select data
             from pg_largeobject
             where loid = l_oid
             order by pageno ) loop
    p_result = p_result || r.data;
  end loop;
  perform lo_unlink(l_oid);
end;
$$;

