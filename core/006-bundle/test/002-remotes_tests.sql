begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema bundle_remotes_test;
set search_path=bundle_remotes_test,public;

-- test remote
insert into endpoint.remote_endpoint(id,url, name) 
values ('67f7d009-52d8-4a01-9b13-00188c904249', 'http://demo.aquameta.org/endpoint', 'Test Server');

insert into bundle.remote(id, endpoint_id, bundle_id) 
values ('24aa68f7-0676-4289-8246-27d1d075e194', '67f7d009-52d8-4a01-9b13-00188c904249', '737177af-16f4-40e1-ac0d-2c11b2b727e9');

-------------------------------------------------------------------------------
-- TEST 1: remote_has_bundle true
-------------------------------------------------------------------------------
select is (r, true, 'ide bundle exists')
from bundle.remote_has_bundle('24aa68f7-0676-4289-8246-27d1d075e194') r;


-------------------------------------------------------------------------------
-- TEST 2: remote_has_bundle false
-------------------------------------------------------------------------------
select is (r, false, 'some made-up bundle does not exist')
from bundle.remote_has_bundle('24aa68f7-0676-4289-8246-27d1d075e192') r;


-------------------------------------------------------------------------------
-- TEST 3: remote_compare_commits
-------------------------------------------------------------------------------
select isnt (count(*), 0, 'GET status_code')
from remote_compare_commits('24aa68f7-0676-4289-8246-27d1d075e194');




rollback;
