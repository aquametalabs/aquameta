/******************************************************************************
 * Filesystem Foreign Data Wrapper
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
-- begin;

-- create extension if not exists multicorn schema public;

create schema filesystem;
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

-- commit;
