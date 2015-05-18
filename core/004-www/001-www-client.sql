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
CREATE OR REPLACE FUNCTION www_client.urlencode(in_str text, OUT _result text)
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
* array_to_querystring(args, vals)
* converts an array of args and an array of values to a query_string suitbale for a URL
*******************************************************************************/
create or replace function www_client.array_to_querystring(args text[], vals text[], out querystring text) as $$
begin
    querystring := '';

    raise notice 'qs: %', querystring;
    for i in 1..array_length(args,1) loop
        querystring := querystring 
            || www_client.urlencode(args[i])
            -- || args[i]
            || '='
            || www_client.urlencode(vals[i])
            -- || vals[i]
            || '&';
        raise notice 'qs: %', querystring;
    end loop;

end;
$$ language plpgsql;



/*******************************************************************************
*
*
* HTTP CLIENT
* Performs GET, POST, DELETE, PATCH operations over HTTP using python's liburl2
*
*
*******************************************************************************/


/*******************************************************************************
* http_get
*******************************************************************************/
create or replace function www_client.http_get (url text) returns text
as $$

import urllib2
import plpy

plpy.notice('************ http_get('+url+')')
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

select www_client.http_get (
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
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
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
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
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
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
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
        || '/' || (row_id::meta.schema_id).name
        || '/table'
        || '/' || (row_id::meta.relation_id).name
        || '/row'
        || '/' || row_id.pk_value
);

$$ language sql;




/*******************************************************************************
* rows_function
*******************************************************************************/
create or replace function www_client.rows_function(http_remote_id uuid, function_id meta.function_id, arg_vals text[], out result text)
as $$
declare 
    qs text;
begin

select into result www_client.http_get (
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
        || '/' || (function_id).schema_id.name
        || '/function'
        || '/' || (function_id).name
        || '/rows'
        || '?' || www_client.array_to_querystring((function_id).parameters, arg_vals)
);

end;
$$ language plpgsql;


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


/*
sample usage:
select bundle.construct_join_graph('foo',
    '{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id", "where_clause": "b.id = '12389021380912309812098312908'}',
    '[
        {"schema_name": "bundle", "relation_name": "commit", "label": "c", "local_id": "bundle_id", "related_label": "b", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset", "label": "r", "local_id": "id", "related_label": "c", "related_field": "rowset_id"},
        {"schema_name": "bundle", "relation_name": "rowset_row", "label": "rr", "local_id": "rowset_id", "related_label": "r", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "local_id": "rowset_row_id", "related_label": "rr", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "blob", "label": "blb", "local_id": "hash", "related_label": "rrf", "related_field": "value_hash"}
     ]');
*/

create or replace function bundle.construct_join_graph (temp_table_name text, start_rowset json, subrowsets json) returns void
as $$
declare
    tmp text;

    schema_name text;
    relation_name text;
    label text;
    local_id text;

    related_label text;
    related_field text;

    where_clause text;

    position integer;
    exclude boolean;

    rowset json;
    q text;
    ct integer;
