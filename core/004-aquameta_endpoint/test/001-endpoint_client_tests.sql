begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema endpoint_test;
set search_path=endpoint_test,public;

-- \set test_url '\'http://demo.aquameta.org/\''
insert into endpoint.remote_endpoint(id,url) values ('67f7d009-52d8-4a01-9b13-00188c904249', 'http://demo.aquameta.org/endpoint');
-------------------------------------------------------------------------------
-- TEST 1: GET status_code
-------------------------------------------------------------------------------
/*
select is (r.status_code, 200, 'GET status_code')
from endpoint.rows_select('http://demo.aquameta.org/endpoint') r;
*/



rollback;
