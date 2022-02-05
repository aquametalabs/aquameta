/*******************************************************************************
 * Bundle
 * Data Version Control System
 * 
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/


/*
 * Code is organized as follows:
 *     1. bundle bundle data model - the tables where bundles are stored
 *     2. head - views that contain the "current" commit from every bundle
 *     3. ignored - where you specify parts of the db that show stay untracked
 *     4. staged changes - where you specify rows/fields that should be different
 *        from the head commit, in the next commit
 *     5. offstage changes - views that contain the parts of the db that are
 *        different from the head commit
 *     6. stage - contains what the next commit would look like if you were to
 *        commit right now
 *     7. status - summarizes the status of the head commit, working copy db, and
 *        stage
 *     8. untracked - rows which are not in any head commit, and available for
 *        stage_row_add()
 *     9. remotes - pushing and pulling to other databases
 *
 */
-------------------------
-- UTIL FIXME
--------------------------
create or replace function exec(statements text[]) returns setof record as $$
   declare
       statement text;
   begin
       foreach statement in array statements loop
           -- raise info 'EXEC statement: %', statement;
           return query execute statement;
       end loop;
    end;
$$ language plpgsql volatile returns null on null input;

------------------------------------------------------------------------------
-- 1. REPOSITORY DATA MODEL
------------------------------------------------------------------------------

-- hash table

create table blob (
    hash text unique,
    value text
);

create or replace function blob_hash_gen_trigger() returns trigger as $$
    begin
        if NEW.value = NULL then
            return NULL;
        end if;

        NEW.hash = public.digest(NEW.value, 'sha256');
        if exists (select 1 from bundle.blob b where b.hash = NEW.hash) then
            return NULL;
        end if;

        return NEW;
    end;
$$ language plpgsql;

create trigger blob_hash_update
    before insert or update on blob
    for each row execute procedure blob_hash_gen_trigger();


-- bundle


create table bundle (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '',
    -- head_commit_id uuid, -- (circular, added later)
    -- checkout_commit_id uuid, -- (circular, added later)
    unique(name)
);

create table rowset (
    id uuid not null default public.uuid_generate_v4() primary key
);

create table rowset_row (
    id uuid not null default public.uuid_generate_v4() primary key,
    rowset_id uuid references rowset(id) on delete cascade,
    row_id meta.row_id
);

create table rowset_row_field (
    id uuid not null default public.uuid_generate_v4() primary key,
    rowset_row_id uuid references rowset_row(id) on delete cascade,
    field_id meta.field_id,
    value_hash text references blob(hash) on delete cascade,
    unique(rowset_row_id, field_id)
);

create table commit (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid references bundle(id) on delete cascade,
    rowset_id uuid references rowset(id) on delete cascade,
    role_id meta.role_id,
    parent_id uuid references commit(id),
    -- TODO: merge_parent_id uuid references commit(id),
    time timestamp not null default now(),
    message text
);
-- circular
alter table bundle add head_commit_id uuid references commit(id) on delete set null;
alter table bundle add checkout_commit_id uuid references commit(id) on delete set null;

create table merge_conflict (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid references bundle(id) on delete cascade,
    field_id meta.field_id not null,
    conflict_value text,
    rowset_row_field_id uuid not null references bundle.rowset_row_field(id) on delete cascade
);



------------------------------------------------------------------------------
-- 2. HEAD
-- Views that contain the "current" commit from each bundle, the commit
-- referenced by bundle.head_commit_id.
------------------------------------------------------------------------------

-- head_commit_row: show the rows head commit
create view head_commit_row as
select bundle.id as bundle_id, c.id as commit_id, rr.row_id from bundle.bundle bundle
    join bundle.commit c on bundle.head_commit_id=c.id
    join bundle.rowset r on r.id = c.rowset_id
    join bundle.rowset_row rr on rr.rowset_id = r.id;


-- head_commit_row: show the fields in each head commit
create view head_commit_field as
select bundle.id as bundle_id, rr.row_id, f.field_id, f.value_hash from bundle.bundle bundle
    join bundle.commit c on bundle.head_commit_id=c.id
    join bundle.rowset r on r.id = c.rowset_id
    join bundle.rowset_row rr on rr.rowset_id = r.id
    join bundle.rowset_row_field f on f.rowset_row_id = rr.id;


-- head_commit_row_with_exists: rows in the head commit, along with whether or
-- not that row actually exists in the database
create view head_commit_row_with_exists as
select bundle.id as bundle_id, c.id as commit_id, rr.row_id, meta.row_exists(rr.row_id) as exists
from bundle.bundle bundle
    join bundle.commit c on bundle.head_commit_id=c.id
    join bundle.rowset r on r.id = c.rowset_id
    join bundle.rowset_row rr on rr.rowset_id = r.id;
    -- order by meta.row_exists(rr.row_id), rr.row_id;



------------------------------------------------------------------------------
-- 3. IGNORED
-- Ignored rows do not show up in untracked_row and are not available for
-- adding to staged_row_new.  The user inserts into ignored_row a row that they
-- don't want to continue to be hassled about adding to the stage.
------------------------------------------------------------------------------
create table ignored_row (
    id uuid not null default public.uuid_generate_v4() primary key,
    row_id meta.row_id
);

create table ignored_schema (
    id uuid not null default public.uuid_generate_v4() primary key,
    schema_id meta.schema_id not null
);

create table ignored_relation (
    id uuid not null default public.uuid_generate_v4() primary key,
    relation_id meta.relation_id not null
);

create table ignored_column (
    id uuid not null default public.uuid_generate_v4() primary key,
    column_id meta.column_id not null
);


------------------------------------------------------------------------------
-- 4. STAGED CHANGES
--
-- The tables where users add changes to be included in the next commit:  New
-- rows, deleted rows and changed fields.
------------------------------------------------------------------------------

-- a row not in the current commit, but is marked to be added to the next commit
create table stage_row_added (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id) on delete cascade,
    row_id meta.row_id,
    unique (bundle_id, row_id)
); -- TODO: check that rows inserted into this table ARE NOT in the head commit's rowset

-- a row that is marked to be deleted from the current commit in the next commit
create table stage_row_deleted (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id) on delete cascade,
    rowset_row_id uuid references rowset_row(id),
    unique (bundle_id, rowset_row_id)
); -- TODO: check that rows inserted into this table ARE in the head commit's rowset

-- a field that is marked to be different from the current commit in the next
-- commit, with it's value
create table stage_field_changed (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id),
    field_id meta.field_id,
    new_value text,
    unique (bundle_id, field_id)
); -- TODO: check that rows inserted into this table ARE in the head commit's rowset




------------------------------------------------------------------------------
-- 5. OFFSTAGE CHANGES
--
-- A diff between the head commits of all the bundles, and the database.  AKA
-- changes to things that are tracked, that have not yet been staged.  Rows
-- show up in these views if rows in the head commit are different than rows in
-- the database.
------------------------------------------------------------------------------
-- deleted
create view offstage_row_deleted as
select row_id, bundle_id
from bundle.head_commit_row_with_exists
where exists = false
-- TODO make this an except
and row_id not in
(select rr.row_id from bundle.stage_row_deleted srd join bundle.rowset_row rr on rr.id = srd.rowset_row_id)
;

create view offstage_row_deleted_by_schema as
select
    row_id::meta.schema_id as schema_id,
    (row_id::meta.schema_id).name as schema_name,
    count(*) as count
from bundle.offstage_row_deleted
group by schema_id;

create view offstage_row_deleted_by_relation as
select row_id::meta.schema_id as schema_id,
    (row_id::meta.schema_id).name as schema_name,
    row_id::meta.relation_id as relation_id,
    (row_id::meta.relation_id).name as relation_name,
    count(*) as count
from bundle.offstage_row_deleted
group by schema_id, relation_id;


-- field changed
create view offstage_field_changed as
select * from (
select
    field_id,
    row_id,
    b.value as old_value,
    meta.field_id_literal_value(field_id) as new_value,
    bundle_id
from bundle.head_commit_field f
join bundle.blob b on f.value_hash = b.hash
where /* meta.field_id_literal_value(field_id) != f.value FIXME: Why is this so slow?  workaround by nesting selects.  still slow.
    and */ f.field_id not in
    (select ofc.field_id from bundle.stage_field_changed ofc)
) x where old_value != new_value; -- FIXME: will break on nulls

/*
create view offstage_field_changed_by_schema as
select
    row_id::meta.schema_id as schema_id,
    (row_id::meta.schema_id).name as schema_name,
    count(*) as count
from bundle.offstage_field_changed
group by schema_id;

create view offstage_field_changed_by_relation as
select row_id::meta.schema_id as schema_id,
    (row_id::meta.schema_id).name as schema_name,
    row_id::meta.relation_id as relation_id,
    (row_id::meta.relation_id).name as relation_name,
    count(*) as count
from bundle.offstage_field_changed
group by schema_id, relation_id;
*/



------------------------------------------------------------------------------
-- 6. STAGE
--
-- A virtual view of what the next commit will look like: The head commit's
-- rowset, minus rows in stage_row_deleted, plus rows in stage_row_added,
-- overwritten by field values in stage_field_changed
------------------------------------------------------------------------------

create view stage_row as
    -- the head commit's rowset rows
    select b.id as bundle_id, rr.row_id as row_id, false as new_row
        from bundle.rowset_row rr
        join bundle.rowset r on rr.rowset_id=r.id
        join bundle.commit c on c.rowset_id = r.id
        join bundle.bundle b on c.bundle_id=b.id
            and b.head_commit_id = c.id

    union
    -- plus stage_row_added
    select bundle_id, row_id, true as new_row
    from bundle.stage_row_added

    except
    -- minus stage_row_deleted
    select srd.bundle_id, rr.row_id, false
        from bundle.stage_row_deleted srd
        join bundle.rowset_row rr on srd.rowset_row_id = rr.id;



/*
a virtual view of what the next commit's fields will look like.  it's centered
around stage_row, we can definitely start there.  then, we get the field values
from:

a) if it was in the previous commit, those fields, but overwritten by stage_field_changed.  stage_row already takes care of removing stage_row_added and stage_row_deleted.

b) if it is a newly added row (it'll be in stage_row_added), then use the working copy's fields

c) what if you have a stage_field_changed on a newly added row?  then, not sure.  probably use it?

problem: stage_field_change contains W.C. data when there are unstaged changes.

*/



create or replace view stage_row_field as
---------- new rows ----------
select stage_row_id, field_id, value, encode(public.digest(value, 'sha256'),'hex') as value_hash from (
    select
        sr.row_id as stage_row_id,
        meta.field_id(
            re.schema_name,
            re.name,
            re.primary_key_column_names[1], -- FIXME
            (sr.row_id).pk_value,
            c.name
        ) as field_id,

        meta.field_id_literal_value( ----  THIS IS SLOW!
            meta.field_id(
                re.schema_name,
                re.name,
                re.primary_key_column_names[1], -- FIXME
                (sr.row_id).pk_value,
                c.name
            )
        )::text as value

    from bundle.stage_row_added sr
        join meta.relation re on sr.row_id::meta.relation_id = re.id
        join meta.relation_column c on c.relation_id=re.id
    ) r

