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



-- TODO: Add triggers on these tables that block modification.  They must never
-- be modified directly, as materialized views rely on them and must be kept in
-- sync.

create table rowset (
    id uuid not null default public.uuid_generate_v4() primary key
);

create table rowset_row (
    id uuid not null default public.uuid_generate_v4() primary key,
    rowset_id uuid references rowset(id) on delete cascade,
    row_id meta.row_id
);

create table rowset_row_dependency (
    id uuid not null default public.uuid_generate_v4() primary key,
    rowset_row_id uuid references rowset_row(id) on delete cascade,
    dependent_row_id uuid references rowset_row(id) on delete cascade
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
-- relying on naming convention for constraints here :/
alter table bundle alter constraint bundle_checkout_commit_id_fkey deferrable initially immediate;
alter table bundle alter constraint bundle_head_commit_id_fkey deferrable initially immediate;

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
create materialized view head_commit_row as
select b.id as bundle_id, c.id as commit_id, rr.id as rowset_row_id, rr.row_id
from bundle.bundle b
    join bundle.commit c on b.head_commit_id=c.id
    join bundle.rowset r on r.id = c.rowset_id
    join bundle.rowset_row rr on rr.rowset_id = r.id;


-- head_commit_row: show the fields in each head commit
create materialized view head_commit_field as
select hcr.*, rrf.field_id, rrf.value_hash
from bundle.head_commit_row hcr
    join bundle.rowset_row_field rrf on rrf.rowset_row_id = hcr.rowset_row_id;


-- head_commit_row_with_exists: rows in the head commit, along with whether or
-- not that row actually exists in the database
-- can't be materialized because of call to row_exists()
-- TODO: can we optimize this query by calling something like meta.rows_exist(row_id[])?
create view head_commit_row_with_exists as
select hcf.*, meta.row_exists(hcf.row_id) as exists
from head_commit_field hcf;



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
    value jsonb,
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
        (row_id).schema_name as schema_name,
        count(*) as count
    from bundle.offstage_row_deleted
group by 1,2;

create view offstage_row_deleted_by_relation as
    select row_id::meta.schema_id as schema_id,
        (row_id).schema_name as schema_name,
        row_id::meta.relation_id as relation_id,
        (row_id).relation_name as relation_name,
        count(*) as count
    from bundle.offstage_row_deleted
group by 1,2,3,4;


create or replace view bundle.offstage_field_changed as
    -- get literal_value (the expensive part) in a CTE
    with f as (
        -- for all the fields in this commit (with their working copy literal value)
        select
            f.field_id,
            f.row_id,
            -- working copy value
            meta.field_id_literal_value(f.field_id) as new_value,
            f.bundle_id,
            f.value_hash
        from bundle.head_commit_field f
    )
    select f.field_id, f.row_id, b.value as old_value, f.new_value, f.bundle_id
    from f
        -- their value in the repository
        join bundle.blob b on f.value_hash = b.hash
        -- if the change is staged, skip it
        left join bundle.stage_field_changed sfc on f.field_id = sfc.field_id
    where sfc.field_id is null
        -- they have changed
        and b.value != f.new_value;

create or replace view bundle.offstage_field_changed2 as
    -- get literal_value (the expensive part) in a CTE
    with f as (
        -- for all the fields in this commit (with their working copy literal value)
        select
            f.field_id,
            f.row_id,
            -- working copy value
            meta.field_id_literal_value(f.field_id) as new_value,
            f.bundle_id,
            f.value_hash
        from bundle.head_commit_field f
    )
    select f.field_id, b.value as old_value, f.new_value, f.bundle_id, f.row_id
    from f
        -- their value in the repository
        join bundle.blob b on f.value_hash = b.hash
        -- if the change is staged, skip it
        left join bundle.stage_field_changed sfc on f.field_id = sfc.field_id
    where sfc.field_id is null
        -- they have changed
        and b.value != f.new_value;

/*
create or replace function bundle.offstage_field_changed(_bundle_id uuid) returns setof bundle.offstage_field_changed as $$
    -- get literal_value (the expensive part) in a CTE
    with f as (
        -- for all the fields in this commit (with their working copy literal value)
        select
            f.field_id,
            f.row_id,
            -- working copy value
            meta.field_id_literal_value(f.field_id) as new_value,
            f.bundle_id,
            f.value_hash
        from bundle.head_commit_field f
        where f.bundle_id = _bundle_id
    )
    select f.field_id, f.row_id, b.value as old_value, f.new_value, f.bundle_id
    from f
        -- their value in the repository
        join bundle.blob b on f.value_hash = b.hash
        -- if the change is staged, skip it
        left join bundle.stage_field_changed sfc on sfc.bundle_id = _bundle_id and f.field_id = sfc.field_id
    where
        sfc.bundle_id = _bundle_id
            and sfc.field_id is null
            -- they have changed
            and b.value != f.new_value
$$ language sql;
*/

create type field_status as ( field_id meta.field_id, db_value text, db_value_hash text);

create or replace function head_row_field_with_value(_bundle_id uuid) returns setof bundle.field_status as $$
declare
    rel record;
    stmts text[];
    literals_stmt text;
    stmt text;
begin
    -- all relations in the head commit
    for rel in
        select
            (row_id::meta.relation_id).name as relation_name,
            (row_id::meta.relation_id).schema_name as schema_name,
            (row_id).pk_column_name as pk_column_name
        from bundle.head_commit_row
        where bundle_id = _bundle_id
        group by row_id::meta.relation_id, (row_id).pk_column_name
    loop

        -- for each relation, select head commit rows in this relation and also
        -- in this bundle, and join them with the relation's data, breaking it out
        -- into one row per field

        stmts := array_append(stmts, format('
            select hcr.row_id, jsonb_each_text(to_jsonb(x)) as keyval
            from bundle.head_commit_row hcr
                left join %I.%I x on
                    (hcr.row_id).pk_value = x.%I::text and
                    (hcr.row_id).schema_name = %L and
                    (hcr.row_id).relation_name = %L
            where hcr.bundle_id = %L
                and (hcr.row_id).schema_name = %L
                and (hcr.row_id).relation_name = %L',
            rel.schema_name,
            rel.relation_name,
            rel.pk_column_name,
            rel.schema_name,
            rel.relation_name,
            _bundle_id,
            rel.schema_name,
            rel.relation_name
        )
    );
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    -- wrap stmt to beautify columns
    literals_stmt := format('
        select
            meta.field_id((row_id).schema_name, (row_id).relation_name, (row_id).pk_column_name, (row_id).pk_value, (keyval).key),
            (keyval).value as db_value,
            public.digest((keyval).value, ''sha256'')::text as value_hash
        from (%s) fields;',
        literals_stmt
    );

    -- raise notice 'literals_stmt: %', literals_stmt;

    return query execute literals_stmt;

end
$$ language plpgsql;

/*
select head.field_id, head.value_hash, db.db_value_hash
from head_commit_field head
    join head_row_field_with_value((select id from bundle.bundle where name like '%.ide')) db
        on db.field_id = head.field_id 
        
where head.bundle_id=(select id from bundle.bundle where name like '%.ide') 
and head.value_hash != db.db_value_hash
order by head.field_id;
*/


/*
create view offstage_field_changed_by_schema as
select
    row_id::meta.schema_id as schema_id,
    (row_id).schema_name as schema_name,
    count(*) as count
from bundle.offstage_field_changed
group by schema_id, row_id;

create view offstage_field_changed_by_relation as
select row_id::meta.schema_id as schema_id,
    (row_id).schema_name as schema_name,
    row_id::meta.relation_id as relation_id,
    (row_id).relation_name relation_name,
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

a) if it was in the previous commit, those fields, but overwritten by
stage_field_changed.  stage_row already takes care of removing stage_row_added
and stage_row_deleted.

b) if it is a newly added row (it'll be in stage_row_added), then use the
working copy's fields

c) what if you have a stage_field_changed on a newly added row?  then, not
sure.  probably use it?

problem: stage_field_change contains W.C. data when there are unstaged changes.

*/

create or replace view stage_row_field as
/*
with mat as (
    select raise_message('hitting stage_row_field'), meta.refresh_all()
)*/
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
            )/*,
            true -- use meta_mat */
        )::text as value

    from bundle.stage_row_added sr
        join meta.relation re on meta.relation_id((sr.row_id).schema_name, (sr.row_id).relation_name) = re.id
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
getting closer:

