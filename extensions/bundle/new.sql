begin;

set search_path=bundle;

-- a field and it's value hash.  this type can be used for both live db literal values and repo values
create type field_hash as ( field_id meta.field_id, value_hash text);


create or replace function get_commit_fields(_commit_id uuid) returns setof field_hash as $$
    select rrf.field_id, rrf.value_hash
    from commit c
       join rowset r on c.rowset_id = r.id
       join rowset_row rr on rr.rowset_id = r.id
       join rowset_row_field rrf on rrf.rowset_row_id = rr.id
    where c.id = _commit_id;
$$ language sql;

create or replace function get_commit_rows(_commit_id uuid, _relation_id meta.relation_id default null) returns setof meta.row_id as $$
    select rr.row_id as row_id
    from commit c
       join rowset r on c.rowset_id = r.id
       join rowset_row rr on rr.rowset_id = r.id
    where c.id = _commit_id and
        case when _relation_id is null then true else (rr.row_id)::meta.relation_id = _relation_id end;
$$ language sql;


/*
head_row_db_hashes(_commit_id uuid)

Returns a field_hash for live database values for a given commit.  It returns
*all* columns present, without regard to what columns or fields are actually
being tracked in the database.  Think `select * from my.table`.  This means:

- when a field is changed since the last commit, the change will be reflected here
- when a column is added since the provided commit, it will be present in this list
- when a column is deleted since the provided commit, it will be absent from this list

Steps:

1) make a list of the relations of all rows in the supplied commit

2) for each relation "x":
   a) start with the contents of rowset_row for this commit, then LEFT JOIN with
      the relation, on

      rowset_row.row_id.pk_value IS NOT DISTINCT FROM x.$pk_column_name

      (NOT DISTINCT because null != null, and that's a match in this situation)

   b) call jsonb_each_text(to_json(x)) which makes a row for each field
   c) construct the field's field_id, and sha256 the field's value

3) UNION all these field_id + hashes from all these relations together and
   return a big list of field_hash records, (meta.field_id, value_hash)

It returns the value hash of all fields on any row in the supplied commit, with
it's value hash.  Typically this would be called with the bundle's head commit
(bundle.head_commit_id), though it can be used to diff against previous commits
as well.

It is useful for generating a bundle's row list with change info, as well as
the stage.  When you INNER JOIN this function's results against
rowset_row_field, non-matching hashes will be fields changed.  When you OUTER
JOIN, it'll pick up new fields (from new columns presumably).
*/


create or replace function get_db_fields(commit_id uuid) returns setof bundle.field_hash as $$
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
        from get_commit_rows(commit_id) row_id
        group by row_id::meta.relation_id, (row_id).pk_column_name
    loop
        -- TODO: check that each relation exists and has not been deleted.
        -- currently, when that happens, this function will fail.

        -- for each relation, select head commit rows in this relation and also
        -- in this bundle, and inner join them with the relation's data, breaking it out
        -- into one row per field

        stmts := array_append(stmts, format('
            select row_id, jsonb_each_text(to_jsonb(x)) as keyval
            from bundle.get_commit_rows(%L, meta.relation_id(%L,%L)) row_id
                left join %I.%I x on -- (#(#) )
                    (row_id).pk_value is not distinct from x.%I::text and -- catch null = null!
                    (row_id).schema_name = %L and
                    (row_id).relation_name = %L',
            commit_id,
            rel.schema_name,
            rel.relation_name,
            rel.schema_name,
            rel.relation_name,
            rel.pk_column_name,
            rel.schema_name,
            rel.relation_name
        )
    );
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    -- wrap stmt to beautify columns
    literals_stmt := format('
        select
            meta.field_id((row_id).schema_name,(row_id).relation_name, (row_id).pk_column_name, (row_id).pk_value, (keyval).key),
            public.digest((keyval).value, ''sha256'')::text as value_hash
        from (%s) fields;',
        literals_stmt
    );

    raise notice 'literals_stmt: %', literals_stmt;

    return query execute literals_stmt;

end
$$ language plpgsql;


create type commit_row as ( row_id meta.row_id, exists boolean);

create or replace function get_db_rows(commit_id uuid) returns setof commit_row as $$
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
        from get_commit_rows(commit_id, null) row_id
        group by row_id::meta.relation_id, (row_id).pk_column_name
    loop
        -- TODO: check that each table exists and has not been deleted.  when
        -- that happens, this function will fail.

        -- for each relation, select head commit rows in this relation and also
        -- in this bundle, and inner join them with the relation's data, breaking it out
        -- into one row per field

        stmts := array_append(stmts, format('
            select row_id, x.%I is not null as exists
            from bundle.get_commit_rows(%L, meta.relation_id(%L,%L)) row_id
                left join %I.%I x on
                    (row_id).pk_value is not distinct from x.%I::text and -- catch null = null!
                    (row_id).schema_name = %L and
                    (row_id).relation_name = %L',
            rel.pk_column_name,
            commit_id,
            rel.schema_name,
            rel.relation_name,
            rel.schema_name,
            rel.relation_name,
            rel.pk_column_name,
            rel.schema_name,
            rel.relation_name
        )
    );
    end loop;

    literals_stmt := array_to_string(stmts,E'\nunion\n');

    -- raise notice 'literals_stmt: %', literals_stmt;

    return query execute literals_stmt;
end;
$$ language plpgsql;


create type row_status as (row_id meta.row_id, exists boolean, changed_fields meta.field_id[]);
create or replace function get_rows_status(commit_id uuid) returns setof row_status as $$
select
    r.row_id,
    r.exists,
    case when r.exists = false then
        null
    else
        -- set to null if array is empty
        nullif(
            -- remove nulls
            array_remove(
                -- agg
                array_agg(
                    -- not changed
                    case when cf.value_hash is not distinct from dbf.value_hash then -- AUDIT can't we use = here? indf is so slow
                        null
                    else
                        dbf.field_id
                    end
                ),
                null
            ),
            '{}'
        )
    end as changed_fields
from get_db_rows(commit_id) as r
    join get_commit_fields(commit_id) cf
        on (cf.field_id)::meta.row_id = r.row_id
    left join get_db_fields(commit_id) dbf
        on (dbf.field_id)::meta.row_id = r.row_id
        and dbf.field_id = cf.field_id
group by r.row_id, r.exists
$$ language sql;

