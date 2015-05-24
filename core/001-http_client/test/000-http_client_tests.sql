begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema http_client_test;
set search_path=http_client_test,public;

-- \set test_url '\'http://httpbin.org/\''

-------------------------------------------------------------------------------
-- TEST 1: GET status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'GET status_code')
from http_client.http_get('http://httpbin.org/get') r;


-------------------------------------------------------------------------------
-- TEST 2: POST status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'POST status_code')
from http_client.http_post('http://httpbin.org/post', 'hi mom') r;


-------------------------------------------------------------------------------
-- TEST 3: POST json status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'POST JSON status_code')
from http_client.http_post('http://httpbin.org/post', '{"hi": "mom"}'::json) r;


-------------------------------------------------------------------------------
-- TEST 4: PATCH status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'PATCH status_code')
from http_client.http_patch('http://httpbin.org/patch', 'hi mom') r;


-------------------------------------------------------------------------------
-- TEST 5: PATCH json status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'PATCH JSON status_code')
from http_client.http_patch('http://httpbin.org/patch', '{"hi": "mom"}'::json) r;


-------------------------------------------------------------------------------
-- TEST 6: DELETE status_code
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'DELETE status_code')
from http_client.http_delete('http://httpbin.org/delete') r;





rollback;
