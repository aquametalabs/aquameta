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
* table remote_endpoint, a known endpoint out in the universe
*******************************************************************************/
create table remote_endpoint (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text,
    url text not null
);


/*******************************************************************************
* client_rows_select
*******************************************************************************/
create or replace function endpoint.client_rows_select(remote_endpoint_id uuid, relation_id meta.relation_id, args text[], arg_vals text[], out response http_client.http_response)
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
* rows_response_to_joingraph
create type join_graph_row as (
    label text,
    row_id meta.row_id,
    row jsonb,
    position integer,
    exclude boolean
);
create or replace function endpoint.rows_response_to_joingraph (response jsonb) returns setof endpoint.join_graph_row
as $$

select 
    'x'::text, 
    meta.row_id('a','b','c',r->'row'->>'id'), 
    (r->'row')::jsonb,
    0,
    false
from json_array_elements((response::json)->'result') r;


$$ language sql;
*******************************************************************************/






/*******************************************************************************
* client_row_select
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
* client_field_select
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
* row_delete
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
* rows_select_function
*******************************************************************************/
create or replace function endpoint.client_rows_select_function(remote_endpoint_id uuid, function_id meta.function_id, arg_vals text[], out http_client.http_response)
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
* rows_insert
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
--
-- row_insert(remote_id uuid, relation_id meta.relation_id, row_object json)
-- row_update(remote_id uuid, row_id meta.row_id, args json)
--
--

commit;