union all

------------ old rows with changed fields -------------
select
    sr.row_id as stage_row_id,
    hcf.field_id as field_id,
    case
        when sfc.field_id is not null then
            sfc.new_value
        else b.value
    end as value,
    hcf.value_hash
from bundle.stage_row sr
    left join bundle.head_commit_field hcf on sr.row_id::text=hcf.row_id::text
    left join bundle.blob b on hcf.value_hash = b.hash
    left join stage_field_changed sfc on sfc.field_id::text = hcf.field_id::text
    where sr.new_row=false;


/*


ATTEMPT TO OPTIMIZE STAGE_ROW_FIELD, ended in tears.

ok.
1. for all the rows in stage_row, aggregate each relation, it's pk column, and the pks of each row.
2. for each relation in the above, select * from that relation where pk in keys into a json_agg
3. convert the json_agg to field_id and value, one per row


-- returns a relation_id, the column name of it's primary key, and all the pks
-- of all the rows in that relation_id on the stage

create or replace view _stage_relation_keys as
with srk as (
select
	stage_row.row_id::meta.relation_id as relation_id,
	((stage_row.row_id).pk_column_id).name as pk_column_name,
	string_agg(quote_literal((stage_row.row_id).pk_value),',') as keys
from stage_row
group by (stage_row.row_id::meta.relation_id, ((stage_row.row_id).pk_column_id).name))



-- takes a relation_id, pk name and
create or replace function bundle.stage_row_keys_to_fields ()
returns setof json as $$
declare
	keys text;
	rows_json json[];
    fields meta.field_id[];
begin
    return query execute 'select row_to_json(r) from (select * from '
            || quote_ident((relation_id::meta.schema_id).name) || '.'
            || quote_ident(relation_id.name)
            || ' where ' || quote_ident(pk_column_name) || '::text in'
			|| '(' || keys || ')'
            || ') r';

end;
$$ language plpgsql;

create or replace view stage_row_field as
with srk as (
    select * from _stage_relation_keys
)
select * from bundle.stage_row_keys_to_fields(srk.relation_id, srk.pk_column_name, srk.keys);

*/


------------------------------------------------------------------------------
-- 7. TRACKED
--
-- rows that are in the "scope of concern" of the bundle.  a row must be
-- tracked before it can be staged.
------------------------------------------------------------------------------

create table tracked_row_added (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id) on delete cascade,
    row_id meta.row_id,
    unique (row_id)
);


create or replace view bundle.tracked_row as
   select b.id as bundle_id, hcr.row_id
   from bundle.bundle b
   join bundle.head_commit_row hcr on hcr.bundle_id=b.id

   union

   -- tracked_row_added
   select b.id, tra.row_id
   from bundle.bundle b
   join bundle.tracked_row_added tra on tra.bundle_id=b.id

   union

   select b.id, sra.row_id
   from bundle.bundle b
   join bundle.stage_row_added sra on sra.bundle_id=b.id;




------------------------------------------------------------------------------
-- 8. STATUS
--
-- a view that pulls together rows from the head commit, live working copy db,
-- and stage.  it's sorted by change_type: deleted, modified, same, added.
------------------------------------------------------------------------------


-- FIXME: this is slow because of odd/slow behavior by offstage_field_changed
create or replace view head_db_stage as
select
    *,
    meta.row_exists(row_id) as row_exists,
    case
        when change_type = 'same' then null
        when change_type = 'deleted' then (stage_row_id is null)
        when change_type = 'added' then true
        when change_type = 'modified' then null
        when change_type = 'tracked' then false
    end as staged,

    (head_row_id is not null) in_head
from (
    select
        coalesce (hcr.bundle_id, sr.bundle_id) as bundle_id,
        hcr.commit_id,
        coalesce (hcr.row_id, sr.row_id) as row_id,
        hcr.row_id as head_row_id,
        sr.row_id as stage_row_id,

        -- change_type
        case
            when sr.row_id is null then 'deleted'
            when hcr.row_id is null then  'added'
            when
                array_remove(array_agg(ofc.field_id), null) != '{}'
                or array_remove(array_agg(sfc.field_id), null) != '{}' then  'modified'
            when meta.row_exists(sr.row_id) = false then 'deleted'
            else 'same'
        end as change_type,

        -- offstage changes
        array_remove(array_agg(ofc.field_id), null) as offstage_field_changes,
        array_agg(ofc.old_value) as offstage_field_changes_old_vals,
        array_agg(ofc.new_value) as offstage_field_changes_new_vals,
        -- staged changes
        array_remove(array_agg(sfc.field_id), null) as stage_field_changes,
        array_agg(ofc.old_value) as stage_field_changes_old_vals,
        array_agg(sfc.new_value) as stage_field_changes_new_vals

    from bundle.head_commit_row hcr
    full outer join bundle.stage_row sr on hcr.row_id::text=sr.row_id::text
    left join stage_field_changed sfc on (sfc.field_id).row_id::text=hcr.row_id::text
    left join offstage_field_changed ofc on (ofc.field_id).row_id::text=hcr.row_id::text
    group by hcr.bundle_id, hcr.commit_id, hcr.row_id, sr.bundle_id, sr.row_id, (sfc.field_id).row_id, (ofc.field_id).row_id

    union

    select tra.bundle_id, null, tra.row_id, null, null, 'tracked', null, null, null, null, null, null
    from bundle.tracked_row_added tra

) c
order by
case c.change_type
    when 'tracked' then 0
    when 'deleted' then 1
    when 'modified' then 2
    when 'same' then 3
    when 'added' then 4
end, row_id;


create view head_db_stage_changed as
select * from bundle.head_db_stage
where change_type != 'same'
    or stage_field_changes::text != '{}'
    or offstage_field_changes::text != '{}'
    or row_exists = false;



------------------------------------------------------------------------------
-- 9. UNTRACKED
--
-- All currently existing database rows that are not ignored (directly or via a
-- cascade), not currently in any of the head commits, and not in
-- stage_row_added [or stage_row_deleted?].
------------------------------------------------------------------------------

create table trackable_nontable_relation (
    id uuid not null default public.uuid_generate_v4() primary key,
    pk_column_id meta.column_id not null
);


-- Relations that are not specifically ignored, and not in a ignored schema
-- TODO: why does this have schema_id and pk_column_id?  should just be a relation_id no?
create or replace view trackable_relation as
    select relation_id, schema_id, primary_key_column_id from (
       -- every single table
    select t.id as relation_id, s.id as schema_id, r.primary_key_column_ids[1] as primary_key_column_id --TODO audit column
    from meta.schema s
    join meta.table t on t.schema_id=s.id
    join meta.relation r on r.id=t.id -- only work with relations that have a primary key
    where primary_key_column_ids[1] is not null

    -- combined with every view in the meta schema
    UNION
    select pk_column_id::meta.relation_id as relation_id, pk_column_id::meta.schema_id as schema_id, pk_column_id as primary_key_column_id
    from bundle.trackable_nontable_relation
) r

    -- ...that is not ignored
    where relation_id not in (
        select relation_id from bundle.ignored_relation
    )
    -- ...and is not in an ignored schema
    and schema_id not in (
        select schema_id from bundle.ignored_schema
    )
;

/*

Generates a set of sql statements that select the row_id of all non-ignored rows, aka
rows that are not ignored by schema- or relation-ignores.

TODO: ignore rows in ignored_row
*/

create or replace view bundle.not_ignored_row_stmt as
select *, 'select meta.row_id(' ||
        quote_literal((r.schema_id).name) || ', ' ||
        quote_literal((r.relation_id).name) || ', ' ||
        quote_literal((r.primary_key_column_id).name) || ', ' ||
        quote_ident((r.primary_key_column_id).name) || '::text ' ||
    ') as row_id from ' ||
    quote_ident((r.schema_id).name) || '.' || quote_ident((r.relation_id).name) ||

    -- special case meta rows so that ignored_* cascades down to all objects in it's scope
    case
        -- schemas
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) = 'schema' then
           ' where id not in (select schema_id from bundle.ignored_schema)'
        -- relations
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('table', 'view', 'relation') then
           ' where id not in (select relation_id from bundle.ignored_relation) and schema_id not in (select schema_id from bundle.ignored_schema)'
        -- functions
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) = 'function_definition' then
           ' where id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- columns
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) = 'column' then
           ' where id not in (select column_id from bundle.ignored_column) and id::meta.relation_id not in (select relation_id from bundle.ignored_relation) and id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- objects that exist in schema scope
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('operator') then
           ' where meta.schema_id(schema_name) not in (select schema_id from bundle.ignored_schema)'
        -- objects that exist in schema scope
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('type_definition') then
           ' where id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- objects that exist in table scope
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('constraint_check','constraint_unique','table_privilege') then
           ' where meta.schema_id(schema_name) not in (select schema_id from bundle.ignored_schema) and table_id not in (select relation_id from bundle.ignored_relation)'
        else ''
    end
    as stmt
from bundle.trackable_relation r;


create or replace view untracked_row as
select r.row_id /*, r.row_id::meta.relation_id as relation_id */
    from bundle.exec((
        select array_agg (stmt) from bundle.not_ignored_row_stmt
    )) r(
        row_id meta.row_id
    )
where r.row_id::text not in (
    select a.row_id::text from bundle.stage_row_added a
    union
    select t.row_id::text from bundle.tracked_row_added t
    union
    select rr.row_id::text from bundle.stage_row_deleted d join rowset_row rr on d.rowset_row_id=rr.id
    union
    select rr.row_id::text from bundle.bundle bundle
        join bundle.commit c on bundle.head_commit_id=c.id
        join bundle.rowset r on c.rowset_id = r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
);


create or replace view untracked_row_by_schema as
select r.row_id::meta.schema_id schema_id, (r.row_id::meta.schema_id).name as schema_name, count(*) as count
from bundle.untracked_row r
group by r.row_id::meta.schema_id, (r.row_id::meta.schema_id).name;

create or replace view untracked_row_by_relation as
select
    (r.row_id::meta.relation_id) relation_id,
    (r.row_id::meta.relation_id).name relation_name,
    (r.row_id::meta.schema_id) schema_id, count(*) as count
from bundle.untracked_row r
group by (r.row_id::meta.relation_id), (r.row_id::meta.relation_id).name, r.row_id::meta.schema_id;


-- here's a table where you can stash some saved connections.
create table remote_database (
    id uuid not null default public.uuid_generate_v4() primary key,
    foreign_server_name text not null default '' unique,
    schema_name text not null default '' unique,
    connection_string text not null default '',
    username text not null default '',
    password text not null default ''
);


------------------------------------------------------------------------------
-- 10. ORIGINS
--
-- When a bundle is imported or fetched, the origin is the source from whence
-- it came.   We use this on push and pull, import and export.
------------------------------------------------------------------------------

create table bundle_csv (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid references bundle(id) on delete cascade,
    directory text not null
);


create table bundle_remote_database (
    id uuid not null default public.uuid_generate_v4() primary key,
    -- question: do we want name?  "origin" would be a typical name in git terms, but also looking at the remote_db's connection string is a pretty good name...
    name text not null default '[ unnamed ]',
    bundle_id uuid references bundle(id) on delete cascade,
    remote_database_id uuid references remote_database(id) on delete cascade
);


