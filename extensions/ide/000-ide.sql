/*******************************************************************************
 * IDE
 * User interface for Aquameta.
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/
/*

needs bundle v0.5 audit


create or replace view ide.bundle_contained_relation as
select *, count(*) as count from (
select (row_id::meta.schema_id).name as schema_name, (row_id::meta.relation_id).name
from bundle.bundle b
    join bundle.head_db_stage hds on hds.bundle_id=b.id
) x
group by x.schema_name, x.name;



create or replace view ide.foreign_key as
select table_id,
    unnest(from_column_ids) as from_column_id,
    unnest(to_column_ids) as to_column_id
from meta.foreign_key;


create table ide.sql_code (
    id uuid not null default public.uuid_generate_v4() primary key,
    code text not null default ''
);


*/

create or replace view ide.resource as
select r.*, b.id as bundle_id, b.name from (
    select meta.row_id('endpoint','resource','id',r.id::text), path, mimetype
    from endpoint.resource r
        join endpoint.mimetype m on r.mimetype_id = m.id

    union

    select meta.row_id('endpoint','resource_binary','id',rb.id::text), path, mimetype
    from endpoint.resource_binary rb
      join endpoint.mimetype m on rb.mimetype_id = m.id
) r

left join (
    select id, name, bundle.get_tracked_rows(name) as row_id from bundle.repository
) b

on r.row_id = b.row_id
order by path;


/*


needs bundle v0.5 audit


create or replace view ide.route as
select r.*, b.id as bundle_id, b.name from (
    select meta.row_id('endpoint','template_route','id',r.id::text), url_pattern, t.name as template_name, mimetype
    from endpoint.template_route r
        join endpoint.template t on r.template_id = t.id
        join endpoint.mimetype m on t.mimetype_id = m.id
) r
join bundle.rowset_row rr on rr.row_id = r.row_id
join bundle.rowset rs on rr.rowset_id = rs.id
join bundle.commit c on c.rowset_id = rs.id
join bundle.bundle b on b.head_commit_id = c.id
order by url_pattern;



create or replace view ide.big_stage as
select b.name, b.id as bundle_id, count(*) as row_count, (h.row_id)::meta.relation_id as relation_id, change_type
from bundle.head_db_stage_changed h
join bundle.bundle b on h.bundle_id = b.id
where b.checkout_commit_id is not null
group by b.name, b.id, (row_id)::meta.relation_id, change_type
order by b.name;



create or replace view ide.commit_with_mergable as
select
    c.*,
	bundle.commit_ancestry(c.id),
	bundle.commits_common_ancestor(c.id, b.head_commit_id),
	bundle.commit_is_mergable(c.id)
from bundle.commit c
    join bundle.bundle b on c.bundle_id = b.id;
*/

create or replace function ide.repository_row_list( repository_id uuid)
returns table (row_id meta.row_id, changed boolean, change_type text) as $$
    -- head commit rows
	select
        dbcf.field_id::meta.row_id,
        bool_or(dbcf.value_hash is distinct from hcf.value_hash) as changed,
        'same' as change_type -- FIXME
	from bundle._get_db_commit_fields(bundle._head_commit_id(repository_id)) dbcf
		full outer join bundle._get_commit_fields(bundle._head_commit_id(repository_id)) hcf on hcf.field_id = dbcf.field_id
	 group by 1

	union

    -- stage rows to add
	select srta.row_id as row_id, true as changed, 'staged' as change_type
	from bundle._get_stage_rows_to_add(repository_id) srta

    union

    -- tracked rows added
    select tra.row_id, true as changed, 'tracked'
    from bundle._get_tracked_rows_added(repository_id) tra


$$ language sql;
