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
    row_id meta.row_id
) returns text
as $$
    insert into bundle.tracked_row_added (bundle_id, row_id) values (
        (select id from bundle.bundle where name=bundle_name),
        row_id
    );
    select bundle_name || ' - ' || (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name || '.' || row_id.pk_value;
$$ language sql;

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
        -- raise log '------------ checkout_row % ----------',
        --    (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name ;
        set search_path=bundle,meta,public;

        if meta.row_exists(row_id) then
            -- raise log '---------------------- row % already exists.... overwriting.',
            -- (row_id::meta.schema_id).name || '.' || (row_id::meta.relation_id).name ;

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
        bundle_name text;
        commit_message text;
        _commit_id uuid;
        commit_role text;
        commit_time timestamp;
    begin
        set local search_path=bundle,meta,public;

        select b.name, c.id, c.message, c.time, (c.role_id).name
        into bundle_name, _commit_id, commit_message, commit_time, commit_role
        from bundle.bundle b
            join bundle.commit c on c.bundle_id = b.id
        where c.id = commit_id;

        if _commit_id is null then
            raise exception 'bundle.checkout() commit with id % does not exist', commit_id;
        end if;

        raise notice 'bundle.checkout(): % / % @ % by %: "%"', bundle_name, commit_id, commit_time, commit_role, commit_message;
        -- raise notice 'bundle: Checking out bundle %', commit_id;
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
