/******************************************************************************
 * ENDPOINT SERVER
 * Filesystem import functions
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/*
 * These functions take a filesystem directory path, and import all files in
 * that directory into endpoint.resource or endpoint.resource_binary.
 *
 * TODO: recurse the folders
 * TODO: combine the functions by per-file, checking endpoint.mimetype.binary
 * (once it exists), to determine if the file is binary based on it's extension
 */

/*
create function endpoint.import_directory_to_resource( directory text, base_path text )
returns setof text as $$
insert into endpoint.resource (path, mimetype_id, content)
select base_path || '/' || name, m.id, content
from filesystem.file f
    join endpoint.mimetype_extension me on me.extension = substring(name from '\.([^\.]*)$')
    join endpoint.mimetype m on me.mimetype_id=m.id
where directory_id=directory
returning path;
$$ language sql;


create function endpoint.import_directory_to_resource_binary( directory text, base_path text )
returns setof text as $$
insert into endpoint.resource_binary (path, mimetype_id, content)
select base_path || '/' || name, m.id, filesystem.bytea_import(path) as content
from filesystem.file f
    join endpoint.mimetype_extension me on me.extension = substring(name from '\.([^\.]*)$')
    join endpoint.mimetype m on me.mimetype_id=m.id
where directory_id=directory
returning path;
$$ language sql;
*/


create function endpoint.get_mimetype_id(_mimetype text) returns uuid as $$
select id from endpoint.mimetype where mimetype=_mimetype;
$$ language sql;
