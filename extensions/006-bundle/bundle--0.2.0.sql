/*******************************************************************************
 * Bundle
 * Data Version Control System
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
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
 *     8. untracked - rows which are not in any head commit, and availble for
 *        stage_row_add()
 *     9. remotes - pushing and pulling to other databases
 *
 */

create schema bundle;

set search_path=bundle,meta,public;


-------------------------
-- UTIL FIXME
--------------------------
create function exec(statements text[]) returns setof record as $$
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
    id uuid default public.uuid_generate_v4() primary key,
    name text,
    -- head_commit_id uuid, (circular, added later)
    unique(name)
);

create table rowset (
    id uuid default public.uuid_generate_v4() primary key
);

create table rowset_row (
    id uuid default public.uuid_generate_v4() primary key,
    rowset_id uuid references rowset(id) on delete cascade,
    row_id meta.row_id
);

create table rowset_row_field (
    id uuid default public.uuid_generate_v4() primary key,
    rowset_row_id uuid references rowset_row(id) on delete cascade,
    field_id meta.field_id,
    value_hash text references blob(hash) on delete cascade,
    unique(rowset_row_id, field_id)
);

/*
create function rowset_row_field_hash_gen_trigger() returns trigger as $$
    begin
        -- raise notice 'ROWSET_ROW_FIELD_HASH_GEN_TRIGGER';
        NEW.value_hash = public.digest(NEW.value, 'sha256'::text)::bytea;

        -- check if the blob already exists
        if exists (select 1 from bundle.blob b where b.hash = NEW.value_hash) then
            -- raise notice 'already exists.';
            return NEW;
        end if;

        -- create the blob
        insert into bundle.blob(value) values (NEW.value);
        NEW.value = NULL;

        return NEW;
    end;
$$ language plpgsql;

create trigger rowset_row_field_hash_update
    before insert or update on bundle.rowset_row_field
    for each row execute procedure bundle.rowset_row_field_hash_gen_trigger();
*/


/*
removed.  start with single parent
create table commit_parent (
    id uuid default public.uuid_generate_v4() primary key,
    commit_id uuid references commit(id) on delete cascade,
    parent_id uuid references commit(id) on delete cascade
);
*/

create table commit (
    id uuid default public.uuid_generate_v4() primary key,
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
-- don't want to continue to be hasseled about adding to the stage.
------------------------------------------------------------------------------
create table ignored_row (
    id uuid default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id) on delete cascade,
    row_id meta.row_id,
    unique (row_id) --TOO RESTRICTIVE?
);

-- ignored_schema:  Ignored rows that are in meta.schema:  If a schema's meta row
-- is ignored, the ignore cascades down to every row in that schema, effectively
-- ignoring everything in it.
create view ignored_schema as
    select (row_id).pk_value::meta.schema_id as schema_id, row_id as meta_row_id
    from bundle.ignored_row
    where
        (row_id::meta.schema_id).name = 'meta' and
        (row_id::meta.relation_id).name = 'schema';

-- ignored_relation:  Same as ignored_schema but for relation.
create view ignored_relation as
    select (row_id).pk_value::meta.relation_id as relation_id, row_id as meta_row_id
    from bundle.ignored_row
    where
        (row_id::meta.schema_id).name = 'meta' and
        (row_id::meta.relation_id).name = 'relation';

-- TODO: ignored_column support...


------------------------------------------------------------------------------
-- 4. STAGED CHANGES
--
-- The tables where users add changes to be included in the next commit:  New
-- rows, deletd rows and changed fields.
------------------------------------------------------------------------------

-- a row not in the current commit, but is marked to be added to the next commit
create table stage_row_added (
    id uuid default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id) on delete cascade,
    row_id meta.row_id,
    unique (bundle_id, row_id)
); -- TODO: check that rows inserted into this table ARE NOT in the head commit's rowset