create function stage_row_field(_bundle_id uuid) returns setof meta.field_id as $$
begin;
for keys in
	select
		count(*),
		b.name,
		sr.row_id::meta.relation_id as relation_id,
		(sr.row_id).pk_column_name as pk_column_name,
		string_agg((sr.row_id).pk_value, ',') as pk_values
	from stage_row sr
	join bundle b on sr.bundle_id = b.id
	where b.id = _bundle_id
	group by (sr.row_id)::meta.relation_id, ((sr.row_id).pk_column_name), b.name, b.id
loop
	execute format 'select * from %I join',
	keys.relation_id
	

loop over keys
	- select * from keys.relation_id

*/


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
create or replace function stage_row_keys_to_fields ()
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


create or replace view tracked_row as
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
        join bundle b on hcr.bundle_id=b.id
        full outer join bundle.stage_row sr on hcr.row_id=sr.row_id
        left join stage_field_changed sfc on (sfc.field_id)::meta.row_id=hcr.row_id
        left join offstage_field_changed ofc on ofc.bundle_id = b.id and (ofc.field_id)::meta.row_id=hcr.row_id
        -- left join offstage_field_changed(b.id) ofc on (ofc.field_id)::meta.row_id=hcr.row_id
        -- where b.checkout_commit_id is not null -- TODO I added this for a reason but now I can't remember why and it is breaking stuff
    group by hcr.bundle_id, hcr.commit_id, hcr.row_id, sr.bundle_id, sr.row_id, (sfc.field_id)::meta.row_id, (ofc.field_id)::meta.row_id

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
select hds.* from bundle.head_db_stage hds
    join bundle.bundle b on hds.bundle_id=b.id
