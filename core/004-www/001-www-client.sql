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
create or replace function www_client.http_post(url text, request_args text)
returns text
as $$
import urllib2
import urllib

req = urllib2.Request(url, request_args)
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;



/*******************************************************************************
* http_delete
*******************************************************************************/
create or replace function www_client.http_delete(url text)
returns text
as $$
import urllib2
opener = urllib2.build_opener(urllib2.HTTPHandler)
# request.add_header('Content-Type', 'your/contenttype')
request.get_method = lambda: 'DELETE'
response = urllib2.urlopen(request)
raw_response = response.read()

$$ language plpythonu;



/*******************************************************************************
* http_patch
*******************************************************************************/
create or replace function www_client.http_patch(url text, request_args text)
returns text
as $$
import urllib2
opener = urllib2.build_opener(urllib2.HTTPHandler)
request = urllib2.Request(url, request_args)
# request.add_header('Content-Type', 'your/contenttype')
request.get_method = lambda: 'PATCH'
response = urllib2.urlopen(request)
raw_response = response.read()

$$ language plpythonu;






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
create or replace function www_client.rows_select(http_remote_id uuid, relation_id meta.relation_id, args json, out response json)
as $$

select www_client.http_get ((select endpoint_url from bundle.remote_http where id=http_remote_id)
        || '/' || www_client.urlencode((relation_id.schema_id).name)
        || '/relation'
        || '/' || www_client.urlencode(relation_id.name)
        || '/rows'
    )::json;

$$ language sql;


/*******************************************************************************
* rows_insert
*******************************************************************************/
create or replace function www_client.rows_insert(http_remote_id uuid, args json[], out response json)
as $$

select www_client.http_post (
    (
        select endpoint_url from bundle.remote_http where id=http_remote_id)
            || '/insert',
        (array_to_json(args))::text

    )::json;

$$ language sql;



/*******************************************************************************
* row_select
*******************************************************************************/
create or replace function www_client.row_select(url text, bundle_id uuid) returns text
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


create or replace function www_client.row_select(url text, bundle_id uuid) returns text
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




/*******************************************************************************
*
*
* BUNDLE CONNECTIONS
*
*
*******************************************************************************/



create or replace function bundle.compare(in remote_http_id uuid)
returns table(local_commit_id uuid, remote_commit_id uuid)
as $$
declare
begin
    return query
        with remote_commit as (select (json_array_elements(
                www_client.http_get(
                    r.endpoint_url
                        || '/bundle/table/commit/rows?bundle_id='
                        || r.bundle_id
                )::json->'result')->'row'->>'id')::uuid as id
            from bundle.remote_http r
            where r.id = remote_http_id
        )
        select c.id as local_commit_id, rc.id as remote_id
        from bundle.commit c
            full outer join remote_commit rc on rc.id=c.id;

end;
$$ language  plpgsql;


create or replace function bundle.push(in remote_http_id uuid)
returns void -- table(_row_id meta.row_id)
as $$
declare
    records json[];
begin
    -- commits to push
    create temporary table _bundlepacker_tmp (row_id meta.row_id, next_fk uuid);

    -- bundle
    insert into _bundlepacker_tmp
        select meta.row_id('bundle','bundle','id', bundle.id::text), null
        from bundle.bundle 
        join bundle.remote_http on remote_http.bundle_id=bundle.id;

    -- commit
    with unpushed_commits as (
        select commit.id from bundle.compare(remote_http_id) comp
            join bundle.commit on commit.id = comp.local_commit_id
            -- join bundle.remote_http r on r.bundle_id = c.id FIXME?
        -- where r.id = remote_http_id
            and comp.remote_commit_id is null)
     insert into _bundlepacker_tmp select meta.row_id('bundle','commit','id', id::text), rowset_id from bundle.commit
        where commit.bundle_id::text in (select (row_id).pk_value from _bundlepacker_tmp)
            and commit.id in (select id from unpushed_commits);

    -- rowset
    insert into _bundlepacker_tmp select meta.row_id('bundle','rowset','id', id::text), null from bundle.rowset
        where id in (select next_fk from _bundlepacker_tmp where (row_id::meta.relation_id).name = 'commit');

    -- rowset_row
    insert into _bundlepacker_tmp select meta.row_id('bundle','rowset_row','id', id::text), rowset_id from bundle.rowset_row rr
        where rr.rowset_id::text in (select (row_id).pk_value from _bundlepacker_tmp where (row_id::meta.relation_id).name = 'rowset');

    -- rowset_row_field
    insert into _bundlepacker_tmp select meta.row_id('bundle','rowset_row_field','id', id::text), rowset_row_id from bundle.rowset_row_field rr
        where rr.rowset_row_id::text in (select (row_id).pk_value from _bundlepacker_tmp where (row_id::meta.relation_id).name = 'rowset_row');

    perform array_append(records, to_json(r)) from _bundlepacker_tmp r;

    perform www_client.rows_insert(remote_http_id, records);

    -- RETURN QUERY EXECUTE  'select row_id, meta.row_id_to_json(row_id) from _bundlepacker_tmp';
    -- RETURN QUERY EXECUTE 'select * from _bundlepacker_tmp';

end;
$$ language plpgsql;


commit;