-- a row that is marked to be deleted from the current commit in the next commit
create table stage_row_deleted (
    id uuid default public.uuid_generate_v4() primary key,
    bundle_id uuid not null references bundle(id) on delete cascade,
    rowset_row_id uuid references rowset_row(id),
    unique (bundle_id, rowset_row_id)
); -- TODO: check that rows inserted into this table ARE in the head commit's rowset

-- a field that is marked to be different from the current commmit in the next
-- commit, with it's value
create table stage_field_changed (
    id uuid default public.uuid_generate_v4() primary key,
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
select
    sr.row_id as stage_row_id,
    meta.field_id(
        re.schema_name,
        re.name,
        re.primary_key_column_names[1], -- FIXME
        (sr.row_id).pk_value,
        c.name
    ) as field_id,

    meta.field_id_literal_value(
        meta.field_id(
            re.schema_name,
            re.name,
            re.primary_key_column_names[1], -- FIXME
            (sr.row_id).pk_value,
            c.name
        )
    )::text as value

from bundle.stage_row sr
    join meta.relation re on sr.row_id::meta.relation_id = re.id
    join meta.column c on c.relation_id=re.id
where sr.new_row=true

union all

------------ old rows with changed fields -------------
select
    sr.row_id as stage_row_id,
    hcf.field_id as field_id,
    case
        when sfc.field_id is not null then
            sfc.new_value
        else b.value
    end as value
from bundle.stage_row sr
    left join bundle.head_commit_field hcf on sr.row_id=hcf.row_id
    left join bundle.blob b on hcf.value_hash = b.hash
    left join stage_field_changed sfc on sfc.field_id = hcf.field_id
    where sr.new_row=false;





------------------------------------------------------------------------------
-- 7. TRACKED
--
-- rows that are in the "scope of concern" of the bundle.  a row must be
-- tracked before it can be staged.
------------------------------------------------------------------------------

create table tracked_row_added (
    id uuid default public.uuid_generate_v4() primary key,
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
    full outer join bundle.stage_row sr on hcr.row_id=sr.row_id
    left join stage_field_changed sfc on (sfc.field_id).row_id=hcr.row_id
    left join offstage_field_changed ofc on ofc.row_id=hcr.row_id
    group by hcr.bundle_id, hcr.commit_id, hcr.row_id, sr.bundle_id, sr.row_id, (sfc.field_id).row_id, ofc.row_id

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


-- Relations that are not specifically ignored, and not in a ignored schema
create or replace view not_ignored_relation as
    select relation_id, schema_id, primary_key_column_id from (
       -- every single table
    select t.id as relation_id, s.id as schema_id, r.primary_key_column_ids[1] as primary_key_column_id --TODO audit column
    from meta.schema s
    join meta.table t on t.schema_id=s.id
    join meta.relation r on r.id=t.id
    where primary_key_column_ids[1] is not null

    -- combined with every view in the meta schema
    UNION
    select v.id as relation_id, v.schema_id, meta.column_id('meta',v.name,'id') as primary_key_column_id
    from meta.view v
    where v.schema_name = 'meta'
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
Generates a set of sql statements that select not_ignored_rows: that are not
ignored by schema- or relation-ignores.  NOTE: We haven't pulled out
specifically ignored rows yet.
*/

create view not_ignored_row_stmt as
select *, 'select meta.row_id(' ||
    quote_literal((r.schema_id).name) || ', ' ||
    quote_literal((r.relation_id).name) || ', ' ||
    quote_literal((r.primary_key_column_id).name) || ', ' ||
    quote_ident((r.primary_key_column_id).name) || '::text ' ||
    ') as row_id from ' ||
    quote_ident((r.schema_id).name) || '.' || quote_ident((r.relation_id).name) as stmt
from bundle.not_ignored_relation r;
-- join

create or replace view untracked_row as
select r.row_id, r.row_id::meta.relation_id as relation_id
    from bundle.exec((
        select array_agg (stmt) from bundle.not_ignored_row_stmt
    )) r(
        row_id meta.row_id
    )
where r.row_id not in (
    select a.row_id from bundle.stage_row_added a
    union
    select t.row_id from bundle.tracked_row_added t
    union
    select rr.row_id from bundle.stage_row_deleted d join rowset_row rr on d.rowset_row_id=rr.id
    union
    select rr.row_id from bundle.bundle bundle
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


/*******************************************************************************
 * Bundle
 * Data Version Control System
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

/*
 * User Functions
 *     1. commit
 *     2. stage
 *     3. checkout
 */

set search_path=bundle,meta,public;


------------------------------------------------------------------------------
-- COMMIT FUNCTIONS
------------------------------------------------------------------------------
create or replace function commit (bundle_name text, message text) returns void as $$
    declare
        _bundle_id uuid;
        new_rowset_id uuid;
        new_commit_id uuid;
    begin

    select id
    into _bundle_id
    from bundle.bundle
    where name = bundle_name;

    -- make a rowset that will hold the contents of this commit
    insert into bundle.rowset default values
    returning id into new_rowset_id;

    -- STAGE
    -- ROWS: copy everything in stage_row to the new rowset
    insert into bundle.rowset_row (rowset_id, row_id)
    select new_rowset_id, row_id from bundle.stage_row where bundle_id=_bundle_id;


    -- FIELDS: copy all the fields in stage_row_field to the new rowset's fields
    insert into bundle.blob (value)
    select f.value
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id = rr.row_id;

    -- FIELDS: copy all the fields in stage_row_field to the new rowset's fields
    insert into bundle.rowset_row_field (rowset_row_id, field_id, value_hash)
    select rr.id, f.field_id, public.digest(value, 'sha256')
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id = rr.row_id;

    /*
    insert into bundle.blob (value)
    select rr.id, f.field_id, f.value
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id = rr.row_id
    join bundle.blob b on (f.field_id).row_id = rr.row_id;
    */

    -- create the commit
    insert into bundle.commit (bundle_id, parent_id, rowset_id, message)
    values (_bundle_id, (select head_commit_id from bundle.bundle b where b.id=_bundle_id), new_rowset_id, message)
    returning id into new_commit_id;

    -- point HEAD at new commit
    update bundle.bundle bundle set head_commit_id=new_commit_id where bundle.id=_bundle_id;

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

-- todo: make this recursive, up the commit_parent list
select c.id as commit_id, message, count(*)
from bundle b
join bundle.commit c on c.bundle_id = b.id
join bundle.rowset r on c.rowset_id=r.id
join bundle.rowset_row rr on rr.rowset_id = r.id
where b.name = bundle_name
group by b.id, c.id, message

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
    -- TODO: check to see if this row is not tracked by some other bundle!
    insert into bundle.tracked_row_added (bundle_id, row_id) values (
        (select id from bundle.bundle where name=bundle_name),
        meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
    );
    select bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value;
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
        where b.name=bundle_name and tra.row_id=meta.row_id(schema_name, relation_name, pk_column_name, pk_value);

    if not FOUND then
        raise exception 'No such bundle, or this row is not yet tracked by this bundle.';
    end if;

    delete from bundle.tracked_row_added tra
        where tra.row_id=meta.row_id(schema_name, relation_name, pk_column_name, pk_value);

    if not FOUND then
        raise exception 'Row could not be delete from tracked_row_added';
    end if;
    return (bundle_name || ' - ' || schema_name || '.' || relation_name || '.' || pk_value)::text;
    end;
$$
language plpgsql;



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
-- CHECKOUT FUNCTIONS
/*
ok.

fetch - get the latest stuff from a remote origin.  you should always be able to do this.
merge - transition the working copy to match the head commit
checkout -

*/


--
-- user stories:
--
-- 1. user downloads a new bundle, checking out where everything is fresh and
-- new.  we don't run into any collissions and just plop it all into place.
--
-- 2. user tries to check out a bundle when his working copy is different from
-- previous commit.  this would be indicated by rows in offstage_row_deleted and
-- offstage_field_change, or stage_row_*.
--
------------------------------------------------------------------------------

-- create or replace function checkout_row (in row_id meta.row_id, in fields text[], in vals text[], in force_overwrite boolean) returns void as $$
CREATE TYPE checkout_field AS (name text, value text, type_name text);

create or replace function checkout_row (in row_id meta.row_id, in fields checkout_field[], in force_overwrite boolean) returns void as $$
    declare
        query_str text;
    begin
        raise log '------------ checkout_row % ----------',
            (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name ;
        set search_path=bundle,meta,public;

        if meta.row_exists(row_id) then
            raise log '---------------------- row % already exists.... overwriting.',
            (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name ;

            -- check to see if this row which is being merged is going to overwrite a row that is
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
                        || '::'
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
            raise log '---------------------- row doesn''t exists.... INSERT:';
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


            /*
            (select string_agg (quote_ident((f::bundle.checkout_field).name), ',') from unnest(fields) as f) || ')'
                || ' values '
                || ' (' || (select string_agg (quote_literal(f.value) || '::' || (f::bundle.checkout_field).type_name,  ',') from unnest(fields) as f) || ')';
                */
        end if;
    end;

$$ language plpgsql;



-- checkout can only be run by superusers because it disables triggers, as described here: http://blog.endpoint.com/2012/10/postgres-system-triggers-error.html
create or replace function checkout (in commit_id uuid) returns void as $$
    declare
        commit_row record;
    begin
        set local search_path=bundle,meta,public;

        raise notice 'CHECKOUT SCHEMA %', commit_id;
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
                join meta.column col on (f.field_id).column_id = col.id
            where c.id=commit_id
            and (rr.row_id::meta.schema_id).name = 'meta'
            group by rr.id
            -- add meta rows first, in sensible order
            order by
                case
                    when row_id::meta.relation_id = meta.relation_id('meta','schema') then 0
                    when row_id::meta.relation_id = meta.relation_id('meta','table') then 2
                    when row_id::meta.relation_id = meta.relation_id('meta','column') then 3
                    when row_id::meta.relation_id = meta.relation_id('meta','sequence') then 4
                    when row_id::meta.relation_id = meta.relation_id('meta','constraint_check') then 4
                    when row_id::meta.relation_id = meta.relation_id('meta','constraint_unique') then 4
                    else 100
                end asc /*,
                case
                when row_id::meta.relation_id = meta.relation_id('meta','column') then array_agg(quote_literal(f.value))->position::integer
                else 0
                end
                    */
        loop
            -- raise log '------------------------------------------------------------------------CHECKOUT meta row: % %',
            --    (commit_row.row_id).pk_column_id.relation_id.name,
            --    (commit_row.row_id).pk_column_id.relation_id.schema_id.name;-- , commit_row.fields_agg;
            perform bundle.checkout_row(commit_row.row_id, commit_row.fields_agg, true);
        end loop;




        -- raise notice '################################################## DISABLING TRIGGERS % ###############################', commit_id;
        -- turn off constraints
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



        raise notice 'CHECKOUT DATA %', commit_id;
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
                join meta.column col on (f.field_id).column_id = col.id
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
        -- raise notice '################################################## ENABLING TRIGGERS % ###############################', commit_id;
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

        -- point head_commit_id to this commit
        update bundle.bundle set head_commit_id = commit_id where id in (select bundle_id from bundle.commit c where c.id = commit_id);

        return;

    end;
$$ language plpgsql;



create or replace function bundle.delete (in _bundle_id uuid) returns void as $$
    -- TODO: delete blobs
    delete from bundle.rowset r where r.id in (select c.rowset_id from bundle.commit c join bundle.bundle b on c.bundle_id = b.id where b.id = _bundle_id);
    delete from bundle.bundle where id = _bundle_id;
$$ language sql;

create or replace function bundle.delete_commit (in _commit_id uuid) returns void as $$
    -- TODO: delete blobs
    -- TODO: delete commits in order?
    delete from bundle.rowset r where r.id in (select c.rowset_id from bundle.commit c where c.id = _commit_id);
    delete from bundle.commit c where c.id = _commit_id;
$$ language sql;


/*******************************************************************************
 * Bundle Remotes
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

set search_path=bundle;



/*******************************************************************************
 * Bundle Remotes
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

set search_path=bundle;

-- bundle import and export functions

create or replace function bundle.bundle_export_csv(bundle_name text, directory text)
 returns void
 language plpgsql
as $$
begin
    execute format('copy (select distinct * from bundle.bundle
        where name=''%s'') to ''%s/bundle.csv''', bundle_name, directory);

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

    execute format('copy (select distinct ir.* from bundle.bundle b
        join bundle.ignored_row ir on ir.bundle_id=b.id
        where b.name=%L order by ir.id) to ''%s/ignored_row.csv''', bundle_name, directory);
end
$$;


create or replace function bundle.bundle_import_csv(directory text)
 returns void
 language plpgsql
as $$
begin
    execute format('alter table bundle.bundle disable trigger all');
    execute format('alter table bundle.commit disable trigger all');
    execute format('copy bundle.bundle from ''%s/bundle.csv''', directory);
    execute format('copy bundle.commit from ''%s/commit.csv''', directory);
    execute format('copy bundle.rowset from ''%s/rowset.csv''', directory);
    execute format('copy bundle.rowset_row from ''%s/rowset_row.csv''', directory);
    execute format('copy bundle.blob from ''%s/blob.csv''', directory);
    execute format('copy bundle.rowset_row_field from ''%s/rowset_row_field.csv''', directory);
    execute format('copy bundle.ignored_row from ''%s/ignored_row.csv''', directory);
    execute format('alter table bundle.bundle enable trigger all');
    execute format('alter table bundle.commit enable trigger all');
end
$$;

create or replace function garbage_collect ( ) returns void 
as $$
delete from bundle.blob where hash is null;
delete from bundle.rowset_row_field where value_hash is null;
delete from bundle.blob where hash not in (select value_hash from bundle.rowset_row_field);
delete from bundle.rowset where id not in (select rowset_id from bundle.commit);
$$ language sql;



/*******************************************************************************
 * Bundle Remotes
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

set search_path=bundle;

/*******************************************************************************
*
*
* BUNDLE REMOTES -- postgres_fdw
*
* This version uses the postgres_fdw foreign data wrapper to mount remote
* databases via a normal postgresql connection.  It uses IMPORT FOREIGN SCHEMA
* to import the bundle schema, and then provides various comparison functions
* for push, pull and merge.
* 
*******************************************************************************/

-- here's a table where you can stash some saved connections.
create table remote_database (
    id uuid default public.uuid_generate_v4() not null,
    foreign_server_name text,
    schema_name text,
    host text,
    port integer,
    dbname text,
    username text,
    password text
);


-- remote_mount()
--
-- setup a foreign server to a remote, and import it's bundle schema

create or replace function remote_mount (
    foreign_server_name text,
    schema_name text,
    host text,
	port integer,
    dbname text,
    username text,
    password text
)
returns boolean as
$$
begin
    execute format(
        'create server %I
            foreign data wrapper postgres_fdw
            options (host %L, port %L, dbname %L)',

        foreign_server_name, host, port, dbname
    );


    execute format(
        'create user mapping for public server %I options (user %L, password %L)',
        foreign_server_name, username, password
    );

    execute format(
        'create schema %I',
        schema_name
    );

    execute format(
        'import foreign schema bundle from server %I into %I options (import_default %L)',
        foreign_server_name, schema_name, 'true'
    );

    return true;
end;
$$ language plpgsql;




-- remote_diff ()
-- 
-- compare the bundles in two bundle schemas, typically a local one and a
-- remote one.  returns bundles present in the local but not the remote,
-- or visa versa.

create or replace function remote_diff( local meta.relation_id, remote meta.relation_id )
returns table (
    local_id uuid, local_name text, local_head_commit_id uuid,
    remote_id uuid, remote_name text, remote_head_commit_id uuid
)
as $$
begin
    raise log 'local: %s', local::text;
    return query execute format('
        select
            local.id as local_id, local.name as local_name, local.head_commit_id as local_head_commit_id,
            remote.id as remote_id, remote.name as remote_name, remote.head_commit_id as remote_head_commit_id
        from %I.%I local
            full outer join %I.%I remote
                using (id, name)
        where local.name is null or remote.name is null
        ', 
        (local::meta.schema_id).name, local.name, 
        (remote::meta.schema_id).name, remote.name
    );
end;
$$
language plpgsql;

-- remote_diff_commits (schema1_name, schema2_name)
-- 
-- returns commits in schema1 but not in schema2, or visa versa

create or replace function remote_diff_commits( local meta.relation_id, remote meta.relation_id )
returns table(
    local_id uuid, local_bundle_id uuid, local_role_id meta.role_id, local_parent_id uuid, local_time timestamp, local_message text, 
    remote_id uuid, remote_bundle_id uuid, remote_role_id meta.role_id, remote_parent_id uuid, remote_time timestamp, remote_message text
)
as $$
begin
    return query execute format('
        select 
            local.id as local_id, local.bundle_id as bundle_id, local.role_id as local_role_id, local.parent_id as local_parent_id, local.time as local_time, local.message as local_message,
            remote.id as remote_id, remote.bundle_id as bundle_id, remote.role_id as remote_role_id, remote.parent_id as remote_parent_id, remote.time as remote_time, remote.message as remote_message
        from %I.%I local
        full outer join %I.%I remote on local.id = remote.id
        where local.id is null or remote.id is null
        ', 
        (local::meta.schema_id).name, local.name, 
        (remote::meta.schema_id).name, remote.name
    );
end;
$$
language plpgsql;

-- remote_commits_ahead (local, remote)
--
-- returns commits in remote but not local

create or replace function remote_commits_ahead( local meta.relation_id, remote meta.relation_id )
returns setof bundle.commit
as $$
begin
    return query execute format('
        select remote.*
        from %I.%I local
        full outer join %I.%I remote on local.id = remote.id
        where local.id is null
        ', 
        (local::meta.schema_id).name, local.name, 
        (remote::meta.schema_id).name, remote.name
    );
end;
$$
language plpgsql;

-- remote_commits_behind (local, remote)
--
-- returns commits in local but not remote
-- (just punts off to remote_commits_ahead, switching local with remote, cause it's the exact opposite)

create or replace function remote_commits_behind ( local meta.relation_id, remote meta.relation_id )
returns setof bundle.commit
as $$
select * from remote_commits_ahead (remote, local);
$$
language sql;



-- remote_clone ()
--
-- copy a repository from one bundle schema (typically a remote) to another (typically a local one)

create or replace function remote_clone( bundle_id uuid, source_schema_name text, dest_schema_name text )
returns boolean as $$
begin
    -- rowset
    execute format ('insert into %2$I.rowset 
        select r.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- rowset_row
    execute format ('
        insert into %2$I.rowset_row 
        select rr.* from %1$I.commit c 
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- blob
    execute format ('
        insert into %2$I.blob
        select b.* from %1$I.commit c 
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
            join %1$I.blob b on f.value_hash = b.hash
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- rowset_row_field
    execute format ('
        insert into %2$I.rowset_row_field 
        select f.* from %1$I.commit c 
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- bundle
    execute format ('insert into %2$I.bundle
		(id, name)
        select b.id, b.name from %1$I.bundle b
        where b.id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- commit
    execute format ('
        insert into %2$I.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

	execute format ('update %2$I.bundle
		set head_commit_id = (
        select b.head_commit_id
		from %1$I.bundle b
        where b.id=%3$L) where id=%3$L', source_schema_name, dest_schema_name, bundle_id);


    return true;
end;
$$
language plpgsql;

insert into bundle values
('13aa5018-d573-4e0c-97ca-7f9fffb6602e', 'org.aquameta.core.bundle', null);

insert into bundle.ignored_row values
('088ee8d1-d7ee-408d-b3fe-fb9c07cc1ce0', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/column)'),
('09336141-8b1a-48ef-b5be-8c0292c9c6f2', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/function)'),
('0ea9f764-0414-4c45-b2ec-37f6253deeb3', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/foreign_data_wrapper)'),
('29b215df-d0bd-4d7d-b52c-6581ba4fae3b', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/connection)'),
('2ae6b663-9932-4cbc-881a-0fcbcf675a27', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/policy_role)'),
('42416f5f-1e45-4cba-98ff-53117befc526', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/foreign_server)'),
('490e92ba-0992-4c03-9ca8-21a4c73df6ca', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/foreign_table)'),
('4b254438-a4fe-4c12-af2a-4d83af785841', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/view)'),
('50c70c8a-a277-4d61-8c23-b50bedc98304', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/operator)'),
('5142013a-c5a8-4c42-906b-21007c462a99', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",schema)"",id)","(information_schema)")'),
('55e34f31-67f3-47c6-b584-dcfb020883fe', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",schema)"",id)","(public)")'),
('5a39a34f-6838-43c0-b4e7-ce32f0a0c49b', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/schema)'),
('66fec083-2473-4b43-b658-7ac412ba538c', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/foreign_key)'),
('6adcc24f-41e4-49d6-a61b-af3a6451de9b', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/constraint_check)'),
('74308e28-7cba-4689-84f7-4cc3b4784a84', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/table_privilege)'),
('7c57a311-a27e-46ed-a95b-a5fa09d55ccb', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/type)'),
('7d814d78-60f9-4ece-8849-b27b69bd89e7', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/role_inheritance)'),
('815aaf8b-8749-4f09-b251-5173868f3775', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",schema)"",id)","(bundle)")'),
('834cf588-ebde-4e15-b02b-55f36c3495ef', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/sequence)'),
('8a1bd0d9-9e03-427e-9085-3b9c8619e3f3', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/policy) '),
('934211ad-66e0-46ba-b13a-63a7448af9a4', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/cast)'),
('a187b3e9-69af-44c8-b6e3-3930cb2e5015', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/table)'),
('a70c7c51-3060-4ee9-ac48-10697c0edb07', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/constraint_unique)'),
('bedb1e4b-b1eb-470b-808b-5fc47a70b3b3', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/trigger)'),
('c0920a5c-59c8-4f66-aeee-cdb045bf9760', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/extension)'),
('c21a871b-7ea6-4dad-b3b6-c8a41884fdaa', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/foreign_column)'),
('ddb8fd26-95f4-4739-b244-1a9c694e9a5c', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",endpoint/user)'),
('e1df0909-5844-41d5-9f16-d6b1b09deb55', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/function_parameter)'),
('e71ba721-a341-4690-a3cf-7e687df63cda', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",schema)"",id)","(pg_catalog)")'),
('f02dde93-d189-4a10-b0fc-6327427d20df', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/role)'),
('f4357328-a6d9-4aca-8804-86201deed976', '13aa5018-d573-4e0c-97ca-7f9fffb6602e', '("(""(""""(meta)"""",relation)"",id)",meta/relation)')
;
