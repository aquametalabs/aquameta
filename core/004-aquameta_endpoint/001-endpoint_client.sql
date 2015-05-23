/*******************************************************************************
 * endpoint - client
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

set search_path=endpoint;



/*******************************************************************************
*
*
* ENDPOINT CLIENT
*
*
*******************************************************************************/

/*******************************************************************************
* TABLE remote_endpoint, a known endpoint out in the universe
*******************************************************************************/

create table remote_endpoint (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text,
    url text not null
);




/*******************************************************************************
* FUNCTION client_rows_select
*******************************************************************************/
create or replace function endpoint.client_rows_select(remote_endpoint_id uuid, relation_id meta.relation_id, args text[] default '{}', arg_vals text[] default '{}', out response http_client.http_response)
as $$

select http_client.http_get (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/' || http_client.urlencode((relation_id.schema_id).name)
        || '/relation'
        || '/' || http_client.urlencode(relation_id.name)
        || '/rows'
        || coalesce('?' || http_client.array_to_querystring(args, arg_vals), '')
);

$$ language sql;



/*******************************************************************************
* FUNCTION client_row_select
*******************************************************************************/
create or replace function endpoint.client_row_select(remote_endpoint_id uuid, row_id meta.row_id, out response http_client.http_response)
as $$

select http_client.http_get (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/' || (row_id::meta.schema_id).name
        || '/table'
        || '/' || (row_id::meta.relation_id).name
        || '/row'
        || '/' || row_id.pk_value
);

$$ language sql;


/*******************************************************************************
* FUNCTION client_field_select
*******************************************************************************/
create or replace function endpoint.client_field_select(remote_endpoint_id uuid, field_id meta.field_id, out response http_client.http_response)
as $$

select http_client.http_get (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/' || (field_id::meta.schema_id).name
        || '/table'
        || '/' || (field_id::meta.relation_id).name
        || '/row'
        || '/' || (field_id.row_id).pk_value
        || '/' || (field_id.column_id).name
);

$$ language sql;


/*******************************************************************************
* FUNCTION client_row_delete
*******************************************************************************/
create or replace function endpoint.client_row_delete(remote_endpoint_id uuid, row_id meta.row_id, out response http_client.http_response)
as $$

select http_client.http_delete (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/' || (row_id::meta.schema_id).name
        || '/table'
        || '/' || (row_id::meta.relation_id).name
        || '/row'
        || '/' || row_id.pk_value
);

$$ language sql;




/*******************************************************************************
* FUNCTION client_rows_select_function
*******************************************************************************/
create or replace function endpoint.client_rows_select_function(remote_endpoint_id uuid, function_id meta.function_id, arg_vals text[] default '{}', out http_client.http_response)
as $$

select http_client.http_get (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/' || (function_id).schema_id.name
        || '/function'
        || '/' || (function_id).name
        || '/rows'
        || coalesce('?' || http_client.array_to_querystring((function_id).parameters, arg_vals),'')
);

$$ language sql;



/*******************************************************************************
* FUNCTION client_rows_insert
*******************************************************************************/
create or replace function endpoint.client_rows_insert(remote_endpoint_id uuid, args json, out response http_client.http_response)
as $$
begin

select http_client.http_post (
    (select url || '/insert' from endpoint.remote_endpoint where id=remote_endpoint_id),
    args::text
);
end;
$$ language plpgsql;


-- TODO

/*******************************************************************************
* FUNCTION client_row_insert
*******************************************************************************/

/*******************************************************************************
* FUNCTION client_row_update
*******************************************************************************/





/*******************************************************************************
* FUNCTION rows_response_to_joingraph
*
* This guy converts a endpoint's JSON response (as returned by say 
* endpoint.client_rows_select()) into our new join-graph format.  Long-term
* endpoint.rows_select should start producing join-graph formatted results that
* contain row_ids and a general overhaul.  This is the shim til we get there.
*******************************************************************************/

create or replace function endpoint.endpoint_response_to_joingraph (response jsonb) returns setof endpoint.join_graph_row
as $$

    select 
        ('n/a'::text,
        meta.row_id(
            split_part(r->>'selector', '/', 1),
            split_part(r->>'selector', '/', 3),
            'id', -- FIXME: We don't know the pk from the response.  I suppose we could figure it out by looking at the name of the field with the same value as the selector pk value.....ha.  Refactor endpoint!
            split_part(r->>'selector', '/', 5)
        ), 
        (r->'row')::jsonb,
        0,
        false)::endpoint.join_graph_row
    from json_array_elements((response::json)->'result') r;

$$ language sql;





commit;
