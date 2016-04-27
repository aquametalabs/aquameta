
begin;

set search_path=endpoint;


-- Create temporary view
create or replace view endpoint.tmp_httpd_mimetype as
select mimetype,
    unnest(string_to_array(extensions, ' ')) as extension
from
(
    select (regexp_split_to_array(a.line, E'\t+'))[1] as mimetype, (regexp_split_to_array(a.line, E'\t+'))[2] as extensions
    from
    (
        select unnest(string_to_array(response_text,  E'\n')) as line
        from http_client.http_get('https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types')
        offset 15
    ) a
    where a.line not like '#%' and line <> ''
) b;


-- Insert mimetypes
insert into endpoint.mimetype (mimetype)
select distinct(mimetype)
from endpoint.tmp_httpd_mimetype
where mimetype not in (select mimetype from endpoint.mimetype);


-- Insert extension
insert into endpoint.mimetype_extension (mimetype_id, extension)
select distinct on (hm.extension) m.id, hm.extension
from endpoint.tmp_httpd_mimetype hm
join endpoint.mimetype m on m.mimetype = hm.mimetype;


-- Drop temporary view
drop view endpoint.tmp_httpd_mimetype;

insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/Datum.js', '/Datum.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/jQuery.min.js', '/jQuery.min.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/underscore.min.js', '/underscore.min.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/datum.html', '/datum.html');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/socket.html', '/socket.html');
insert into resource_file(file_id, url) values ('/s/aquameta/Dockerfile', '/Dockerfile');
insert into resource_directory(directory_id, indexes) values ('/s/aquameta/core/004-aquameta_endpoint/js', false);
insert into resource_directory(directory_id, indexes) values ('/s/aquameta/core', true);
insert into resource_directory(directory_id, indexes) values ('/s/aquameta', true);


end;
