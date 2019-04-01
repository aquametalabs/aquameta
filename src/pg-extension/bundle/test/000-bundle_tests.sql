begin;

create extension if not exists pgtap schema public;
set search_path=public,meta;

-- select plan(115);
select * from no_plan();

drop schema if exists bundle_test cascade;
create schema bundle_test;
set search_path=bundle_test, bundle, public;

\set bundle_id '\'9caeb540-8ad5-11e4-b4a9-0800200c9a66\''

delete from bundle where id= :bundle_id;

-- Test vars store temporary variables used internally for testing
create table bundle_test.test_vars (
    id serial primary key,
    starting_untracked_rows integer
);
insert into bundle_test.test_vars (starting_untracked_rows) values (NULL);



-- REPO_SUMMARY
--
-- A repo_summary is a custom type and utility function that holds the number
-- of rows in the various tables in the bundle system.  We use it to take
-- actions and then quickly compare it to expected row count totals.

create type repo_summary as (
    commit integer,
    head_commit_row integer,
    stage_row_added  integer,
    stage_row_deleted integer,
    stage_field_changed integer,
    offstage_row_deleted integer,
    offstage_field_changed integer,
    untracked_row integer
);

create function repo_summary (in bundle_name text, out result repo_summary) as $$
    declare
        _bundle_id uuid;
        starting_untracked_rows integer;
    begin
        select into _bundle_id id from bundle.bundle where name=bundle_name;
        select into starting_untracked_rows v.starting_untracked_rows from test_vars v;
        select into result
            (select count(*)::integer from bundle.commit c
                join bundle.rowset r on c.rowset_id=r.id where c.bundle_id=_bundle_id),
            (select count(*)::integer from bundle.head_commit_row r where r.bundle_id=_bundle_id),
            (select count(*)::integer from stage_row_added r where r.bundle_id=_bundle_id),
            (select count(*)::integer from stage_row_deleted r where r.bundle_id=_bundle_id),
            (select count(*)::integer from stage_field_changed r where r.bundle_id=_bundle_id),
            (select count(*)::integer from offstage_row_deleted r where r.bundle_id=_bundle_id),
            (select count(*)::integer from offstage_field_changed r where r.bundle_id=_bundle_id),
            (select (count(*)::integer - starting_untracked_rows) from untracked_row r);
    end;
$$ language plpgsql;

-- test data
create table bundle_test.chakra (
    id serial primary key,
    position integer,
    name text,
    color text,
    tone_hz decimal
);


-- setup our counter of starting untracked rows
update test_vars set starting_untracked_rows = (select count(*)::integer from bundle.untracked_row);



-------------------------------------------------------------------------------
-- TEST 1: no bundle
-------------------------------------------------------------------------------
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        0, -- commit
        0, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'No bundle yet, everything should be zeros'
);



-------------------------------------------------------------------------------
-- TEST 2: empty bundle
-------------------------------------------------------------------------------
insert into bundle.bundle (id, name) values (:bundle_id, 'com.aquameta.core.bundle.tests');
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        0, -- commit
        0, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'Empty bundle is empty'
);



-------------------------------------------------------------------------------
-- TEST 3: new untracked rows
-------------------------------------------------------------------------------
insert into bundle_test.chakra (id, position, name, color, tone_hz) values
    (1, 1, 'Root',         'red', 172.06),
    (2, 2, 'Navel',        'orange', 221.23),
    (3, 3, 'Solar Plexus', 'yellow', 141.27),
    (4, 4, 'Heart',        'green', 136.10)
;
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        0, -- commit
        0, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        4  -- untracked_rows
    )::repo_summary,
    'Four newly inserted rows should show up in untracked_rows'
);



-------------------------------------------------------------------------------
-- TEST 4: stage_row_add()
-------------------------------------------------------------------------------
select bundle.tracked_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',1::text);
select bundle.tracked_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',2::text);
select bundle.tracked_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',3::text);
select bundle.tracked_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',4::text);

select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',1::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',2::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',3::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',4::text);
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        0, -- commit
        0, -- head_commit_row
        4, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'stage_row_add() to the four new rows should remove them from untracked_rows and add them to stage_row_added'
);



