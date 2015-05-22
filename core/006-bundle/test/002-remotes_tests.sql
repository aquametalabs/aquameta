begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema bundle_remotes_test;
set search_path=bundle_remotes_test,public;

-- test remote
insert into endpoint.remote_endpoint(id,url, name) 
values ('67f7d009-52d8-4a01-9b13-00188c904249', 'http://demo.aquameta.org/endpoint', 'Test Server');

insert into endpoint.remote(id, remote_id, bundle_id) 
values ('00000000-52d8-4a01-9b13-00188c904249', );

-------------------------------------------------------------------------------
-- TEST 1: rows_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'GET status_code')
from endpoint.client_rows_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.relation_id('widget','input')) r;


-------------------------------------------------------------------------------
-- TEST 2: row_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'GET status_code')
from endpoint.client_row_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.row_id('bundle','bundle','id','0c2aa87b-0a66-48cb-ac9d-733d0a740bde')) r;


-------------------------------------------------------------------------------
-- TEST 3: field_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'GET status_code')
from endpoint.client_field_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.field_id('bundle','bundle','id','0c2aa87b-0a66-48cb-ac9d-733d0a740bde', 'name')) r;


-------------------------------------------------------------------------------
-- TEST 4: row_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'GET status_code')
from endpoint.client_rows_select_function('67f7d009-52d8-4a01-9b13-00188c904249', meta.function_id('bundle','commit_log',ARRAY['bundle_name']), ARRAY['com.aquameta.bundle']) r;



rollback;