begin
    -- raise notice '######## CONSTRUCT_JSON_GRAPH % % %', temp_table_name, start_rowset, subrowsets;
    -- create temp table
    tmp := quote_ident(temp_table_name);
    execute 'create temp table if not exists '
        || tmp
        || '(label text, row_id text, position integer, exclude boolean, row json)';

    -- load up the starting relation
    schema_name := quote_ident(start_rowset->>'schema_name');
    relation_name := quote_ident(start_rowset->>'relation_name');
    label := quote_ident(start_rowset->>'label');
    local_id:= quote_ident(start_rowset->>'local_id');
    exclude:= coalesce(start_rowset->>'exclude', 'false');

    position := coalesce(start_rowset->>'position', '0');

    where_clause := coalesce ('where ' || (start_rowset->>'where_clause')::text, '');

    -- raise notice '#### construct_join_graph PHASE 1:  label: %, schema_name: %, relation_name: %, local_id: %, where_clause: %',
    --    label, schema_name, relation_name, local_id, where_clause;

    q := 'insert into ' || tmp
        || ' select ''' || label || ''','
        || '     meta.row_id(''' || schema_name || ''',''' || relation_name || ''',''' || local_id || ''',' || label || '.' || local_id || '::text)::text, '
        || '     ' || position || ', '
        || '     ' || exclude || ','
        || '     row_to_json(' || label || ')'
        || ' from ' || schema_name || '.' || relation_name || ' ' || label
        || ' ' || where_clause;

        -- raise notice 'QUERY PHASE 1: %', q;
    execute q;


    -- load up sub-relations
    for i in 0..(json_array_length(subrowsets) - 1) loop
        rowset := subrowsets->i;

        schema_name := quote_ident(rowset->>'schema_name');
        relation_name := quote_ident(rowset->>'relation_name');
        label := quote_ident(rowset->>'label');
        local_id:= quote_ident(rowset->>'local_id');

        related_label := quote_ident(rowset->>'related_label');
        related_field := quote_ident(rowset->>'related_field');

        where_clause := coalesce ('where ' || (rowset->>'where_clause')::text, '');
        exclude:= coalesce(rowset->>'exclude', 'false');

        position := coalesce(rowset->>'position', '0');

        -- raise notice '#### construct_join_graph PHASE 2:  label: %, schema_name: %, relation_name: %, local_id: %, related_label: %, related_field: %, where_clause: %',
        --    label, schema_name, relation_name, local_id, related_label, related_field, where_clause;


        q := 'insert into ' || tmp
            || ' select ''' || label || ''','
            || '     meta.row_id(''' || schema_name || ''',''' || relation_name || ''',''' || local_id || ''',' || label || '.' || local_id || '::text), '
            || '     ' || position || ', '
            || '     ' || exclude || ', '
            || '     row_to_json(' || label || ')'
            || ' from ' || schema_name || '.' || relation_name || ' ' || label
            || ' join ' || tmp || ' on ' || tmp || '.label = ''' || related_label || ''''
            || '  and (' || tmp || '.row)->>''' || related_field || ''' = ' || label || '.' || local_id || '::text'
            || ' ' || where_clause;
        -- raise notice 'QUERY PHASE 2: %', q;
        execute q;

    end loop;

    execute 'delete from ' || tmp || ' where exclude = true';
end;
$$ language plpgsql;



/*******************************************************************************
* bundle.remote_compare_commits
* diffs the set of local commits with the set of remote commits
*******************************************************************************/

create or replace function bundle.remote_compare_commits(in remote_http_id uuid)
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
                    -- 'http://demo.aquameta.org/endpoint'
                        || '/bundle/table/commit/rows?bundle_id='
                        || r.bundle_id
                )::json->'result')->'row'->>'id')::uuid as id
            from bundle.remote_http r
            where r.id = remote_http_id
        )
        select c.id as local_commit_id, rc.id as remote_id
        from bundle.commit c
            full outer join remote_commit rc on rc.id=c.id
            where c.bundle_id = local_bundle_id or c.bundle_id is null;

end;
$$ language  plpgsql;


/*******************************************************************************
* bundle.remote_compare_commits
* checks a remote to see if it also has a bundle with the same id installed
*******************************************************************************/

create or replace function bundle.remote_has_bundle(in remote_http_id uuid, out has_bundle boolean)
as $$
declare
    local_bundle_id uuid;
begin
    select into has_bundle count(*) > 0 from (
        select (json_array_elements(
            www_client.http_get(
                r.endpoint_url
                    || '/bundle/table/bundle/rows/'
                    || r.bundle_id
            )::json->'result')->'row'->>'id')::uuid as id
        from bundle.remote_http r
        where r.id = remote_http_id
    ) has;
end;
$$ language  plpgsql;



/*******************************************************************************
* bundle.construct_bundle_diff
* fills a temporary table with the commits specified, but only including NEW blobs
*******************************************************************************/

create or replace function bundle.construct_bundle_diff(bundle_id uuid, new_commits uuid[], temp_table_name text) returns void as $$
declare 
    new_commits_str text;
begin
    select into new_commits_str string_agg(q,',') from (
    select quote_literal(unnest(new_commits)) q) as quoted;
    raise notice '######## CONSTRUCTING BUNDLE DIFF FOR COMMITS %', new_commits_str;

    perform bundle.construct_join_graph( 
            -- meta.function_id('bundle','construct_join_graph', ARRAY['temp_table_name', 'start_rowset', 'subrowsets']),
            -- 'some_temp_table'
            -- ARRAY[
            temp_table_name,
            ('{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id", "where_clause": "b.id = ''' || bundle_id::text || '''", "position": 1, "exclude": false }')::json,
            ('[
                {"schema_name": "bundle", "relation_name": "commit",           "label": "c",   "local_id": "bundle_id",     "related_label": "b",   "related_field": "id",         "position": 5, "where_clause": "c.id in (' || new_commits_str || ')"},
                {"schema_name": "bundle", "relation_name": "rowset",           "label": "r",   "local_id": "id",            "related_label": "c",   "related_field": "rowset_id",  "position": 2},
                {"schema_name": "bundle", "relation_name": "rowset_row",       "label": "rr",  "local_id": "rowset_id",     "related_label": "r",   "related_field": "id",         "position": 3},
                {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "local_id": "rowset_row_id", "related_label": "rr",  "related_field": "id",         "position": 6},
                {"schema_name": "bundle", "relation_name": "blob",             "label": "blb", "local_id": "hash",          "related_label": "rrf", "related_field": "value_hash", "position": 5}
             ]')::json
        );

end;
$$ language plpgsql;



/*******************************************************************************
* bundle.push
* transfer to a remote repository any local commits not present in the remote
*******************************************************************************/

create or replace function bundle.remote_push(in remote_http_id uuid)
returns void -- table(_row_id meta.row_id)
as $$
declare
    ct integer;
    bundle_id uuid;
begin
    raise notice '################################### PUSH ##########################';
    select into bundle_id r.bundle_id from bundle.remote_http r where r.id = remote_http_id;

    perform bundle.construct_join_graph(
        '_bundle_push_temp',
        ('{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id", "where_clause": "b.id = ''' || bundle_id::text || '''", "position": 1, "exclude": true }')::json,
        (
            '[
                {"schema_name": "bundle", "relation_name": "commit",           "label": "c",   "local_id": "bundle_id",     "related_label": "b",   "related_field": "id",         "position": 5, "where_clause": "c.id in (select comp.local_commit_id from bundle.remote_compare_commits(''' || remote_http_id::text || '''::uuid) comp where comp.remote_commit_id is null)"},
                {"schema_name": "bundle", "relation_name": "rowset",           "label": "r",   "local_id": "id",            "related_label": "c",   "related_field": "rowset_id",  "position": 2},
                {"schema_name": "bundle", "relation_name": "rowset_row",       "label": "rr",  "local_id": "rowset_id",     "related_label": "r",   "related_field": "id",         "position": 3},
                {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "local_id": "rowset_row_id", "related_label": "rr",  "related_field": "id",         "position": 6},
                {"schema_name": "bundle", "relation_name": "blob",             "label": "blb", "local_id": "hash",          "related_label": "rrf", "related_field": "value_hash", "position": 5}
             ]'
        )::json
    );

    -- http://hashrocket.com/blog/posts/faster-json-generation-with-postgresql
    perform www_client.rows_insert (
        remote_http_id,
        array_to_json(
            array_agg(
                row_to_json(b)
            )
        )
    )
    from (select * from _bundle_push_temp order by position) as b;

    drop table _bundle_push_temp;
end;
$$ language plpgsql;
/*******************************************************************************
* bundle.fetch
* download from remote repository any commits not present in the local repository
*******************************************************************************/

create or replace function bundle.remote_fetch(in remote_http_id uuid)
returns void -- table(_row_id meta.row_id)
as $$
declare
    ct integer;
    bundle_id uuid;
    new_commits text;
begin
    raise notice '################################### FETCH ##########################';
    select into bundle_id r.bundle_id from bundle.remote_http r where r.id = remote_http_id;

    -- get a comm-separated list of new commits
    select into new_commits coalesce(string_agg(quote_literal(remote_commit_id::text), ','),'') 
        from bundle.remote_compare_commits(remote_http_id)
        where local_commit_id is null;

    raise notice 'NEW COMMITS: %', new_commits;

    -- construct a join_graph on the remote server
    select -- www.rows_insert(
        www_client.rows_function(
            remote_http_id, 
            meta.function_id('bundle','construct_join_graph', ARRAY['temp_table_name', 'start_rowset', 'subrowsets']),
            -- args
            ARRAY[
                '_bundle_push_temp',
                '{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id", "where_clause": "b.id = ''' || bundle_id::text || '''", "position": 1, "exclude": true }',
                ('[
                    {"schema_name": "bundle", "relation_name": "commit",           "label": "c",   "local_id": "bundle_id",     "related_label": "b",   "related_field": "id",         "position": 5, "where_clause": "c.id in (' || new_commits || ')"},
                    {"schema_name": "bundle", "relation_name": "rowset",           "label": "r",   "local_id": "id",            "related_label": "c",   "related_field": "rowset_id",  "position": 2},
                    {"schema_name": "bundle", "relation_name": "rowset_row",       "label": "rr",  "local_id": "rowset_id",     "related_label": "r",   "related_field": "id",         "position": 3},
                    {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "local_id": "rowset_row_id", "related_label": "rr",  "related_field": "id",         "position": 6},
                    {"schema_name": "bundle", "relation_name": "blob",             "label": "blb", "local_id": "hash",          "related_label": "rrf", "related_field": "value_hash", "position": 5}
                 ]')::jsonb::text
            ]
        )::json;
--    );

    /*
    -- http://hashrocket.com/blog/posts/faster-json-generation-with-postgresql
    perform www_client.rows_insert (
        remote_http_id,
        array_to_json(
            array_agg(
                row_to_json(b)
            )
        )
    )
    from (select * from _bundle_push_temp order by position) as b;

    drop table _bundle_push_temp;
    */
end;
$$ language plpgsql;


commit;
