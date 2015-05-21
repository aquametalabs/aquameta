begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema http_client_test;
set search_path=http_client_test,public;

-- \set test_url '\'http://demo.aquameta.org/index.html\''

-------------------------------------------------------------------------------
-- TEST 1: GET response_text
-------------------------------------------------------------------------------
select is (r.response_text, 'hi mom', 'GET response_text')
from http_client.http_get('http://demo.aquameta.org/index.html') r;


-------------------------------------------------------------------------------
-- TEST 2: GET status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'GET status_code')
from http_client.http_get('http://demo.aquameta.org/index.html') r;




rollback;