-------------------------------------------------------------------------------
-- TEST 5: bundle.commit()
-------------------------------------------------------------------------------
select bundle.commit('com.aquameta.core.bundle.tests','here come the first four chakras');
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'Committing the four new rows should make one new commit, add four rows to head_commit_row, and zero out everything else'
);



-------------------------------------------------------------------------------
-- TEST 6: insert 2nd set of rows
-------------------------------------------------------------------------------
insert into bundle_test.chakra (id, position, name, color, tone_hz) values
    (5, 5, 'Throat',       'blue', 126.22),
    (6, 6, 'Third Eye',    'indego', 210.42)
;
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        2  -- untracked_rows
    )::repo_summary,
    'Inserting two new rows after existing commit should add two to untracked_rows and keep everything else the same.'
);



-------------------------------------------------------------------------------
-- TEST 7: second round of stage_row_add()
-------------------------------------------------------------------------------
select bundle.tracked_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',5::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',5::text);
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        1  -- untracked_rows
    )::repo_summary,
    'Staging a new rows should add it to the stage and remove it from stage_row_added and untracked_rows.'
);



-------------------------------------------------------------------------------
-- TEST 8: delete a tracked row
-------------------------------------------------------------------------------
delete from bundle_test.chakra where id=4;
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        1, -- offstage_row_deleted
        0, -- offstage_field_changed
        1  -- untracked_rows
    )::repo_summary,
    'Deleting a row that is in the head_commit should make it show up in offstage_row_deleted.'
);



-------------------------------------------------------------------------------
-- TEST 9: stage the delete of a tracked row
-------------------------------------------------------------------------------
select bundle.stage_row_delete('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',4::text);
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        1, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        1  -- untracked_rows
    )::repo_summary,
    'Staging a delete should remove that row from offstage_row_deleted and add it to stage_row_deleted.'
);



-------------------------------------------------------------------------------
-- TEST 10: delete a tracked row
-------------------------------------------------------------------------------
delete from bundle_test.chakra where id=6;
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        1, -- stage_row_deleted
        0, -- stage_field_changed
        0, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'Deleting a untracked row should reduce untracked by one and leave everything else the same'
);



-------------------------------------------------------------------------------
-- TEST 11: unstage a delete
-------------------------------------------------------------------------------
select bundle.unstage_row_delete('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',4::text);
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        1, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'Unstaging a previously staged delete should reduce stage_row_deleted by one and increase offstage_row_deleted by one.'
);



-------------------------------------------------------------------------------
-- TEST 12: changing a tracked field
-------------------------------------------------------------------------------
update bundle_test.chakra set color='rojo' where position=1;
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        1, -- offstage_row_deleted
        1, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'Changing a committed row should increase offstage_field_changed by one.'
);



-------------------------------------------------------------------------------
-- TEST 13: Staging a changed field
-------------------------------------------------------------------------------
select bundle.stage_field_change('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id','1', 'color');
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        1, -- commit
        4, -- head_commit_row
        1, -- stage_row_added
        0, -- stage_row_deleted
        1, -- stage_field_changed
        1, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    'Staging a changed field should decrease offstage_field_changed by one and increase stage_field_changed by one.'
);



-------------------------------------------------------------------------------
-- TEST 14: commit
-------------------------------------------------------------------------------
insert into bundle_test.chakra (id, position, name, color, tone_hz) values
    (7, 7, 'Crown',        'violet', 194.18)
;
select bundle.tracked_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',7::text);
select bundle.stage_row_add('com.aquameta.core.bundle.tests', 'bundle_test','chakra','id',7::text);
select bundle.commit('com.aquameta.core.bundle.tests','last few');
select bundle.checkout((select id from bundle.commit where message='last few'));
/*
select row_eq(
    $$ select * from repo_summary('com.aquameta.core.bundle.tests') $$,
    row(
        2, -- commit
        6, -- head_commit_row
        0, -- stage_row_added
        0, -- stage_row_deleted
        0, -- stage_field_changed
        1, -- offstage_row_deleted
        0, -- offstage_field_changed
        0  -- untracked_rows
    )::repo_summary,
    ''
);
*/


-------------------------------------------------------------------------------
-- TEST 14: delete and checkout
-------------------------------------------------------------------------------
delete from bundle_test.chakra;




rollback;
