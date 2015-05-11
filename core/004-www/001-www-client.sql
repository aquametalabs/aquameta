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

req = urllib2.Request(url)
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;

/*******************************************************************************
* http_post
*******************************************************************************/
create or replace function www_client.http_post(url text, data text)
returns text
as $$
import urllib2

req = urllib2.Request(url, data)
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

req = urllib2.Request(url)
req.get_method = lambda: 'DELETE'
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

$$ language plpythonu;



/*******************************************************************************
* http_patch
*******************************************************************************/
create or replace function www_client.http_patch(url text, data text)
returns text
as $$
import urllib2

req = urllib2.Request(url, data)
req.get_method = lambda: 'PATCH'
response = urllib2.urlopen(req)
raw_response = response.read()
return raw_response

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
create or replace function www_client.rows_insert(http_remote_id uuid, args json, out response text)
as $$

select www_client.http_post (
    (select endpoint_url || '/insert' from bundle.remote_http where id=http_remote_id),
    args::text -- fixme?  does a post expect x=7&y=p&z=3 ?
);

$$ language sql;



/*******************************************************************************
* row_select
*******************************************************************************/
create or replace function www_client.row_select(http_remote_id uuid, row_id meta.row_id) returns json
as $$

select www_client.http_get (
    (
        select endpoint_url from bundle.remote_http where id=http_remote_id)
            || '/' || (row_id::meta.schema_id).name
            || '/table' 
            || '/' || (row_id::meta.relation_id).name
            || '/row'
            || '/' || row_id.pk_value
    )::json;

$$ language sql;


/*******************************************************************************
* field_select
*******************************************************************************/
create or replace function www_client.field_select(http_remote_id uuid, field_id meta.field_id) returns text
as $$

select www_client.http_get (
    (
        select endpoint_url from bundle.remote_http where id=http_remote_id)
            || '/' || (field_id::meta.schema_id).name
            || '/table' 
            || '/' || (field_id::meta.relation_id).name
            || '/row'
            || '/' || (field_id.row_id).pk_value
            || '/' || (field_id.column_id).name
    );

$$ language sql;


/*******************************************************************************
* row_delete
*******************************************************************************/
create or replace function www_client.row_delete(http_remote_id uuid, row_id meta.row_id) returns text
as $$

select www_client.http_delete (
    (
        select endpoint_url from bundle.remote_http where id=http_remote_id)
            || '/' || (row_id::meta.schema_id).name
            || '/table' 
            || '/' || (row_id::meta.relation_id).name
            || '/row'
            || '/' || row_id.pk_value
    );

$$ language sql;


--
--
-- row_insert(remote_id uuid, relation_id meta.relation_id, row_object json)
-- row_update(remote_id uuid, row_id meta.row_id, args json)
--
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
    local_bundle_id uuid;
begin
    select into local_bundle_id bundle_id from bundle.remote_http rh where rh.id = remote_http_id;
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
            full outer join remote_commit rc on rc.id=c.id
            where c.bundle_id = local_bundle_id;

end;
$$ language  plpgsql;


create or replace function bundle.push(in remote_http_id uuid)
returns void -- table(_row_id meta.row_id)
as $$
declare
    ct integer;
    bundle_id uuid;
begin
    raise notice '################################### PUSH ##########################';
    select into bundle_id r.bundle_id from bundle.remote_http r where r.id = remote_http_id;

    perform meta.construct_join_graph('_bundle_push_temp', ('{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id", "where_clause": "b.id = ''' || bundle_id::text || '''" }')::json,
    '[
        {"schema_name": "bundle", "relation_name": "commit", "label": "c", "local_id": "bundle_id", "related_label": "b", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset", "label": "r", "local_id": "id", "related_label": "c", "related_field": "rowset_id"},
        {"schema_name": "bundle", "relation_name": "rowset_row", "label": "rr", "local_id": "rowset_id", "related_label": "r", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "local_id": "rowset_row_id", "related_label": "rr", "related_field": "id"}
     ]'::json); 
    

     --   {"schema_name": "bundle", "relation_name": "blob", "label": "blb", "local_id": "hash", "related_label": "rrf", "related_field": "value_hash"}

    -- http://hashrocket.com/blog/posts/faster-json-generation-with-postgresql
    perform www_client.rows_insert (
        remote_http_id, 
        array_to_json(
            array_agg(
                row_to_json(
                    _bundle_push_temp
                )
            )
        ) 
    )
    from _bundle_push_temp;

    drop table _bundle_push_temp;

    -- raise notice '%', records;

    -- perform www_client.rows_insert(remote_http_id, records);

    -- RETURN QUERY EXECUTE  'select row_id, meta.row_id_to_json(row_id) from _bundlepacker_tmp';
    -- RETURN QUERY EXECUTE 'select * from _bundlepacker_tmp';

end;
$$ language plpgsql;


commit;
