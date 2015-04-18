/*******************************************************************************
 * WWW - client
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

create schema www_client;
set search_path=www_client;

-- ??????
create table www_client.remote (
    name text,
    url text
);

insert into www_client.remote (name, url) values ('bazaar', 'http://bazaar.aquameta.com');
-- ??????


create or replace function www_client.http_get (url text) returns text
as $$

import urllib2
import urllib

req = urllib2.Request(url)
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;



create or replace function www_client.http_post (url text, bundle_id uuid) returns text
as $$

import urllib2
import urllib
import plpy


# get from repo
# which commits do i need not include?

url = 'http://bazaar.aquameta.com'

stmt = plpy.prepare('select * from bundle.commit where bundle_id = $1', [ 'uuid' ]);
commits = plpy.execute(stmt, [ bundle_id ]);

data = urllib.urlencode(commits)
req = urllib2.Request(url, data)
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;



--
--
--
--
--
-- row_delete(remote_id uuid, row_id meta.row_id)
-- row_insert(remote_id uuid, relation_id meta.relation_id, row_object json)
-- row_update(remote_id uuid, row_id meta.row_id, args json)
-- row_select(remote_id uuid, row_id meta.row_id)
--
-- field_select(remote_id uuid, field_id meta.field_id)
-- rows_select(remote_id uuid, relation_id meta.relation_id, args json)
-- rows_select_function(remote_id uuid, function_id meta.function_id)
--
--
--
--


commit;





