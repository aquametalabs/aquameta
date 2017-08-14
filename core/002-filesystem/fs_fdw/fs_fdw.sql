/******************************************************************************
 * Filesystem Foreign Data Wrapper
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;

create extension if not exists multicorn schema public;

set search_path=filesystem;

drop foreign data wrapper if exists fs_fdw cascade;

create foreign data wrapper fs_fdw
  handler public.multicorn_handler
  validator public.multicorn_validator;

create server fs_srv foreign data wrapper fs_fdw options (
	wrapper 'fs_fdw.FilesystemForeignDataWrapper'
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
) server fs_srv options (table_name 'file');

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
) server fs_srv options (table_name 'directory');

commit;