where hds.change_type != 'same'
    or hds.stage_field_changes::text != '{}'
    or hds.offstage_field_changes::text != '{}'
    or hds.row_exists = false;



------------------------------------------------------------------------------
-- 9. UNTRACKED
--
-- All currently existing database rows that are not ignored (directly or via a
-- cascade), not currently in any of the head commits, and not in
-- stage_row_added [or stage_row_deleted?].
------------------------------------------------------------------------------

-- relations in this table will show up in untracked_rows, and can be staged etc.
-- it uses pk_column_id because views, foreign tables, etc. do not have primary
-- keys, so pk_column_id imposes one on the table, and will be treated as such.
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
    select
        pk_column_id::meta.relation_id as relation_id,
        pk_column_id::meta.schema_id as schema_id,
        pk_column_id as primary_key_column_id
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

create or replace view not_ignored_row_stmt as
select *, 'select meta.row_id(' ||
        quote_literal((r.schema_id).name) || ', ' ||
        quote_literal((r.relation_id).name) || ', ' ||
        quote_literal((r.primary_key_column_id).name) || ', ' ||
        quote_ident((r.primary_key_column_id).name) || '::text ' ||
    ') as row_id from ' ||
    quote_ident((r.schema_id).name) || '.' || quote_ident((r.relation_id).name) ||

    -- special case meta rows so that ignored_* cascades down to all objects in its scope:
    -- exclude rows from meta that are in "normal" tables that are ignored
    case
        -- schemas
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) = 'schema' then
           ' where id not in (select schema_id from bundle.ignored_schema) '
        -- relations
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('table', 'view', 'relation') then
           ' where id not in (select relation_id from bundle.ignored_relation) and schema_id not in (select schema_id from bundle.ignored_schema)'
        -- functions
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) = 'function' then
           ' where id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- columns
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) = 'column' then
           ' where id not in (select column_id from bundle.ignored_column) and id::meta.relation_id not in (select relation_id from bundle.ignored_relation) and id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'

        -- objects that exist in schema scope

        -- operator
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('operator') then
           ' where meta.schema_id(schema_name) not in (select schema_id from bundle.ignored_schema)'
        -- type
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('type') then
           ' where id::meta.schema_id not in (select schema_id from bundle.ignored_schema)'
        -- constraint_unique, constraint_check, table_privilege
        when (r.schema_id).name = 'meta' and ((r.relation_id).name) in ('constraint_check','constraint_unique','table_privilege') then
           ' where meta.schema_id(schema_name) not in (select schema_id from bundle.ignored_schema) and table_id not in (select relation_id from bundle.ignored_relation)'
        else ''
    end

    -- when meta views are tracked via 'trackable_nontable_relation', they
    -- setting a view as as a "trackable_non-table_relation",
    -- exclude rows from meta that are in trackable non-table tables that are ignored


    as stmt
from bundle.trackable_relation r;


-- all rows in the database that are not tracked, staged, in stage_row_deleted,
-- ignored, or in an existing bundle

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


-- helper agg function, shows in which schema all the untracked rows exist
create or replace view untracked_row_by_schema as
select meta.schema_id((r.row_id).schema_name) as schema_id, (r.row_id).schema_name as schema_name, count(*) as count
from bundle.untracked_row r
group by 1,2;

create or replace view untracked_row_by_relation as
select
    (r.row_id)::meta.relation_id as relation_id,
    (r.row_id).relation_name as relation_name,
    (r.row_id)::meta.schema_id as schema_id,
    count(*) as count
from bundle.untracked_row r
group by 1,2,3;



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

/*
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
*/
