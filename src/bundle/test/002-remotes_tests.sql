begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

select * from no_plan();

create schema bundle_remotes_test;
set search_path=bundle_remotes_test,public;


-- test bundle
create table bundle_remotes_test.chakra (
    id serial primary key,
    position integer,
    name text,
    color text,
    tone_hz decimal
);

-- test bundle, endpoint and remote
\set bundle_id '\'9caeb540-8ad5-11e4-b4a9-0800200c9a66\''
\set remote_endpoint_id '\'67f7d009-52d8-4a01-9b13-00188c904249\''
\set remote_id '\'24aa68f7-0676-4289-8246-27d1d075e194\''

insert into bundle.bundle (id, name) values (:bundle_id, 'com.aquameta.core.bundle.tests');
insert into endpoint.remote_endpoint(id,url, name) values (:remote_endpoint_id, 'http://demo.aquameta.org/endpoint', 'Test Server');
insert into bundle.remote(id, endpoint_id, bundle_id) values (:remote_id, :remote_endpoint_id, :bundle_id);


-------------------------------------------------------------------------------
-- TEST 1: remote_has_bundle false
-------------------------------------------------------------------------------
select is (r, false, 'test bundle does not exist on remote server')
from bundle.remote_has_bundle(:remote_id) r;


-------------------------------------------------------------------------------
-- TEST 2: remote_compare_commits
-------------------------------------------------------------------------------
select is (count(*)::integer, 0, 'new repo compare commits has no rows')
from bundle.remote_compare_commits(:remote_id);


-- test data
insert into bundle_remotes_test.chakra (id, position, name, color, tone_hz) values
    (1, 1, 'Root',         'red', 172.06),
    (2, 2, 'Navel',        'orange', 221.23),
    (3, 3, 'Solar Plexus', 'yellow', 141.27),
    (4, 4, 'Heart',        'green', 136.10),
    (5, 5, 'Throat',       'blue', 126.22),
    (6, 6, 'Third Eye',    'indego', 210.42),
    (7, 7, 'Crown',        'violet', 194.18)
;

-- test commit
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_remotes_test','chakra','id',1::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_remotes_test','chakra','id',2::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_remotes_test','chakra','id',3::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_remotes_test','chakra','id',4::text);
select bundle.commit('com.aquameta.core.bundle.tests','here come the first four chakras');

-------------------------------------------------------------------------------
-- TEST 2: remote_compare_commits
-------------------------------------------------------------------------------
select is (count(*)::integer, 1, 'new repo compare commits has no rows')
from bundle.remote_compare_commits(:remote_id) where local_commit_id is not null and remote_commit_id is null;


-------------------------------------------------------------------------------
-- TEST 3: construct_bundle_diff
-------------------------------------------------------------------------------
select bundle.construct_bundle_diff(:bundle_id, (select array_agg(id) from bundle.commit where bundle_id=:bundle_id), 'test_bundle_diff');
select isnt (count(*)::integer, 0, 'bundle diff has rows')
from test_bundle_diff;


-------------------------------------------------------------------------------
-- TEST 4: remote_push with create_bundle true makes compare = 1
-------------------------------------------------------------------------------
select bundle.remote_push(:remote_id, true);
select is (count(*)::integer, 1, 'after push, remote_compare_commits = 1')
from bundle.remote_compare_commits(:remote_id) where remote_commit_id is not null;


-------------------------------------------------------------------------------
-- TEST 5: remote_has_bundle false
-------------------------------------------------------------------------------
select is (r, true, 'after push, test bundle now exists')
from bundle.remote_has_bundle(:remote_id) r;


-------------------------------------------------------------------------------
-- TEST 6: new commit
-------------------------------------------------------------------------------
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_remotes_test','chakra','id',5::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_remotes_test','chakra','id',6::text);
select bundle.commit('com.aquameta.core.bundle.tests','next two chakras');


-------------------------------------------------------------------------------
-- TEST 7: remote_push with create_bundle true makes compare = 1
-------------------------------------------------------------------------------
drop table test_bundle_diff;
select bundle.remote_push(:remote_id, false);
select is (count(*)::integer, 2, 'after second push, remote_commits = 2 and local_commits = 2')
from bundle.remote_compare_commits(:remote_id) where remote_commit_id is not null and local_commit_id is not null;


-------------------------------------------------------------------------------
-- TEST 8: delete the local commits and compare
-------------------------------------------------------------------------------
select bundle.delete_commit(c.id) from bundle.bundle b join bundle.commit c on c.bundle_id=b.id where b.id = :bundle_id;
select is (count(*)::integer, 2, 'after deleting local commits, remote_commits = 2 and local = 0')
from bundle.remote_compare_commits(:remote_id) where remote_commit_id is not null and local_commit_id is null;


-------------------------------------------------------------------------------
-- TEST 9: fetch pushed commits
-------------------------------------------------------------------------------
select bundle.remote_fetch(:remote_id, false);
select is (count(*)::integer, 2, 'after pull, remote_compare_commits = 2')
from bundle.remote_compare_commits(:remote_id) where remote_commit_id is not null and local_commit_id is not null;

