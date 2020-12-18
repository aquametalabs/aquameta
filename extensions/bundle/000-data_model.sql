/*******************************************************************************
 * Bundle
 * Data Version Control System
 * 
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
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
    id uuid not null default public.uuid_generate_v4() primary key,
    name text,
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
-- rows, deletd rows and changed fields.
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

-- a field that is marked to be different from the current commmit in the next
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
    left join bundle.head_commit_field hcf on sr.row_id=hcf.row_id
    left join bundle.blob b on hcf.value_hash = b.hash
    left join stage_field_changed sfc on sfc.field_id = hcf.field_id
    where sr.new_row=false;


/*


ATTEMPT TO OPTIMIZE STAGE_ROW_FIELD, ended in tears.

ok.
1. for all the rows in stage_row, aggregate each relation, it's pk column, and the pk's of each row.
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
    full outer join bundle.stage_row sr on hcr.row_id=sr.row_id
    left join stage_field_changed sfc on (sfc.field_id).row_id=hcr.row_id
    left join offstage_field_changed ofc on (ofc.field_id).row_id=hcr.row_id
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
-- TODO: why does this have schema_id and pk_column_id?  should just be a realtion_id no?
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
Generates a set of sql statements that select not_ignored_rows: that are not
ignored by schema- or relation-ignores.
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


-- here's a table where you can stash some saved connections.
create table remote_database (
    id uuid not null default public.uuid_generate_v4() primary key,
    foreign_server_name text,
    schema_name text,
    host text,
    port integer,
    dbname text,
    username text,
    password text
);


------------------------------------------------------------------------------
-- 9. ORIGINS
--
-- When a bundle is imported or fetched, the origin is the source from whence
-- it came.   We use this on push and pull, import and export.
------------------------------------------------------------------------------

create table bundle_origin_csv (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid references bundle(id) on delete cascade,
    directory text not null
);


create table bundle_origin_remote (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid references bundle(id) on delete cascade,
    remote_database_id uuid references remote_database(id) on delete cascade
);


------------------------------------------------------------------------------
-- 9. EXTENSION DUMP CONFIGURATION
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
select pg_catalog.pg_extension_config_dump('bundle_origin_csv','');
select pg_catalog.pg_extension_config_dump('bundle_origin_remote','');
