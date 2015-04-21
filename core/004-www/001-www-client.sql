/*******************************************************************************
 * WWW - client
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

create language plpythonu;
create schema www_client;
set search_path=www_client;



/*******************************************************************************
* 
* 
* UTILS
* General purpose http client utilities.
* 
* 
*******************************************************************************/


/*******************************************************************************
* urlencode
* via http://stackoverflow.com/questions/10318014/javascript-encodeuri-like-function-in-postgresql
*******************************************************************************/
CREATE OR REPLACE FUNCTION urlencode(in_str text, OUT _result text)
    STRICT IMMUTABLE AS $urlencode$
DECLARE
    _i      int4;
    _temp   varchar;
    _ascii  int4;
BEGIN
    _result = '';
    FOR _i IN 1 .. length(in_str) LOOP
        _temp := substr(in_str, _i, 1);
        IF _temp ~ '[0-9a-zA-Z:/@._?#-]+' THEN
            _result := _result || _temp;
        ELSE
            _ascii := ascii(_temp);
            IF _ascii > x'07ff'::int4 THEN
                RAISE EXCEPTION 'Won''t deal with 3 (or more) byte sequences.';
            END IF;
            IF _ascii <= x'07f'::int4 THEN
                _temp := '%'||to_hex(_ascii);
            ELSE
                _temp := '%'||to_hex((_ascii & x'03f'::int4)+x'80'::int4);
                _ascii := _ascii >> 6;
                _temp := '%'||to_hex((_ascii & x'01f'::int4)+x'c0'::int4)
                            ||_temp;
            END IF;
            _result := _result || upper(_temp);
        END IF;
    END LOOP;
    RETURN ;
END;
$urlencode$ LANGUAGE plpgsql;

/*******************************************************************************
* http_get
*******************************************************************************/
create or replace function www_client.http_get (url text) returns text
as $$

import urllib2
import urllib

req = urllib2.Request(url)
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;

/*******************************************************************************
* http_post
*******************************************************************************/
/*
create or replace function www_client.http_get (url text) returns text
as $$

import urllib2
import urllib

req = urllib2.Request(url)
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;
*/







/*******************************************************************************
* 
* 
* ENDPOINT CLIENT
* 
* 
*******************************************************************************/

/*******************************************************************************
* rows_select
*******************************************************************************/
create or replace function rows_select(http_remote_id uuid, relation_id meta.relation_id, args json, out response json)
as $$

select www_client.http_get ((select url from bundle.remote_http where id=http_remote_id) 
        || '/' || www_client.urlencode((relation_id.schema_id).name)
        || '/relation'
        || '/' || www_client.urlencode(relation_id.name)
        || '/rows'
    )::json;

$$ language sql;



/*******************************************************************************
* row_select
*******************************************************************************/
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

