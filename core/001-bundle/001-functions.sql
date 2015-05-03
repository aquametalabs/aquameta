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

begin;

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
    insert into bundle.rowset_row_field (rowset_row_id, field_id, value_hash)
    select rr.id, f.field_id, f.value
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id = rr.row_id;

    insert into bundle.blob (value)
    select rr.id, f.field_id, f.value
    from bundle.rowset_row rr
    join bundle.rowset r on r.id=new_rowset_id and rr.rowset_id=r.id
    join bundle.stage_row_field f on (f.field_id).row_id = rr.row_id
    join bundle.blob b on (f.field_id).row_id = rr.row_id;

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
from bundle.commit c
join bundle.rowset r on c.rowset_id=r.id
join bundle.rowset_row rr on rr.rowset_id = r.id
group by c.id, message

$$ language sql;



------------------------------------------------------------------------------
-- STAGE FUNCTIONS
------------------------------------------------------------------------------
-- stage an add
create or replace function stage_row_add (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns void
as $$
    insert into bundle.stage_row_added (bundle_id, row_id) values (
        (select id from bundle.bundle where name=bundle_name),
        meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
    );
$$ language sql;


-- unstage an add
create or replace function unstage_row_add (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns void
as $$
    delete from bundle.stage_row_added
        where bundle_id = (select id from bundle.bundle where name=bundle_name)
          and row_id=meta.row_id(schema_name, relation_name, pk_column_name, pk_value);
$$ language sql;


create or replace function stage_row_delete (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns void
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
        and rr.row_id = meta.row_id(schema_name, relation_name, pk_column_name, pk_value)
$$ language sql;



create or replace function unstage_row_delete (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text
) returns void
as $$
    delete from bundle.stage_row_deleted srd
    using bundle.rowset_row rr
    where rr.id = srd.rowset_row_id
        and srd.bundle_id=(select id from bundle.bundle where name=bundle_name)
        and rr.row_id=meta.row_id(schema_name, relation_name, pk_column_name, pk_value);
$$ language sql;


/* all text interface */
create or replace function stage_field_change (
    bundle_name text,
    schema_name text,
    relation_name text,
    pk_column_name text,
    pk_value text,
    column_name text -- FIXME: somehow the webserver thinks it's a relation if column_name is present??
) returns void
as $$
    insert into bundle.stage_field_changed (bundle_id, field_id, new_value)
    values (
        (select id from bundle.bundle where name=bundle_name),
        meta.field_id (schema_name, relation_name, pk_column_name, pk_value, column_name),
        meta.field_id_literal_value(
            meta.field_id (schema_name, relation_name, pk_column_name, pk_value, column_name)
        )
    );
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
) returns void
as $$
    delete from bundle.stage_field_changed
        where field_id=
            meta.field_id (schema_name, relation_name, pk_column_name, pk_value, column_name);
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
                        || '::'
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



create or replace function checkout (in commit_id uuid) returns void as $$
    declare
        commit_row record;
    begin
        set local search_path=bundle,meta,public;

        raise notice '################################################## CHECKOUT SCHEMA % ###############################', commit_id;

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
            raise log '------------------------------------------------------------------------CHECKOUT meta row: % %',
                (commit_row.row_id).pk_column_id.relation_id.name,
                (commit_row.row_id).pk_column_id.relation_id.schema_id.name;-- , commit_row.fields_agg;
            perform bundle.checkout_row(commit_row.row_id, commit_row.fields_agg, true);
        end loop;







        raise notice '################################################## DISABLING TRIGGERS % ###############################', commit_id;
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
            raise log '-------------------------------- DISABLING TRIGGER on table %',
                quote_ident(commit_row.schema_name) || '.' || quote_ident(commit_row.relation_name);

            execute 'alter table '
                || quote_ident(commit_row.schema_name) || '.' || quote_ident(commit_row.relation_name)
                || ' disable trigger all';
        end loop;


        raise notice '################################################## CHECKOUT DATA % ###############################', commit_id;
        -- insert the rows
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
            raise log '------------------------------------------------------------------------CHECKOUT row: % %',
               (commit_row.row_id).pk_column_id.relation_id.name,
               (commit_row.row_id).pk_column_id.relation_id.schema_id.name;-- , commit_row.fields_agg;
            perform bundle.checkout_row(commit_row.row_id, commit_row.fields_agg, true);
        end loop;



        -- turn constraints back on
        raise notice '################################################## ENABLING TRIGGERS % ###############################', commit_id;
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

        return;

    end;
$$ language plpgsql;





------------------------------------------------------------------------------
-- PUSH/FETCH FUNCTIONS
--
--
------------------------------------------------------------------------------
/* PACKER */
/* This is used to push/pull bundles over WebRTC */
create type rowbundle as (
    row_id meta.row_id,
    row_json json
);

create table bundle._bundlepacker_tmp (row_id meta.row_id, next_fk uuid);

create or replace function bundlepacker (bundle_id uuid)
returns setof rowbundle
as $$

begin
    set local search_path=bundle;
    delete from bundle._bundlepacker_tmp;

    insert into bundle._bundlepacker_tmp select meta.row_id('bundle','bundle','id', id::text), null from bundle where id=bundle_id;
    insert into bundle._bundlepacker_tmp select meta.row_id('bundle','commit','id', id::text), rowset_id from bundle.commit c where c.bundle_id::text in (select (row_id).pk_value from bundle._bundlepacker_tmp);
    insert into bundle._bundlepacker_tmp select meta.row_id('bundle','rowset','id', id::text), null from bundle.rowset where id in (select next_fk from bundle._bundlepacker_tmp where (row_id::meta.relation_id).name = 'commit');
    insert into bundle._bundlepacker_tmp select meta.row_id('bundle','rowset_row','id', id::text), rowset_id from bundle.rowset_row rr where rr.rowset_id::text in (select (row_id).pk_value from bundle._bundlepacker_tmp where (row_id::meta.relation_id).name = 'rowset');
    insert into bundle._bundlepacker_tmp select meta.row_id('bundle','rowset_row_field','id', id::text), rowset_row_id from bundle.rowset_row_field rr where rr.rowset_row_id::text in (select (row_id).pk_value from bundle._bundlepacker_tmp where (row_id::meta.relation_id).name = 'rowset_row');

    RETURN QUERY EXECUTE  'select row_id, meta.row_id_to_json(row_id) from bundle._bundlepacker_tmp';

end;
$$ language plpgsql;


/* UNPACKER */
create table bundleunpacker (bundle text);


create or replace function bundleunpacker_insert_function()
returns trigger
as $$
declare
    bundle_row record;
    row_id meta.row_id;
begin
    -- raise notice 'NEW.row_id::json:::::::::::::::::::::::::::::: %', NEW.bundle::json;

    -- setof key text, value json
    for bundle_row in select * from json_each(NEW.bundle::json)
    loop
        row_id := meta.row_id(bundle_row.value->'row_id');

        raise notice 'ARRRRRRRRRRRGS: bundle_row.value->"row_id": %     row_id: %         % % % %',
            bundle_row.value->'row_id',
            row_id,
            (row_id::meta.schema_id).name,
            'table',
            (row_id::meta.relation_id).name,
            bundle_row.value->'row_json';



        select * from www.row_insert(
            (row_id::meta.schema_id).name,
            'table',
            (row_id::meta.relation_id).name,
            bundle_row.value->'row_json'
        );

        raise notice 'bundle_row.value->row_json = %', bundle_row.value->'row_json';

        /*
        raise notice 'bundle_row.value = %', bundle_row.value;
        execute 'insert into ' || quote_ident((row_id::meta.schema_id).name)
                               || '.' quote_ident((row_id::meta.relation_id).name)
                               || '.'
        */
    end loop;

    return NEW;
end;
$$ language plpgsql;

create trigger bundleunpacker_insert_trigger after insert on bundleunpacker
FOR EACH ROW
execute procedure bundleunpacker_insert_function ();


-- push
/*
1. ask the remote repository if it has the bundle
    yes:
        ask the remote what commits it has in the
            x,y,z:
                send commits where not in x,y,x
    no:







*/

/*
create function push (bundle_id uuid, remote_id uuid)
returns void as $$

    -- http://localhost:8080/endpoint/bundle/table/commit/rows?bundle_id=737177af-16f4-40e1-ac0d-2c11b2b727e9
    with remote_host as
        (select r.host from bundle.remote r where r.id=remote_id)
    select * from http_get (
    -- http_get (







$$ language plpgsql;


*/

