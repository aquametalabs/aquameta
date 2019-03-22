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

/*
-- resource_binary
insert into endpoint.resource_binary (path, mimetype_id, content) select directory_id || '/' || name, m.id, bytea_import(f.path)
from file f
        join endpoint.mimetype_extension me on me.extension = substring(name from '\.([^\.]*)$')
        join endpoint.mimetype m on me.mimetype_id=m.id
where directory_id='/home/ubuntu/src/html5up-verti/images';
*/
