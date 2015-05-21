/*******************************************************************************
 * endpoint - client
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

create schema endpoint_client;
set search_path=endpoint_client;



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
create or replace function endpoint_client.endpoint_rows_select(http_remote_id uuid, relation_id meta.relation_id, args json, out response json)
as $$

select http_client.http_get (
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
        || '/' || http_client.urlencode((relation_id.schema_id).name)
        || '/relation'
        || '/' || http_client.urlencode(relation_id.name)
        || '/rows'
)::json;

$$ language sql;


/*******************************************************************************
* rows_insert
*******************************************************************************/
create or replace function endpoint_client.endpoint_rows_insert(http_remote_id uuid, args json, out response text)
as $$
begin

raise notice 'WWW_CLIENT.ROWS_INSERT: %s', args;

select http_client.http_post (
    (select endpoint_url || '/insert' from bundle.remote_http where id=http_remote_id),
    args::text -- fixme?  does a post expect x=7&y=p&z=3 ?
);
end;
$$ language plpgsql;



/*******************************************************************************
* row_select
*******************************************************************************/
create or replace function endpoint_client.endpoint_row_select(http_remote_id uuid, row_id meta.row_id) returns json
as $$

select http_client.http_get (
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
create or replace function endpoint_client.endpoint_field_select(http_remote_id uuid, field_id meta.field_id) returns text
as $$

select http_client.http_get (
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
create or replace function endpoint_client.endpoint_row_delete(http_remote_id uuid, row_id meta.row_id) returns text
as $$

select http_client.http_delete (
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
        || '/' || (row_id::meta.schema_id).name
        || '/table'
        || '/' || (row_id::meta.relation_id).name
        || '/row'
        || '/' || row_id.pk_value
);

$$ language sql;




/*******************************************************************************
* rows_select_function
*******************************************************************************/
create or replace function endpoint_client.endpoint_rows_select_function(http_remote_id uuid, function_id meta.function_id, arg_vals text[], out result text)
as $$
declare
    qs text;
begin

select into result http_client.http_get (
    (select endpoint_url from bundle.remote_http where id=http_remote_id)
        || '/' || (function_id).schema_id.name
        || '/function'
        || '/' || (function_id).name
        || '/rows'
        || '?' || endpoint_client.array_to_querystring((function_id).parameters, arg_vals)
);

end;
$$ language plpgsql;


--
--
-- row_insert(remote_id uuid, relation_id meta.relation_id, row_object json)
-- row_update(remote_id uuid, row_id meta.row_id, args json)
--
-- rows_select(remote_id uuid, relation_id meta.relation_id, args json)
--
--
--