------------------------------------------------------------------------------
-- 12. MIGRATIONS
--
-- SQL script to be run when a commit is checked out.  Additive, runs all
-- prior migrations in the commit tree
------------------------------------------------------------------------------

create table migration (
    id uuid not null default public.uuid_generate_v4() primary key,
    description text not null default '',
    sql_up text not null default '',
    sql_down text not null default ''
);


------------------------------------------------------------------------------
-- 13. EXTENSION DUMP CONFIGURATION
--
-- Set tables so that when pg_dump runs, their contents (rows) are dumped
-- (which doesn't happen by default)
------------------------------------------------------------------------------

select pg_catalog.pg_extension_config_dump('blob','');
select pg_catalog.pg_extension_config_dump('bundle','');
select pg_catalog.pg_extension_config_dump('commit','');
select pg_catalog.pg_extension_config_dump('ignored_column','');
select pg_catalog.pg_extension_config_dump('ignored_relation','');
select pg_catalog.pg_extension_config_dump('ignored_row','');
select pg_catalog.pg_extension_config_dump('ignored_schema','');
select pg_catalog.pg_extension_config_dump('remote_database','');
select pg_catalog.pg_extension_config_dump('rowset','');
select pg_catalog.pg_extension_config_dump('rowset_row','');
select pg_catalog.pg_extension_config_dump('rowset_row_field','');
select pg_catalog.pg_extension_config_dump('stage_field_changed','');
select pg_catalog.pg_extension_config_dump('stage_row_added','');
select pg_catalog.pg_extension_config_dump('stage_row_deleted','');
select pg_catalog.pg_extension_config_dump('trackable_nontable_relation','');
select pg_catalog.pg_extension_config_dump('tracked_row_added','');
select pg_catalog.pg_extension_config_dump('bundle_csv','');
select pg_catalog.pg_extension_config_dump('bundle_remote_database','');
/*******************************************************************************
 * Bundle
 * Data Version Control System
 *
 * Copyright (c) 2020 - Aquameta, LLC - http://aquameta.org/
 ******************************************************************************/

/*
 * User Functions
 *     1. commit
 *     2. stage
 *     3. checkout
 */

------------------------------------------------------------------------------
-- COMMIT FUNCTIONS
------------------------------------------------------------------------------
create or replace function commit (bundle_name text, message text) returns void as $$
    declare
        _bundle_id uuid;
        new_rowset_id uuid;
        new_commit_id uuid;
    begin

    raise notice 'bundle: Committing to %', bundle_name;

    select id
    into _bundle_id
    from bundle.bundle
    where name = bundle_name;

    -- make a rowset that will hold the contents of this commit
    insert into bundle.rowset default values
    returning id into new_rowset_id;

    -- STAGE
    raise notice 'bundle: Committing rowset_rows...';
    -- ROWS: copy everything in stage_row to the new rowset
    insert into bundle.rowset_row (rowset_id, row_id)
    select new_rowset_id, row_id from bundle.stage_row where bundle_id=_bundle_id;


    raise notice 'bundle: Committing blobs...';
    -- FIELDS: copy all the fields in stage_row_field to the new rowset's fields
    insert into bundle.blob (value)
    select f.value
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id::text = rr.row_id::text; -- TODO: should we be checking here to see if the staged value is different than the w.c. value??

    raise notice 'bundle: Committing stage_row_fields...';
    -- FIELDS: copy all the fields in stage_row_field to the new rowset's fields
    insert into bundle.rowset_row_field (rowset_row_id, field_id, value_hash)
    select rr.id, f.field_id, public.digest(value, 'sha256')
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id::text = rr.row_id::text;

    raise notice 'bundle: Creating the commit...';
    -- create the commit
    insert into bundle.commit (bundle_id, parent_id, rowset_id, message)
    values (_bundle_id, (select head_commit_id from bundle.bundle b where b.id=_bundle_id), new_rowset_id, message)
    returning id into new_commit_id;

    raise notice 'bundle: Updating bundle.head_commit_id...';
    -- point HEAD at new commit
    update bundle.bundle bundle set head_commit_id=new_commit_id, checkout_commit_id=new_commit_id where bundle.id=_bundle_id;

    raise notice 'bundle: Cleaning up after commit...';
    -- clear the stage
    delete from bundle.stage_row_added where bundle_id=_bundle_id;
    delete from bundle.stage_row_deleted where bundle_id=_bundle_id;
    delete from bundle.stage_field_changed where bundle_id=_bundle_id;

    end

$$ language plpgsql;



create or replace function head_rows (
    in bundle_name text,
    out commit_id uuid,
    out schema_name text,
    out relation_name text,
    out pk_column_name text,
    out pk_value text)
returns setof record
as $$
    select c.id,
        (row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    from bundle.bundle bundle
        join bundle.commit c on bundle.head_commit_id=c.id
        join bundle.rowset r on c.rowset_id = r.id
        join bundle.rowset_row rr on rr.rowset_id = r.id
    where bundle.name = bundle_name
$$ language sql;



create or replace function commit_log (in bundle_name text, out commit_id uuid, out message text, out count bigint)
returns setof record
as $$
select c.id as commit_id, c.message, count(*)
    from bundle.bundle b
        join bundle.commit c on c.bundle_id = b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id = r.id
    where b.name = bundle_name
    group by b.id, c.id, c.message
$$ language sql;



------------------------------------------------------------------------------
-- TRACKED ROW FUNCTIONS
------------------------------------------------------------------------------
-- track a row
create or replace function tracked_row_add (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns text
as $$
    -- TODO: check to see if this row is not tracked by some other bundle?
    insert into bundle.tracked_row_added (bundle_id, row_id) values (
        (select id from bundle.bundle where name=bundle_name),
        meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
    );
    select bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value;
$$ language sql;

create or replace function tracked_row_add (
    bundle_name text,
    row_id meta.row_id
) returns text
as $$
    select bundle.tracked_row_add(bundle_name, (
        row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    );
$$ language sql;



-- untrack a row
create or replace function untrack_row (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns text
as $$
    -- TODO: check to see if this row is not tracked by some other bundle?
    delete from bundle.tracked_row_added
        where bundle_id = (select id from bundle.bundle where name=bundle_name)
        and row_id = meta.row_id(schema_name, relation_name, pk_column_name, pk_value);
    select 'untracked: ' || bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value;
$$ language sql;

create or replace function untrack_row (
    bundle_name text,
    row_id meta.row_id
) returns text
as $$
    select bundle.untrack_row(bundle_name, (
        row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    );
$$ language sql;




-------------------------------------------------------------------------------
-- STAGE FUNCTIONS
------------------------------------------------------------------------------
-- stage an add
create or replace function stage_row_add (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns text
as $$
    begin
    insert into bundle.stage_row_added (bundle_id, row_id)
        select b.id, meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        from bundle.bundle b
        join bundle.tracked_row_added tra on tra.bundle_id=b.id
        where b.name=bundle_name and tra.row_id::text=meta.row_id(schema_name, relation_name, pk_column_name, pk_value)::text;

    if not FOUND then
        raise exception 'No such bundle, or this row is not yet tracked by this bundle.';
    end if;

    delete from bundle.tracked_row_added tra
        where tra.row_id::text=meta.row_id(schema_name, relation_name, pk_column_name, pk_value)::text;

    if not FOUND then
        raise exception 'Row could not be deleted from bundle.tracked_row_added';
    end if;
    return (bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value)::text;
    end;
$$
language plpgsql;

create or replace function stage_row_add (
    bundle_name text,
    row_id meta.row_id
) returns text
as $$
    select bundle.stage_row_add(bundle_name, (
        row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    );
$$ language sql;



-- unstage an add
create or replace function unstage_row_add (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns text
as $$
    begin
    delete from bundle.stage_row_added
        where bundle_id = (select id from bundle.bundle where name=bundle_name)
          and row_id=meta.row_id(schema_name, relation_name, pk_column_name, pk_value);

    if not FOUND then
        raise exception 'No such bundle or row.';
    end if;


    insert into bundle.tracked_row_added (bundle_id, row_id)
        values (
            (select id from bundle.bundle where name=bundle_name),
            meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
        );

    if not FOUND then
        raise exception 'No such bundle or row.';
    end if;
    return 'hi'; --- bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value;
    end
;
$$
language plpgsql;

create or replace function unstage_row_add (
    bundle_name text,
    row_id meta.row_id
) returns text
as $$
    select bundle.unstage_row_add(bundle_name, (
        row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    );
$$ language sql;




create or replace function stage_row_delete (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns text
as $$
    insert into bundle.stage_row_deleted (bundle_id, rowset_row_id)
    select
        bundle.id as bundle_id,
        rr.id as rowset_row_id
    from bundle.bundle bundle
        join bundle.commit c on bundle.head_commit_id = c.id
        join bundle.rowset r on c.rowset_id = r.id
        join bundle.rowset_row rr on rr.rowset_id = r.id
    where bundle.name = bundle_name
        and rr.row_id = meta.row_id(schema_name, relation_name, pk_column_name, pk_value);
    select bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value;
$$ language sql;

create or replace function stage_row_delete (
    bundle_name text,
    row_id meta.row_id
) returns text
as $$
    select bundle.stage_row_delete(bundle_name, (
        row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    );
$$ language sql;



create or replace function unstage_row_delete (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns text
as $$
    delete from bundle.stage_row_deleted srd
    using bundle.rowset_row rr
    where rr.id = srd.rowset_row_id
        and srd.bundle_id=(select id from bundle.bundle where name=bundle_name)
        and rr.row_id=meta.row_id(schema_name, relation_name, pk_column_name, pk_value);
    select bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value;
$$ language sql;

create or replace function unstage_row_delete (
    bundle_name text,
    row_id meta.row_id
) returns text
as $$
    select bundle.unstage_row_delete(bundle_name, (
        row_id::meta.schema_id).name,
        (row_id::meta.relation_id).name,
        ((row_id).pk_column_id).name,
        (row_id).pk_value
    );
$$ language sql;


/* all text interface */
create or replace function stage_field_change (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text,
    column_name text -- FIXME: somehow the webserver thinks it's a relation if column_name is present??
) returns text
as $$
    insert into bundle.stage_field_changed (bundle_id, field_id, new_value)
    values (
        (select id from bundle.bundle where name=bundle_name),
        meta.field_id (schema_name, relation_name, pk_column_name, pk_value, column_name),
        meta.field_id_literal_value(
            meta.field_id (schema_name, relation_name, pk_column_name, pk_value, column_name)
        )
    );
    select bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value || ' - ' || column_name;
$$ language sql;


/* all id interface */
create or replace function stage_field_change (
    bundle_id uuid,
    changed_field_id meta.field_id
) returns void
as $$
    insert into bundle.stage_field_changed (bundle_id, field_id, new_value)
    values (bundle_id, changed_field_id, meta.field_id_literal_value(changed_field_id)
    );
$$ language sql;




/* all text interface */
create or replace function unstage_field_change (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text,
    column_name text -- FIXME: somehow the webserver thinks it's a relation if column_name is present??
) returns text
as $$
    delete from bundle.stage_field_changed
        where field_id=
            meta.field_id (schema_name, relation_name, pk_column_name, pk_value, column_name);
    select bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value || ' - ' || column_name;
$$ language sql;


/* all id interface */
create or replace function unstage_field_change (
    bundle_id uuid,
    changed_field_id meta.field_id
) returns void
as $$
    delete from bundle.stage_field_changed where field_id=changed_field_id;
$$ language sql;


------------------------------------------------------------------------------
--
-- CHECKOUT FUNCTIONS
--
------------------------------------------------------------------------------

create type checkout_field as (name text, value text, type_name text);
create or replace function checkout_row (in row_id meta.row_id, in fields checkout_field[], in force_overwrite boolean) returns void as $$
    declare
        query_str text;
    begin
        -- raise log '------------ checkout_row % ----------',
        --    (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name ;
        set local search_path=something_that_must_not_be;

        if meta.row_exists(row_id) then
            -- raise log '---------------------- row % already exists.... overwriting.',
            -- (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name ;

            -- TODO: check to see if this row which is being merged is going to overwrite a row that is
            -- different from the head commit

            -- overwrite existing values with new values.
            /*
            execute 'update ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name)
                || ' set (' || array_to_string(fields.name,', ','NULL') || ')'
                || '   = (' || array_to_string(fields.value || '::'||fields.type_name, ', ','NULL') || ')'
                || ' where ' || (row_id.pk_column_id).name
                || '     = ' || row_id.pk_value;
            */
            query_str := 'update '
                || quote_ident((row_id::meta.schema_id).name)
                || '.'
                || quote_ident((row_id::meta.relation_id).name)
                || ' set (';

            for i in 1 .. array_upper(fields, 1)
            loop
                query_str := query_str || quote_ident(fields[i].name);

                if i < array_upper(fields, 1) then
                    query_str := query_str || ', ';
                end if;
            end loop;

            query_str := query_str
                || ') = (';

            for i in 1 .. array_upper(fields, 1)
            loop
                query_str := query_str
                || coalesce(
                    quote_literal(fields[i].value)
                        || '::text::'
                        || fields[i].type_name,
                    'NULL'
                );

                if i < array_upper(fields, 1) then
                    query_str := query_str || ', ';
                end if;
            end loop;

            query_str := query_str
                || ')'
                || ' where ' || quote_ident((row_id.pk_column_id).name)
                || '::text = ' || quote_literal(row_id.pk_value) || '::text'; -- cast them both to text instead of look up the column's type... maybe lazy?

            -- raise log 'query_str: %', query_str;

            execute query_str;

        else
            -- raise log '---------------------- row doesn''t exists.... INSERT:';
            query_str := 'insert into '
                || quote_ident((row_id::meta.schema_id).name)
                || '.'
                || quote_ident((row_id::meta.relation_id).name)
                || ' (';

            for i in 1 .. array_upper(fields, 1)
            loop
                query_str := query_str || quote_ident(fields[i].name);

                if i < array_upper(fields, 1) then
                    query_str := query_str || ', ';
                end if;
            end loop;

            query_str := query_str
                || ') values (';

            for i in 1 .. array_upper(fields, 1)
            loop
                query_str := query_str
                || coalesce(
                    quote_literal(fields[i].value)
                        || '::text::'
                        || fields[i].type_name,
                    'NULL'
                );

                if i < array_upper(fields, 1) then
                    query_str := query_str || ', ';
                end if;
            end loop;

            query_str := query_str  || ')';

            -- raise log 'query_str: %', query_str;

            execute query_str;
        end if;
    end;

$$ language plpgsql;



-- checkout can only be run by superusers because it disables triggers, as described here: http://blog.endpoint.com/2012/10/postgres-system-triggers-error.html
create or replace function checkout (in commit_id uuid, in comment text default null) returns void as $$
    declare
        commit_row record;
        bundle_name text;
        commit_message text;
        _commit_id uuid;
        commit_role text;
        commit_time timestamp;
    begin
        -- set local search_path=bundle,meta,public;
        set local search_path=something_that_must_not_be;
        /* TODO
        - check to see if this bundle is already checked out
        - if yes, check to see if it has any uncommitted changes, either new tracked rows or already
          tracked row changes
          - if it does, fail, unless checkout was passed a (new) HARD boolean of true
          - if it doesn't, delete the existing checkout (so we don't have dangling rows)
        - proceed.
        */

        select b.name, c.id, c.message, c.time, (c.role_id).name
        into bundle_name, _commit_id, commit_message, commit_time, commit_role
        from bundle.bundle b
            join bundle.commit c on c.bundle_id = b.id
        where c.id = commit_id;

        if _commit_id is null then
            raise exception 'bundle.checkout() commit with id % does not exist', commit_id;
        end if;

        raise notice 'bundle.checkout(): % / % @ % by %: "%"', bundle_name, commit_id, commit_time, commit_role, commit_message;
        -- insert the meta-rows in this commit to the database
        for commit_row in
            select
                rr.row_id,
                array_agg(
                    row(
                        ((f.field_id).column_id).name,
                        b.value,
                        col.type_name
                    )::bundle.checkout_field
                ) as fields_agg
            from bundle.commit c
                join bundle.rowset r on c.rowset_id=r.id
                join bundle.rowset_row rr on rr.rowset_id=r.id
                join bundle.rowset_row_field f on f.rowset_row_id=rr.id
                join bundle.blob b on f.value_hash=b.hash
                join meta.relation_column col on (f.field_id).column_id = col.id
            where c.id=commit_id
            and (rr.row_id::meta.schema_id).name = 'meta'
            group by rr.id
            -- add meta rows first, in sensible order
            order by
                case
                    when row_id::meta.relation_id = meta.relation_id('meta','schema') then 0
                    when row_id::meta.relation_id = meta.relation_id('meta','type_definition') then 1
                    when row_id::meta.relation_id = meta.relation_id('meta','table') then 2
                    when row_id::meta.relation_id = meta.relation_id('meta','column') then 3
                    when row_id::meta.relation_id = meta.relation_id('meta','sequence') then 4
                    when row_id::meta.relation_id = meta.relation_id('meta','constraint_check') then 4
                    when row_id::meta.relation_id = meta.relation_id('meta','constraint_unique') then 4
                    when row_id::meta.relation_id = meta.relation_id('meta','function_definition') then 5
                    else 100
                end asc /*,
                case
                when row_id::meta.relation_id = meta.relation_id('meta','column') then array_agg(quote_literal(f.value))->position::integer
                else 0
                end
                    */
        loop
            -- raise log '-- CHECKOUT meta row: % %',
            --    (commit_row.row_id).pk_column_id.relation_id.name,
            --    (commit_row.row_id).pk_column_id.relation_id.schema_id.name;-- , commit_row.fields_agg;
            perform bundle.checkout_row(commit_row.row_id, commit_row.fields_agg, true);
        end loop;




        -- raise notice '### DISABLING TRIGGERS % ###', commit_id;
        -- turn off constraints
        --
        -- TODO: stop doing this.  row keys must be analyzed so that they can be inserted in sensible order.
        -- in the case of circular dependencies we might still need to briefly and microscopically disable them.
        for commit_row in
            select distinct
                (rr.row_id).pk_column_id.relation_id.name as relation_name,
                (rr.row_id).pk_column_id.relation_id.schema_id.name as schema_name
            from bundle.commit c
                join bundle.rowset r on c.rowset_id=r.id
                join bundle.rowset_row rr on rr.rowset_id=r.id
                where c.id = commit_id
                and (rr.row_id::meta.schema_id).name != 'meta'
        loop
            -- raise log '-------------------------------- DISABLING TRIGGER on table %',
            --    quote_ident(commit_row.schema_name) || '.' || quote_ident(commit_row.relation_name);

            execute 'alter table '
                || quote_ident(commit_row.schema_name) || '.' || quote_ident(commit_row.relation_name)
                || ' disable trigger all';
        end loop;



        -- raise notice 'CHECKOUT DATA %', commit_id;
        -- insert the non-meta rows
        for commit_row in
            select
                rr.row_id,
                array_agg(
                    row(
                        ((f.field_id).column_id).name,
                        b.value,
                        col.type_name
                    )::bundle.checkout_field
                ) as fields_agg
            from bundle.commit c
                join bundle.rowset r on c.rowset_id=r.id
                join bundle.rowset_row rr on rr.rowset_id=r.id
                join bundle.rowset_row_field f on f.rowset_row_id=rr.id
                join bundle.blob b on f.value_hash=b.hash
                join meta.relation_column col on (f.field_id).column_id = col.id
            where c.id=commit_id
            and (rr.row_id::meta.schema_id).name != 'meta'
            group by rr.id
        loop
            -- raise log '------------------------------------------------------------------------CHECKOUT row: % %',
            --  (commit_row.row_id).pk_column_id.relation_id.name,
            --  (commit_row.row_id).pk_column_id.relation_id.schema_id.name;-- , commit_row.fields_agg;
            perform bundle.checkout_row(commit_row.row_id, commit_row.fields_agg, true);
        end loop;



        -- turn constraints back on
        -- raise notice '### ENABLING TRIGGERS % ###', commit_id;
        for commit_row in
            select distinct
                (rr.row_id).pk_column_id.relation_id.name as relation_name,
                (rr.row_id).pk_column_id.relation_id.schema_id.name as schema_name
            from bundle.commit c
                join bundle.rowset r on c.rowset_id=r.id
                join bundle.rowset_row rr on rr.rowset_id=r.id
                where c.id = commit_id
                and (rr.row_id::meta.schema_id).name != 'meta'
        loop
            execute 'alter table '
                || quote_ident(commit_row.schema_name) || '.' || quote_ident(commit_row.relation_name)
                || ' enable trigger all';
        end loop;

        -- point head_commit_id and checkout_commit_id to this commit
        update bundle.bundle set head_commit_id = commit_id where id in (select bundle_id from bundle.commit c where c.id = commit_id); -- TODO: now that checkout_commit_id exists, do we still do this?
        update bundle.bundle set checkout_commit_id = commit_id where id in (select bundle_id from bundle.commit c where c.id = commit_id);

        return;
    end;
$$ language plpgsql;


/*
 * This is used by the IDE for "revert".  row_id here is text because composite
 * types custom input functions, they all use record_in, so we can't pass it a
 * text string without explicitly casting it in the call, and endpoint always
 * passes text without casting.  So it just takes text and casts it internally.
 */

create or replace function checkout_row(_row_id text, commit_id uuid) returns void as $$
    declare
        commit_row record;
    begin
        set local search_path=something_that_must_not_be;
        for commit_row in
            select
                rr.row_id,
                array_agg(
                    row(
                        ((f.field_id).column_id).name,
                        b.value,
                        col.type_name
                    )::bundle.checkout_field
                ) as fields_agg
            from bundle.commit c
                join bundle.rowset r on c.rowset_id=r.id
                join bundle.rowset_row rr on rr.rowset_id=r.id
                join bundle.rowset_row_field f on f.rowset_row_id=rr.id
                join bundle.blob b on f.value_hash=b.hash
                join meta.relation_column col on (f.field_id).column_id = col.id
            where c.id=commit_id
                and rr.row_id = _row_id::meta.row_id
            group by rr.id
        loop
            perform bundle.checkout_row(commit_row.row_id, commit_row.fields_agg, true);
        end loop;
        return;
    end;
$$ language plpgsql;


------------------------------------------------------------------------------
-- MERGE
--
--
------------------------------------------------------------------------------


-- traverses the parent_ids of this commit, recursively returns them all
create or replace function commit_ancestry(_commit_id uuid) returns uuid[] as $$
    with recursive parent as (
        select c.id, c.parent_id from bundle.commit c where c.id=_commit_id
        union
        select c.id, c.parent_id from bundle.commit c join parent p on c.id = p.parent_id
    ) select array_agg(id) from parent
    -- ancestors only
    where id != _commit_id;
$$ language sql;




-- takes two commits on (presumably) different branches of the same bundle, returns their common ancestor or null
create or replace function commits_common_ancestor(commit1_id uuid, commit2_id uuid) returns uuid as $$
    declare
        same_branch_1 integer;
        same_branch_2 integer;
        ancestor uuid;
    begin
        if commit1_id = commit2_id then return null; end if;

        select count(*) from unnest(bundle.commit_ancestry(commit1_id)) c(id)
            where id = commit2_id into same_branch_1;
        select count(*) from unnest(bundle.commit_ancestry(commit2_id)) c(id)
            where id = commit1_id into same_branch_2;

        if same_branch_1 > 0 or same_branch_2 > 0 or same_branch_1 is null or same_branch_2 is null then
            -- raise notice 'Commits are on the same branch.';
            return null;
        end if;

        select c1.id from unnest(bundle.commit_ancestry(commit2_id)) c1(id)
            join unnest(bundle.commit_ancestry(commit2_id)) c2(id) on c1.id = c2.id limit 1
        into ancestor;

        return ancestor;
    end;
$$ language plpgsql;



-- fields changed between two commits, a kind of field-level diff
create type fields_changed_between_commits as (field_id meta.field_id, commit1_value_hash text, commit2_value_hash text);
create or replace function fields_changed_between_commits(commit1_id uuid, commit2_id uuid) returns setof fields_changed_between_commits as $$
    select commit1_field_id, commit1_value_hash, commit2_value_hash
    from (
        select rrf.field_id as commit1_field_id, rrf.value_hash as commit1_value_hash
            from bundle.commit c
                join bundle.rowset r on c.rowset_id = r.id
                join bundle.rowset_row rr on rr.rowset_id = r.id
                join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
                where c.id = commit1_id
    ) c1 join (
        select rrf.field_id as commit2_field_id, rrf.value_hash as commit2_value_hash
            from bundle.commit c
                join bundle.rowset r on c.rowset_id = r.id
                join bundle.rowset_row rr on rr.rowset_id = r.id
                join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
                where c.id = commit2_id
    ) c2 on commit1_field_id = commit2_field_id and commit1_value_hash != commit2_value_hash
$$ language sql;



-- rows in new_commit that are not in ancestor_commit
create or replace function rows_created_between_commits( new_commit_id uuid, ancestor_commit_id uuid ) returns setof meta.row_id as $$
    select rr.row_id
        from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
            where c.id = new_commit_id
    except
    select rr.row_id
        from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
            where c.id = ancestor_commit_id
$$ language sql;


-- checks to see if it structurally makes sense that this commit be merged.
-- does not check for changes in the working copy.
create or replace function commit_is_mergable(merge_commit_id uuid) returns boolean as $$
    declare
        _bundle_id uuid;
        bundle_name text;
        checkout_matches_head boolean;
        common_ancestor_id uuid;
        head_commit_id uuid;
    begin
        -- propagate some variables
        select b.head_commit_id = b.checkout_commit_id, b.head_commit_id, b.name, b.id
        from bundle.commit c
            join bundle.bundle b on c.bundle_id = b.id
        where c.id = merge_commit_id
        into checkout_matches_head, head_commit_id, bundle_name, _bundle_id;

        -- assert that the bundle is not in detached head mode
        if not checkout_matches_head then
            -- raise notice 'Merge not permitted when bundle.head_commit_id does not equal bundle.checkout_commit_id';
            return false;
        end if;

        -- assert that the two commits share a common ancestor
        select bundle.commits_common_ancestor(head_commit_id, merge_commit_id) into common_ancestor_id;
        if common_ancestor_id is null then
            -- raise notice 'Head commit and merge commit do not share a common ancestor.';
            return false;
        end if;

        -- assert that this commit is not already merged
        -- TODO


        return true;
    end;
$$ language plpgsql;



/*
Merge

- assert that this commit is mergable
    - head_commit_id equals checkout_commit_id (no detached head)
    - working copy does not contain any changes
    - the two commits share a common ancestor
- set bundle in merge mode: bundle.merge_commit_id is not null and references the commit being merged
- update and stage non-conflicting field changes
- update but do not stage conflicting field changes
- insert and stage new row creates
- delete and stage new row deletes
*/


create or replace function merge(merge_commit_id uuid) returns void as $$
    declare
        _bundle_id uuid;
        bundle_name text;
        checkout_matches_head boolean;
        conflicted_merge boolean := false;
        changes_count integer;
        common_ancestor_id uuid;
        head_commit_id uuid;
        f record;
        update_stmt text;
    begin
        -- propagate some variables
        select b.head_commit_id = b.checkout_commit_id, b.head_commit_id, b.name, b.id
        from bundle.commit c
            join bundle.bundle b on c.bundle_id = b.id
        where c.id = merge_commit_id
        into checkout_matches_head, head_commit_id, bundle_name, _bundle_id;

        -- assert that the bundle is not in detached head mode
        if not checkout_matches_head then
            raise exception 'Merge not permitted when bundle.head_commit_id does not equal bundle.checkout_commit_id';
        end if;

        -- assert that the working copy does not contain uncommitted changes (TODO: allow this?)
        select count(*) from bundle.head_db_stage_changed where bundle_id=_bundle_id into changes_count;
        if changes_count > 0 then
            raise exception 'Merge not permitted when this bundle has uncommitted changes';
        end if;

        -- assert that the two commits share a common ancestor
        select * from bundle.commits_common_ancestor(head_commit_id, merge_commit_id) into common_ancestor_id;
        if common_ancestor_id is null then
            raise exception 'Head commit and merge commit do not share a common ancestor.';
        end if;

        -- assert that this commit is not already merged
        -- TODO

        raise notice 'Merging commit % into head (%), with common ancestor commit %', merge_commit_id, head_commit_id, common_ancestor_id;

        /*
         *
         * safely mergable fields
         *
         */

        -- get fields that were changed on the merge commit branch, but not also changed on the head commit branch (aka non-conflicting)
        for f in
            select field_id from bundle.fields_changed_between_commits(merge_commit_id, common_ancestor_id)
            except
            select field_id from bundle.fields_changed_between_commits(head_commit_id, common_ancestor_id)
        loop
            -- update the working copy with each non-conflicting field change
            update_stmt := format('
                update %I.%I set %I = (
                    select b.value
                    from bundle.commit c
                        join bundle.rowset r on c.rowset_id = r.id
                        join bundle.rowset_row rr on rr.rowset_id = r.id
                        join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
                        join bundle.blob b on rrf.value_hash = b.hash
                    where c.id = %L
                        and rrf.field_id::text = %L
                ) where %I = %L',
                (((((f.field_id).row_id).pk_column_id).relation_id).schema_id).name,
                 ((((f.field_id).row_id).pk_column_id).relation_id).name,
                   ((f.field_id).column_id).name,
                merge_commit_id,
                   f.field_id::text,
                  (((f.field_id).row_id).pk_column_id).name,
                   ((f.field_id).row_id).pk_value
            );
            -- raise notice 'STMT: %', update_stmt;
            execute update_stmt;
            perform bundle.stage_field_change(_bundle_id, f.field_id);
        end loop;


        /*
         *
         * new rows
         *
         */

        for f in
            select bundle.rows_created_between_commits(merge_commit_id, common_ancestor_id) as row_id
        loop
            raise notice 'checking out new row %', f.row_id::text;
            perform bundle.checkout_row(f.row_id::text, merge_commit_id);
            perform bundle.tracked_row_add(bundle_name, f.row_id);
            perform bundle.stage_row_add(bundle_name, f.row_id);
        end loop;


        /*
         *
         * conflicting fields
         *
         * Change the working copy but do not stage them.  Merge conflicts are
         * unstaged.  There's probably something more elaborate we cna do here.
         *
         */

        for f in
            select field_id from bundle.fields_changed_between_commits(merge_commit_id, common_ancestor_id)
            intersect
            select field_id from bundle.fields_changed_between_commits(head_commit_id, common_ancestor_id)
        loop
            -- if this section has rows in it, this merge has conflicts
            conflicted_merge := true;

            -- update the working copy with each non-conflicting field change
            update_stmt := format('
                update %I.%I set %I = (
                    select b.value
                    from bundle.commit c
                        join bundle.rowset r on c.rowset_id = r.id
                        join bundle.rowset_row rr on rr.rowset_id = r.id
                        join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
                        join bundle.blob b on rrf.value_hash = b.hash
                    where c.id = %L
                        and rrf.field_id::text = %L
                ) where %I = %L',
                (((((f.field_id).row_id).pk_column_id).relation_id).schema_id).name,
                 ((((f.field_id).row_id).pk_column_id).relation_id).name,
                   ((f.field_id).column_id).name,
                merge_commit_id,
                   f.field_id::text,
                  (((f.field_id).row_id).pk_column_id).name,
                   ((f.field_id).row_id).pk_value
            );
            -- raise notice 'STMT: %', update_stmt;
            execute update_stmt;

            -- insert record of the conflicting field into bundle.merge_conflict
            update_stmt := format('
                insert into bundle.merge_conflict 
                    ( bundle_id, rowset_row_field_id, field_id, conflict_value )
                select _bundle_id, rrf.id, rrf.field_id, b.value
                from bundle.commit c
                    join bundle.rowset r on c.rowset_id = r.id
                    join bundle.rowset_row rr on rr.rowset_id = r.id
                    join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
                    join bundle.blob b on rrf.value_hash = b.hash
                where c.id = %L
                    and rrf.field_id::text = %L',
                merge_commit_id, f.field_id::text
            );
            -- raise notice 'STMT: %', update_stmt;
            execute update_stmt;

        end loop;

        /*
        TODO:
        - row deletes
        */

        -- set merge state
        update bundle.bundle set merge_commit_id = merge_commit_id where id=_bundle_id;

    end;
$$ language plpgsql;

create or replace function merge_finish(_bundle_id uuid) returns void as $$
    begin
    end;
$$ language plpgsql;


create or replace function merge_cancel(_bundle_id uuid) returns void as $$
    begin
        -- assert that bundle is in merge mode
        -- assert that head_commit_id
    end;
$$ language plpgsql;



------------------------------------------------------------------------------
-- BUNDLE COPY
------------------------------------------------------------------------------
/*
create function bundle.bundle_copy(_bundle_id uuid, new_name text) returns uuid as $$
    insert into bundle.bundle select * from bundle.bundle where id=_bundle_id;
    insert into bundle.rowset select * from bundle.rowset r join commit c on c.rowset_id=r.id where c.bundle_id = _bundle_id;
    insert into bundle.commit select * from bundle.commit where bundle_id = _bundle_id;

$$ language sql;
*/

------------------------------------------------------------------------------
-- BUNDLE CREATE / DELETE
------------------------------------------------------------------------------

create or replace function bundle.bundle_create (name text) returns uuid as $$
declare
    bundle_id uuid;
begin
    insert into bundle.bundle (name) values (name) returning id into bundle_id;
    -- TODO: should we make an initial commit and rowset for a newly created bundle?  if not, when checkout_commit_id is null, does that mean it is not checked out, or it is new, or both?  both is wrong.
    -- insert into bundle.commit
    return bundle_id;
end;
$$ language plpgsql;

create or replace function bundle.bundle_delete (in _bundle_id uuid) returns void as $$
    -- TODO: delete blobs
    delete from bundle.rowset r where r.id in (select c.rowset_id from bundle.commit c join bundle.bundle b on c.bundle_id = b.id where b.id = _bundle_id);
    delete from bundle.bundle where id = _bundle_id;
$$ language sql;

------------------------------------------------------------------------------
-- COMMIT DELETE
------------------------------------------------------------------------------

create or replace function bundle.commit_delete(in _commit_id uuid) returns void as $$
    -- TODO: delete blobs
    -- TODO: delete commits in order?
    delete from bundle.rowset r where r.id in (select c.rowset_id from bundle.commit c where c.id = _commit_id);
    delete from bundle.commit c where c.id = _commit_id;
$$ language sql;


------------------------------------------------------------------------------
-- CHECKOUT DELETE
------------------------------------------------------------------------------

/*
 * deletes the rows in the database that are tracked by the specified commit
 * (usually bundle.head_commit_id).
 * TODO: this could be optimized to one delete per relation
 */
create or replace function bundle.checkout_delete(in _bundle_id uuid, in _commit_id uuid) returns void as $$
declare
        temprow record;
begin
    for temprow in
        select rr.* from bundle.bundle b
            join bundle.commit c on c.bundle_id = b.id
            join bundle.rowset r on r.id = c.rowset_id
            join bundle.rowset_row rr on rr.rowset_id = r.id
        where b.id = _bundle_id and c.id = _commit_id
        loop
        execute format ('delete from %I.%I where %I = %L',
            ((((temprow.row_id).pk_column_id).relation_id).schema_id).name,
            (((temprow.row_id).pk_column_id).relation_id).name,
            ((temprow.row_id).pk_column_id).name,
            (temprow.row_id).pk_value);
    end loop;

    update bundle.bundle set checkout_commit_id = null where id = _bundle_id;
end;
$$ language plpgsql;

------------------------------------------------------------------------------
-- STATUS FUNCTIONS
------------------------------------------------------------------------------

create or replace function bundle.status()
returns setof text as $$
    select b.name || ' - '
        || hds.change_type || ' - '
        || hds.row_id::text
    from bundle.bundle b
        join bundle.head_db_stage_changed hds on hds.bundle_id = b.id
    order by b.name, hds.row_id::text;
$$ language sql;



------------------------------------------------------------------------------
-- ROW HISTORY
------------------------------------------------------------------------------


create type row_history_return_type as (
    field_hashes jsonb,
    commit_id uuid,
    commit_message text,
    commit_parent_id uuid,
    time timestamp,
    bundle_id uuid,
    bundle_name text
);

-- create or replace function bundle.row_history(_row_id meta.row_id) returns setof record as $$
-- broken out into fields because composite types hate endpoint
-- this is wrong.  not traversing the commit tree, just using time
create or replace function bundle.row_history(schema_name text, relation_name text, pk_column_name text, pk_value text) returns setof row_history_return_type as $$
    select field_hashes, commit_id, commit_message, commit_parent_id, time, bundle_id, bundle_name
    from (
        with commits as (
            select jsonb_object_agg(((rrf.field_id).column_id).name, rrf.value_hash::text) as field_hashes, c.id as commit_id, c.message as commit_message, c.parent_id as commit_parent_id, c.time, b.id as bundle_id, b.name as bundle_name
            from bundle.rowset_row rr
                join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
                join bundle.rowset r on rr.rowset_id = r.id
                join bundle.commit c on c.rowset_id = r.id
                join bundle.bundle b on c.bundle_id = b.id
            where row_id::text = meta.row_id(schema_name, relation_name, pk_column_name, pk_value)::text
            group by rr.id, c.id, c.message, b.id, b.name, c.parent_id, c.time
            order by c.time
        )
        select commits.*, lag(field_hashes, 1, null) over (order by commits.time) as previous_commit_hashes
        from commits
    ) commits_with_previous
    where field_hashes != previous_commit_hashes or previous_commit_hashes is null;
$$ language sql;


-- this is mostly ganked from head_db_stage for performance reasons, seemed view was acting as an optimization barrier.  audit.
create or replace function bundle.row_status(schema_name text, relation_name text, pk_column_name text, pk_value text) returns bundle.head_db_stage as $$
select
    *,
    meta.row_exists(row_id) as row_exists,
    case
        when change_type = 'same' then null
        when change_type = 'deleted' then (stage_row_id is null)
        when change_type = 'added' then true
        when change_type = 'modified' then null
        when change_type = 'tracked' then false
    end as staged,

    (head_row_id is not null) in_head
from (
    select
        coalesce (hcr.bundle_id, sr.bundle_id) as bundle_id,
        hcr.commit_id,
        coalesce (hcr.row_id, sr.row_id) as row_id,
        hcr.row_id as head_row_id,
        sr.row_id as stage_row_id,

        -- change_type
        case
            when sr.row_id is null then 'deleted'
            when hcr.row_id is null then  'added'
            when
                array_remove(array_agg(ofc.field_id), null) != '{}'
                or array_remove(array_agg(sfc.field_id), null) != '{}' then  'modified'
            when meta.row_exists(sr.row_id) = false then 'deleted'
            else 'same'
        end as change_type,

        -- offstage changes
        array_remove(array_agg(ofc.field_id), null) as offstage_field_changes,
        array_agg(ofc.old_value) as offstage_field_changes_old_vals,
        array_agg(ofc.new_value) as offstage_field_changes_new_vals,
        -- staged changes
        array_remove(array_agg(sfc.field_id), null) as stage_field_changes,
        array_agg(ofc.old_value) as stage_field_changes_old_vals,
        array_agg(sfc.new_value) as stage_field_changes_new_vals

    from (
        -- this is view head_commit_row, just ganked in with row_id filter
        select b.id AS bundle_id,
            c.id as commit_id,
            rr.row_id
        from bundle.bundle b
            join bundle.commit c on b.head_commit_id = c.id
            join bundle.rowset r on r.id = c.rowset_id
            join bundle.rowset_row rr on rr.rowset_id = r.id
        where row_id::text = meta.row_id(schema_name, relation_name, pk_column_name, pk_value)::text
    ) hcr
    full outer join bundle.stage_row sr on hcr.row_id::text=sr.row_id::text
    left join bundle.stage_field_changed sfc on (sfc.field_id).row_id::text=hcr.row_id::text
    left join bundle.offstage_field_changed ofc on (ofc.field_id).row_id::text=hcr.row_id::text
    group by hcr.bundle_id, hcr.commit_id, hcr.row_id, sr.bundle_id, sr.row_id, (sfc.field_id).row_id, (ofc.field_id).row_id

    union

    select tra.bundle_id, null, tra.row_id, null, null, 'tracked', null, null, null, null, null, null
    from bundle.tracked_row_added tra

) c
order by
case c.change_type
    when 'tracked' then 0
    when 'deleted' then 1
    when 'modified' then 2
    when 'same' then 3
    when 'added' then 4
end, row_id;

$$ language sql;
/*******************************************************************************
 * Bundle Utilities
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

-- export
-- saves bundle contents to filesystem.  overwrites if it is already there.
-- directory must already exist and be writable by postgres user.

create or replace function bundle.bundle_export_csv(bundle_name text, directory text)
 returns void
 language plpgsql
as $$
begin
    -- check if bundle exists
    if not exists( select true from bundle.bundle b where b.name = bundle_name) then
        raise exception 'No such bundle with name %', bundle_name;
    end if;

    -- check that bundle has commits
    -- TODO: is this really a problem?
    if not exists( select true from bundle.bundle b join bundle.commit c on c.bundle_id = b.id where b.name = bundle_name) then
        raise exception 'No commits found in bundle %', bundle_name;
    end if;


    -- copy bundle contents to csv files
    -- checkout_commit_id is set to NULL explicitly, because it is only relevant to this current database
    execute format('copy (select b.id, b.name, b.head_commit_id, NULL /* checkout_commit_id */ from bundle.bundle b
        where b.name=''%s'') to ''%s/bundle.csv''', bundle_name, directory);

    execute format('copy (select distinct c.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        where b.name=%L) to ''%s/commit.csv''', bundle_name, directory);

    execute format('copy (select distinct r.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        where b.name=%L order by r.id) to ''%s/rowset.csv''', bundle_name, directory);

    execute format('copy (select distinct rr.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
        where b.name=%L order by rr.id) to ''%s/rowset_row.csv''', bundle_name, directory);

    execute format('copy (select distinct rrf.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id
        where b.name=%L order by rrf.id) to ''%s/rowset_row_field.csv''', bundle_name, directory);

    execute format('copy (select distinct blob.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id
        join bundle.blob on rrf.value_hash=blob.hash
        where b.name=%L order by blob.hash) to ''%s/blob.csv''', bundle_name, directory);
end
$$;


-- import
-- import a bundle from a csv export (created by above).

create or replace function bundle.bundle_import_csv(directory text)
 returns uuid
 language plpgsql
as $$
declare
    bundle_id uuid;
    bundle_name text;
begin
    -- triggers must be disabled because bundle and commit have circular
    -- dependencies, and blob
    execute format('alter table bundle.bundle disable trigger all');
    execute format('alter table bundle.commit disable trigger all');
    execute format('copy bundle.bundle from ''%s/bundle.csv''', directory);
    execute format('copy bundle.commit from ''%s/commit.csv''', directory);

    -- copy the commit data
    execute format('copy bundle.rowset from ''%s/rowset.csv''', directory);
    execute format('copy bundle.rowset_row from ''%s/rowset_row.csv''', directory);
    execute format('copy bundle.blob from ''%s/blob.csv''', directory);
    execute format('copy bundle.rowset_row_field from ''%s/rowset_row_field.csv''', directory);
    execute format('alter table bundle.bundle enable trigger all');
    execute format('alter table bundle.commit enable trigger all');

    -- set the origin for this bundle
    execute format('create temporary table origin_temp(id uuid, name text, head_commit_id uuid, checkout_commit_id uuid) on commit drop');
    execute format('copy origin_temp from ''%s/bundle.csv''', directory);
    execute format('insert into bundle.bundle_csv(directory, bundle_id) select %L, id from origin_temp', directory);

    -- make sure that checkout_commit_is null
    select name from origin_temp into bundle_name;
    update bundle.bundle set checkout_commit_id = NULL where name = bundle_name;

    -- return bundle.id
    select id from origin_temp into bundle_id;
    return bundle_id;
end
$$;

-- garbage_collect()
-- deletes any blobs that are not referenced by any rowset_row_fields

create or replace function bundle.garbage_collect() returns void
as $$
    delete from bundle.blob where hash is null;
    delete from bundle.rowset_row_field where value_hash is null;
    delete from bundle.blob where hash not in (select value_hash from bundle.rowset_row_field);
    delete from bundle.rowset where id not in (select rowset_id from bundle.commit);
$$ language sql;




create type search_method as enum ('like','ilike','regex', 'iregex');
create type search_scope as enum ('head','stage','tracked','changed','history');

create or replace function bundle.search(
    term text,
    search_method search_method,
    scope search_scope,
    _bundle_id uuid default null)
returns table (
    bundle_id uuid,
    bundle_name text,
    commit_ids uuid[],

    row_schema_name text,
    row_relation_name text,
    row_pk_column_name text,
    row_pk_value text,
    field_name text,

    messages text[],
    value_hash text,
    value text
) as $$
declare
    search_stmt text;
begin
    search_stmt := 'select
        b.id as bundle_id,
        b.name,
        array_agg(c.id) as commit_ids,

        (rrf.field_id::meta.schema_id).name as row_schema_name,
        (rrf.field_id::meta.relation_id).name as row_relation_name,
        (((rrf.field_id).row_id).pk_column_id).name as row_pk_column_name,
        ((rrf.field_id).row_id).pk_value as row_pk_value,
        ((rrf.field_id).column_id).name as field_name,

        array_agg(c.message),
        rrf.value_hash,
        value
        from bundle.bundle b
            join bundle.commit c on c.bundle_id=b.id ';
    case scope
        when 'head' then
        search_stmt := search_stmt || '
            join bundle.head_commit_row hcr on hcr.commit_id = c.id
            join bundle.head_commit_field rrf on rrf.row_id = hcr.row_id
            join bundle.blob bb on rrf.value_hash = bb.hash ';
        when 'stage' then
        search_stmt := search_stmt || '
            join bundle.stage_row sr on sr.bundle_id = b.id
            join bundle.stage_row_field rrf on rrf.stage_row_id::text = sr.row_id::text '; --TODO: holy cown this cast to text speeds things up 70x
        when 'history' then
        search_stmt := search_stmt || '
            join bundle.rowset r on c.rowset_id=r.id
            join bundle.rowset_row rr on rr.rowset_id=r.id
            join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
            join bundle.blob bb on rrf.value_hash = bb.hash ';
        else raise exception 'Not Yet Implemented';
    end case;

    case search_method
        when 'like' then
        search_stmt := search_stmt || ' where value like ''%%%s%%'' ';
        when 'ilike' then
        search_stmt := search_stmt || ' where value ilike ''%%%s%%'' ';
        when 'regex' then
        search_stmt := search_stmt || ' where value ~ ''%s'' ';
        when 'iregex' then
        search_stmt := search_stmt || ' where value ~* ''%s'' ';
    end case;

    if _bundle_id is not null then
         search_stmt := search_stmt || format(' and b.id=%L', _bundle_id);
    end if;

    search_stmt := search_stmt || '
        group by rrf.field_id, b.id, b.name, rrf.value_hash, value';

     -- TODO: escape single quotes
    search_stmt := format( search_stmt, term );
    raise notice 'search_stmt: %', search_stmt;
    return query execute search_stmt;
end;
$$ language plpgsql;
/*******************************************************************************
 * Bundle Remotes
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/*******************************************************************************
*
* BUNDLE REMOTES -- postgres_fdw
*
* This version uses the postgres_fdw foreign data wrapper to mount remote
* databases via a normal postgresql connection.  It uses IMPORT FOREIGN SCHEMA
* to import the bundle schema, and then provides various comparison functions
* for push, pull and merge.
*
*******************************************************************************/



-- remote_mount()
--
-- setup a foreign server to a remote, and import it's bundle schema


create or replace function bundle.remote_mount (
    foreign_server_name text,
    schema_name text,
    connection_string text,
    username text,
    password text
)
returns boolean as
$$
declare
    user_map_options text;
begin

    /*
    TODO: 
    there isn't a nice way to do this without writing a whole connection string parser.
    for unix socket connections, you need to not specify a password, but that means we have
    to detect whether or not the specified host is a unix socket.
	https://github.com/aquametalabs/aquameta/issues/224#issuecomment-750311286
    */

    execute format(
        'create server %I
            foreign data wrapper postgres_fdw
            options (%s, fetch_size ''1000'', extensions %L)',
        foreign_server_name, connection_string, 'uuid-ossp'
    );

    user_map_options := format('user %L', username);
    if password is not null then
        user_map_options := user_map_options || format(', password %L', password);
    end if;

    execute format(
        'create user mapping for public server %I options (%s)',
        foreign_server_name, user_map_options
    );

    execute format(
        'create schema %I',
        schema_name
    );

    execute format('
        import foreign schema bundle limit to
            (bundle, commit, rowset, rowset_row, rowset_row_field, blob, _bundle_blob)
        from server %I into %I options (import_default %L)',
        foreign_server_name, schema_name, 'true'
    );

    return true;
end;
$$ language plpgsql;


create or replace function bundle.remote_mount( remote_database_id uuid ) returns boolean as $$
begin
    execute format ('select bundle.remote_mount(
        foreign_server_name,
        schema_name,
        connection_string,
        username,
        password)
    from bundle.remote_database
    where id = %L', remote_database_id);
    return true;
exception
    when others then return false;
end;

$$ language plpgsql;



create or replace function bundle.remote_unmount( remote_database_id uuid ) returns boolean as $$
declare
    _schema_name text;
    _foreign_server_name text;
begin
    select foreign_server_name, schema_name from bundle.remote_database where id = remote_database_id into _foreign_server_name, _schema_name;
    execute format('drop server if exists %I cascade', _foreign_server_name);
    execute format('drop schema f exists %I', _schema_name);
    return true;
end;
$$ language plpgsql;



create or replace function bundle.remote_is_mounted( remote_database_id uuid ) returns boolean as $$
declare
    _schema_name text;
    _foreign_server_name text;
    has_schema boolean;
    has_server boolean;
    has_tables boolean;
begin
    select schema_name, foreign_server_name from bundle.remote_database where id = remote_database_id into _schema_name, _foreign_server_name;
    execute format ('select (count(*) = 1) from meta.schema where name = %L', _schema_name) into has_schema;
    execute format ('select (count(*) = 1) from meta.foreign_server where name = %L', _foreign_server_name) into has_server;
    execute format ('select (count(*) = 7) from meta.foreign_table where schema_name = %L and name in (''bundle'',''commit'',''rowset'',''rowset_row'',''rowset_row_field'',''blob'',''_bundle_blob'')', _schema_name) into has_tables;
    return has_schema and has_server and has_tables;
end;
$$ language plpgsql;



create or replace function bundle.remote_is_online( remote_database_id uuid ) returns boolean as $$
declare
    _schema_name text;
    _foreign_server_name text;
begin
    select schema_name, foreign_server_name from bundle.remote_database where id = remote_database_id into _schema_name, _foreign_server_name;

    -- xocolatl | you could do something like  create foreign table pg_temp.test(i int) server s options (table '(select 1)'); 
    execute format ('select count(*) from %I.bundle where name = ''connection_test''', _schema_name);
    return true;
exception
    when others then
        return false;
end
$$ language plpgsql;



-- bundle_commits_array( bundle_relation_id )
--
-- contains a row for each bundle in a database, containing the "commit" row of each commit in the bundle

create or replace function bundle.bundle_commits_array( bundle_relation_id meta.relation_id, bundle_id uuid default null )
returns table (
    id uuid, name text, head_commit_id uuid, commits json
)
as $$
declare
    bundle_filter_stmt text;
begin
    bundle_filter_stmt := '';
    if bundle_id is not null then
        bundle_filter_stmt := format('where bundle_id = %L', bundle_id);
    end if;
    return query execute format('
        select
            b.id,
            b.name,
            b.head_commit_id,
            json_agg( json_build_object(
                ''id'', c.id,
                ''bundle_id'', c.bundle_id,
                ''message'', c.message,
                ''time'', c.time,
                ''parent_id'', c.parent_id
            )) as commits
        from %I.%I b
            join %I.commit c on c.bundle_id=b.id
        %s
        group by b.id, b.name, b.head_commit_id
    ',
        (bundle_relation_id::meta.schema_id).name,
        bundle_relation_id.name,
        (bundle_relation_id::meta.schema_id).name,
        bundle_filter_stmt
    );
end;
$$ language plpgsql;



-- diff_bundle_bundle_commits( bundle_table_a, bundle_table_b )
--
-- outer-joins the bundle tables of databases, one row per bundle.  the row also contains a json aggregate of every commit in that bundle.

create or replace function bundle.remote_commits_diff(
    remote_database_id uuid,
    bundle_id uuid default null
) returns table (
    a_bundle_id uuid, a_name text, a_head_commit_id uuid, a_commits json,
    b_bundle_id uuid, b_name text, b_head_commit_id uuid, b_commits json
)
as $$
declare
    remote_schema_name text;
    remote_connection_string text;
begin
    select schema_name, connection_string from bundle.remote_database
        where id = remote_database_id
	into remote_schema_name, remote_connection_string;

    return query execute format('
        select a.id as a_bundle_id, a.name as a_name, a.head_commit_id as a_head_commit_id, a.commits as a_commits,
            b.id as b_bundle_id, b.name as b_name, b.head_commit_id as b_head_commit_id, b.commits as b_commits
        from bundle.bundle_commits_array( meta.relation_id(''bundle'',''bundle''), %L ) a
            full outer join bundle.bundle_commits_array( meta.relation_id (%L,''bundle''), %L) b
                on a.id = b.id
        ', bundle_id, remote_schema_name, bundle_id );
end;
$$ language plpgsql;


/*

create or replace function bundle.remote_commits_ahead( remote_database_id uuid, bundle_id uuid) 
returns bundle.commit
as $$
declare
    source_schema_name text;
    source_connection_string text;
    source_bundle_name text;
    source_bundle_id uuid;
begin
    select schema_name, connection_string from bundle.remote_database
        where id = remote_database_id
	into source_schema_name, source_connection_string;
    -- source
    execute format ('select b.name, b.id from %1$I.bundle b where id=%2$L', source_schema_name, bundle_id) into source_bundle_name, source_bundle_id;
    raise notice 'Cloning bundle % (%) from %...', source_bundle_name, source_bundle_id, source_connection_string;

    execute format ('select c.* from %1$I.bundle b join %1$I.commit c on c.bundle_id = b.id where b.id = %2$L and c.id not in (select c.id from bundle.commit c)',
        remote

$$ language sql;
*/



-- remote_pull_bundle()
--
-- copy a repository from one bundle schema (typically a remote) to another (typically a local one)
create or replace function bundle.remote_pull_bundle( remote_database_id uuid, bundle_id uuid ) -- source_schema_name text, dest_schema_name text )
returns boolean as $$
declare
    source_schema_name text;
    source_bundle_name text;
    source_bundle_id uuid;
    source_connection_string text;
begin
    select schema_name, connection_string from bundle.remote_database
        where id = remote_database_id
	into source_schema_name, source_connection_string;

    -- source
    execute format ('select b.name, b.id from %1$I.bundle b where id=%2$L', source_schema_name, bundle_id) into source_bundle_name, source_bundle_id;
    raise notice 'Cloning bundle % (%) from %...', source_bundle_name, source_bundle_id, source_connection_string;

    --------------- transfer --------------
    -- rowset
    raise notice '...rowset';
    execute format ('insert into bundle.rowset
        select r.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- rowset_row
    raise notice '...rowset_row';
    execute format ('
        insert into bundle.rowset_row
        select rr.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- blob
    raise notice '...blob';
    execute format ('
        insert into bundle.blob
        select bb.hash, bb.value from %1$I._bundle_blob bb
        where bb.bundle_id=%2$L', source_schema_name, bundle_id);

    -- rowset_row_field
    raise notice '...rowset_row_field';
    execute format ('
        insert into bundle.rowset_row_field
        select f.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- bundle
    raise notice '...bundle';
    execute format ('insert into bundle.bundle (id, name)
        select b.id, b.name from %1$I.bundle b
        where b.id=%2$L', source_schema_name, bundle_id);

    -- commit
    raise notice '...commit';
    execute format ('
        insert into bundle.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- bundle.head_commit_id
    -- TODO: audit this in light of checkout_commit_id
    execute format ('update bundle.bundle
        set head_commit_id = (
            select b.head_commit_id
            from %1$I.bundle b
            where b.id=%2$L
    ) where id=%2$L', source_schema_name, bundle_id);

    execute format ('insert into bundle.bundle_remote_database (bundle_id, remote_database_id) values( %L, %L )', bundle_id, remote_database_id);

    return true;
end;
$$
language plpgsql;



create or replace function bundle.remote_push_bundle( remote_database_id uuid, bundle_id uuid ) -- source_schema_name text, dest_schema_name text )
returns boolean as $$
declare
    remote_schema_name text;
    remote_connection_string text;
    source_bundle_name text;
begin

    -- these used to be arguments, but now they're not.  we need to track remote_database_id explicitly.
    select schema_name, connection_string from bundle.remote_database
        where id = remote_database_id
	into remote_schema_name, remote_connection_string;

    select name from bundle.bundle where id = bundle_id
    into source_bundle_name;

    raise notice 'Pushing bundle % (%) from %...', source_bundle_name, bundle_id, remote_connection_string;
    raise notice '...bundle';
    execute format ('insert into %1$I.bundle (id,name)
        select b.id, b.name from bundle.bundle b
        where b.id=%2$L', remote_schema_name, bundle_id);

    perform bundle.remote_push_commits( remote_database_id, bundle_id );

    raise notice '...updating bundle.head_commit_id';
    execute format ('update bundle.bundle b
        set head_commit_id=(select head_commit_id from %1$I.bundle b where b.id=%2$L)
        where b.id=%2$L', remote_schema_name, bundle_id);
    return true;
end;
$$
language plpgsql;



/*
 * bundle.remote_pull_commits
 *
 * transfer from remote all the commits that are not in the local repository for specified bundle
 *
 */

create or replace function bundle.remote_pull_commits( remote_database_id uuid, bundle_id uuid )
returns boolean as $$
declare
	dest_schema_name text;
	source_connection_string text;
	source_schema_name text;
	source_bundle_name text;
	source_bundle_id uuid;
	new_commit_ids text;
    new_commits_count integer;
begin
    -- these used to be arguments, but now they're not.  we need to track remote_database_id explicitly.
    select schema_name, connection_string from bundle.remote_database
        where id = remote_database_id
	into source_schema_name, source_connection_string;

    -- dest_schema_name
    select 'bundle' into dest_schema_name;

    -- source
    execute format ('select b.name, b.id from %1$I.bundle b where id=%2$L', source_schema_name, bundle_id) into source_bundle_name, source_bundle_id;

    -- new_commit_ids - commits in the bundle
    execute format ('
        select count(*), string_agg(quote_literal(c.id::text),'','')
            from %1$I.commit c
            join %1$I.bundle b on c.bundle_id = b.id
            where b.id = %2$L
                and c.id not in (select id from bundle.commit where bundle_id = %2$L)
        ', source_schema_name, bundle_id)
        into new_commits_count, new_commit_ids;

        if new_commits_count = 0 then
            new_commit_ids = quote_literal(false);
        end if;

    -- notice
    raise notice 'Pulling % new commits for % (%) from %...',
        new_commits_count, source_bundle_name, source_bundle_id, source_connection_string;

    -- raise notice 'new_commit_ids: %', new_commit_ids;

    -- rowset
    raise notice '...rowset';
    execute format ('insert into %2$I.rowset
        select r.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
        where c.bundle_id=%3$L
            and c.id in (%4$s)',
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    -- rowset_row
    raise notice '...rowset_row';
    execute format ('
        insert into %2$I.rowset_row
        select rr.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%3$L
            and c.id in (%4$s)',
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    -- blob TODO: stop transferring all the blobs for just a pull
    raise notice '...blob';
    execute format ('
        insert into %2$I.blob
        select bb.hash, bb.value
            from %1$I._bundle_blob bb
            where bb.bundle_id=%3$L',
        source_schema_name, dest_schema_name, bundle_id);

    -- rowset_row_field
    raise notice '...rowset_row_field';
    execute format ('
        insert into %2$I.rowset_row_field
        select f.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%3$L
            and c.id in (%4$s)',
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    -- commit
    raise notice '...commit';
    execute format ('insert into %2$I.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%3$L
            and c.id in (%4$s)
        order by c.time asc', -- TODO: we're just sorting by time here which is a hack.  build the parent_id tree recursively.
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    return true;

end;
$$ language plpgsql;



/*
 * bundle.remote_push_commits()
 *
 * transfer from remote all the commits that are not in the local repository for specified bundle
 *
 */

create or replace function bundle.remote_push_commits( remote_database_id uuid, bundle_id uuid )
returns boolean as $$
declare
	dest_schema_name text;
	remote_connection_string text;
	remote_schema_name text;
	remote_bundle_name text;
	remote_bundle_id uuid;
	new_commit_ids text;
    new_commits_count integer;
begin
    -- remote_schema_name, connection_string
    select schema_name, connection_string from bundle.remote_database
        where id = remote_database_id
	into remote_schema_name, remote_connection_string;

    -- dest_schema_name
    select 'bundle' into dest_schema_name;

    -- remote
    execute format ('select b.name, b.id from bundle.bundle b where id=%1$L', bundle_id) into remote_bundle_name, remote_bundle_id;

    -- new_commit_ids - commits in the bundle
    execute format ('
        select count(*), string_agg(quote_literal(c.id::text),'','')
            from bundle.commit c
            join bundle.bundle b on c.bundle_id = b.id
            where b.id = %2$L
                and c.id not in (select id from %1$I.commit where bundle_id = %2$L)
            group by c.time
            order by c.time asc
        ', remote_schema_name, bundle_id)
        into new_commits_count, new_commit_ids;

        if new_commits_count = 0 then
            new_commit_ids = quote_literal(false);
        end if;


    -- notice
    raise notice 'Pushing % new commits for % (%) from %...',
        new_commits_count, remote_bundle_name, remote_bundle_id, remote_connection_string;

    -- raise notice 'new_commit_ids: %', new_commit_ids;

    -- rowset
    raise notice '...rowset';
    execute format ('insert into %1$I.rowset
        select r.* from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
        where c.bundle_id=%2$L
            and c.id in (%3$s)',
        remote_schema_name, bundle_id, new_commit_ids);

    -- rowset_row
    raise notice '...rowset_row';
    execute format ('
        insert into %1$I.rowset_row
        select rr.* from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%2$L
            and c.id in (%3$s)',
        remote_schema_name, bundle_id, new_commit_ids);

    -- blob TODO: stop transferring all the blobs for just a pull
    raise notice '...blob';
    execute format ('
        insert into %1$I.blob
        select distinct bb.hash, bb.value from bundle.bundle b
            join bundle.commit c on c.bundle_id = b.id
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
            join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
            join bundle.blob bb on rrf.value_hash = bb.hash
        where b.id=%2$L
            and c.id in (%3$s)',
            -- and bb.hash not in (select all the hashes that aren't new.... optimization)
        remote_schema_name, bundle_id, new_commit_ids);

    -- rowset_row_field
    raise notice '...rowset_row_field';
    execute format ('
        insert into %1$I.rowset_row_field
        select f.* from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
            join bundle.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%2$L
            and c.id in (%3$s)',
        remote_schema_name, bundle_id, new_commit_ids);

    -- commit
    raise notice '...commit';
    execute format ('insert into %1$I.commit
        select c.* from bundle.commit c
        where c.bundle_id=%2$L
            and c.id in (%3$s)
        order by c.time asc', -- TODO: we're just sorting by time here which is a hack.  build the parent_id tree recursively.
        remote_schema_name, bundle_id, new_commit_ids);

    return true;
end;
$$ language plpgsql;



/* optimization view for postgres_fdw */

create or replace view _bundle_blob as
select distinct on (b.id, bb.hash) b.id as bundle_id, bb.* from bundle.bundle b
    join bundle.commit c on c.bundle_id = b.id
    join bundle.rowset r on c.rowset_id = r.id
    join bundle.rowset_row rr on rr.rowset_id = r.id
    join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
    join bundle.blob bb on bb.hash = rrf.value_hash;
/*******************************************************************************
 * Bundle Ignored
 *
 * Relations that are not available for version control.
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

set search_path=bundle;
/*
select bundle_create('org.aquameta.core.bundle');

-- don't try to version control these tables in the version control system
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','commit'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','rowset_row_field'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','blob'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','tracked_row_added'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','stage_field_changed'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','stage_row_added'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','stage_row_deleted'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle_csv'));
insert into bundle.ignored_relation(relation_id) values (meta.relation_id('bundle','bundle_remote_database'));

-- don't try to version control anything in the built-in system catalogs
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('pg_catalog'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('public'));
insert into bundle.ignored_schema(schema_id) values (meta.schema_id('information_schema'));

-- stage and commit the above rows
select tracked_row_add('org.aquameta.core.bundle', 'bundle','ignored_relation','id',id::text) from bundle.ignored_relation;
-- select stage_row_add('org.aquameta.core.bundle', 'bundle','ignored_relation','id',id::text) from bundle.ignored_relation;

select tracked_row_add('org.aquameta.core.bundle', 'bundle','ignored_schema','id',id::text) from bundle.ignored_schema;
-- select stage_row_add('org.aquameta.core.bundle', 'bundle','ignored_schema','id',id::text) from bundle.ignored_schema;

-- select commit('org.aquameta.core.bundle', 'bundle bundle');
*/
