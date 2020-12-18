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
-- TEST 1: client_rows_select
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_select function returns 200')
from endpoint.client_rows_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.relation_id('widget','input')) r;


-------------------------------------------------------------------------------
-- TEST 2: client_rows_select with args
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_select function with args returns 200')
from endpoint.client_rows_select('67f7d009-52d8-4a01-9b13-00188c904249', meta.relation_id('widget','input'), ARRAY['name'], ARRAY['row']) r;


-------------------------------------------------------------------------------
-- TEST 3: client_row_select
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
-- TEST 5: client_row_select_function
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_select_function returns 200')
from endpoint.client_rows_select_function('67f7d009-52d8-4a01-9b13-00188c904249', meta.function_id('bundle','commit_log',ARRAY['bundle_name']), ARRAY['com.aquameta.core.ide']) r;

-------------------------------------------------------------------------------
-- TEST 5: construct_join_graph
-------------------------------------------------------------------------------
create table movie (id serial primary key, name text);
create table actor (id serial primary key, name text);
create table movie_actor (id serial primary key, movie_id integer not null references movie(id), actor_id integer not null references actor(id));
insert into movie (id, name) values (1, 'Ghostbusters');
insert into movie (id, name) values (2, 'Groundhog Day');
insert into movie (id, name) values (3, 'Lost in Translation');
insert into actor (id, name) values (1, 'Bill Murray');
insert into actor (id, name) values (2, 'Susan Sarandon');
insert into actor (id, name) values (3, 'Paul Rudd');
insert into actor (id, name) values (4, 'Scarlett Johansen');
insert into actor (id, name) values (5, 'Harold Ramis');
insert into actor (id, name) values (6, 'Andie MacDowell');
insert into movie_actor (movie_id, actor_id) values (1,1), (1,5), (2,1), (2,6), (3,1), (3,4);

select endpoint.construct_join_graph('movies_join_graph',
    '{ "schema_name": "endpoint_test", "relation_name": "movie", "label": "m", "pk_field": "id", "where_clause": "name like ''G%'' ", "position": 1 }',
    '[
        {"schema_name": "endpoint_test", "relation_name": "movie_actor", "label": "ma", "pk_field": "id", "join_local_field": "id", "related_label": "m", "related_field": "id", "position": 2},
        {"schema_name": "endpoint_test", "relation_name": "actor", "label": "a", "pk_field": "id", "join_local_field": "id", "related_label": "ma", "related_field": "actor_id", "position": 3}
     ]');
select isnt (count(*)::integer, 0, 'join graph has rows') from movies_join_graph;

-------------------------------------------------------------------------------
-- TEST 6: join_graph_to_json
-------------------------------------------------------------------------------
select isnt (jsonb_array_length(endpoint.join_graph_to_json('movies_join_graph')), 0, 'join_graph_to_json produces non-empty json array');


-------------------------------------------------------------------------------
-- TEST 7: client_rows_insert
-------------------------------------------------------------------------------
select is (r.status_code, 200, 'rows_insert_function returns 200')
from endpoint.client_rows_insert('67f7d009-52d8-4a01-9b13-00188c904249', endpoint.join_graph_to_json('movies_join_graph')) r;

rollback;
