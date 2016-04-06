
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
select distinct(mimetype) from endpoint.tmp_httpd_mimetype;


-- Insert extension
insert into endpoint.mimetype_extension (mimetype_id, extension)
select distinct on (hm.extension) m.id, hm.extension
from endpoint.tmp_httpd_mimetype hm
join endpoint.mimetype m on m.mimetype = hm.mimetype;

-- Default mimetype extension
insert into endpoint.mimetype_extnesion (mimetype_id, extension) values (
    (select id from endpoint.mimetype where mimetype='text/plain'),
    ''
);

-- Drop temporary view
drop view endpoint.tmp_httpd_mimetype;

end;
