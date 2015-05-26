begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema endpoint_test;
set search_path=endpoint_test,public;

-- test remote
insert into endpoint.remote_endpoint(id,url, name) 
values ('67f7d009-52d8-4a01-9b13-00188c904249', 'http://demo.aquameta.org/endpoint', 'Test Server');

-------------------------------------------------------------------------------
-- TEST 1: rows_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_select function returns 200')
from endpoint.client_rows_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.relation_id('widget','input')) r;


-------------------------------------------------------------------------------
-- TEST 2: rows_select with args
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_select function with args returns 200')
from endpoint.client_rows_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.relation_id('widget','input'), ARRAY['name'], ARRAY['row']) r;


-------------------------------------------------------------------------------
-- TEST 3: row_select
-------------------------------------------------------------------------------
-- debugger3_manager
select is (r.status_code, 200, 'row_select function returns 200')
from endpoint.client_row_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.row_id('widget','widget','id','793960f9-5522-499b-a36e-144f80c8a741')) r;


-------------------------------------------------------------------------------
-- TEST 4: field_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'field_select function returns 200')
from endpoint.client_field_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.field_id('bundle','bundle','id','0c2aa87b-0a66-48cb-ac9d-733d0a740bde', 'name')) r;


-------------------------------------------------------------------------------
-- TEST 5: row_select_function
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_select_function returns 200')
from endpoint.client_rows_select_function('67f7d009-52d8-4a01-9b13-00188c904249', meta.function_id('bundle','commit_log',ARRAY['bundle_name']), ARRAY['com.aquameta.core.ide']) r;

-------------------------------------------------------------------------------
-- TEST 5: construct_join_graph
-------------------------------------------------------------------------------
select endpoint.construct_join_graph('test_join_graph',
    '{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id", "where_clause": "b.id = ''e2edb6c9-cb76-4b57-9898-2e08debe99ee''" }',
    '[
        {"schema_name": "bundle", "relation_name": "commit", "label": "c", "local_id": "bundle_id", "related_label": "b", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset", "label": "r", "local_id": "id", "related_label": "c", "related_field": "rowset_id"},
        {"schema_name": "bundle", "relation_name": "rowset_row", "label": "rr", "local_id": "rowset_id", "related_label": "r", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset_row_field", "label": "rrf", "local_id": "rowset_row_id", "related_label": "rr", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "blob", "label": "blb", "local_id": "hash", "related_label": "rrf", "related_field": "value_hash"}
     ]');
select isnt (count(*)::integer, 0, 'join graph has rows') from test_join_graph;


-------------------------------------------------------------------------------
-- TEST 6: join_graph_to_json
-------------------------------------------------------------------------------
select isnt (jsonb_array_length(endpoint.join_graph_to_json('test_join_graph')), 0, 'join_graph_to_json produces non-empty json array');


-------------------------------------------------------------------------------
-- TEST 7: rows_insert_function
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_insert_function returns 200')
from endpoint.client_rows_insert('67f7d009-52d8-4a01-9b13-00188c904249', endpoint.join_graph_to_json('test_join_graph')) r;

rollback;
