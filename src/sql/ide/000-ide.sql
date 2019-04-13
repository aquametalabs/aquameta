/*******************************************************************************
 * IDE
 * User interface for Aquameta.
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/
begin;

create schema ide;
set search_path=ide;

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


commit;
