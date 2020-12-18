/*******************************************************************************
 * endpoint - client
 *
 * Copyriright (c) 2020 - Aquameta, LLC - http://aquameta.org/
 ******************************************************************************/

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

-- /endpoint/0.3/relation/widget/input?meta_data=true
select http_client.http_get (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/relation'
        || '/' || http_client.urlencode((relation_id.schema_id).name)
        || '/' || http_client.urlencode(relation_id.name)
        || coalesce('?' || http_client.array_to_querystring(args, arg_vals), '')
);

$$ language sql;



/*******************************************************************************
* FUNCTION client_row_select
*******************************************************************************/
-- endpoint/0.3/relation/widget/input?meta_data=true&where=%7B%22name%22%3A%22id%22%2C%22op%22%3A%22%3D%22%2C%22value%22%3A%2212345%22%7D
create or replace function endpoint.client_row_select(remote_endpoint_id uuid, row_id meta.row_id, out response http_client.http_response)
as $$

select http_client.http_get (
    (select url from endpoint.remote_endpoint where id=remote_endpoint_id)
        || '/row'
        || '/' || (row_id::meta.schema_id).name
        || '/' || (row_id::meta.relation_id).name
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
        || '/field'
        || '/' || (field_id::meta.schema_id).name
        || '/' || (field_id::meta.relation_id).name
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
        || '/row'
        || '/' || (row_id::meta.schema_id).name
        || '/' || (row_id::meta.relation_id).name
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
        || '/function'
        || '/' || (function_id).schema_id.name
        || '/' || (function_id).name
        || coalesce('?' || http_client.array_to_querystring((function_id).parameters, arg_vals),'')
);

$$ language sql;



/*******************************************************************************
* FUNCTION client_rows_insert
*******************************************************************************/
create or replace function endpoint.client_rows_insert(remote_endpoint_id uuid, args jsonb, out response http_client.http_response)
as $$

select http_client.http_post (
    (select url || '/insert' from endpoint.remote_endpoint where id=remote_endpoint_id),
    args::text
);
$$ language sql;


-- TODO

/*******************************************************************************
* FUNCTION client_row_insert
*******************************************************************************/

/*******************************************************************************
* FUNCTION client_row_update
*******************************************************************************/



/*******************************************************************************
 *
 *
 * JOIN GRAPH CLIENT
 *
 * A multidimensional structure made up of rows from various tables connected
 * by their foreign keys, for non-tabular query results made up of rows, but
 * serialized into a table of type join_graph_row.
 *
 *
 *
 *******************************************************************************/


/*******************************************************************************
* FUNCTION join_graph_to_json
*
* converts a join_graph_row table to the json object that rows_insert expects,
* basically an array of row_to_json on each row in the join_graph.
*******************************************************************************/

create or replace function endpoint.join_graph_to_json(join_graph_table text, out join_graph_json jsonb)
as $$
begin
     -- build json object
    execute 'select json_agg(row_to_json(jgt))::jsonb from (select * from ' || quote_ident(join_graph_table) || ' jgt2 order by jgt2.position) jgt'
    into join_graph_json;
end;
$$ language plpgsql;




/*******************************************************************************
* FUNCTION endpoint_response_to_joingraph
*
* This guy converts a endpoint's JSON response (as returned by say
* endpoint.client_rows_select()) into our new join-graph format.  Long-term
* endpoint.rows_select should start producing join-graph formatted results that
* contain row_ids and a general overhaul.  This is the shim til we get there.
*******************************************************************************/

create or replace function endpoint.endpoint_response_to_joingraph (response jsonb, out joingraph_json json)
as $$

    select json_agg(r->'row')
    from json_array_elements((response::json)->'result') r;

$$ language sql;


/*

    execute 'select into join_graph_table array_to_json(array_agg((''{ "row": '' || row_to_json(tmp)::text || '', "selector": "hi mom"}'')::json)) from bundle_push_1234 tmp;
    -- result := ('{"columns":[{"name":"row_id","type":"row_id"},{"name":"row","type":"json"}], "result": ' || result2 || '}')::json;
*/
