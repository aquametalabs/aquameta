drop schema if exists ux cascade;
create schema ux;
set search_path=ux;
create view all_tables_schemas as
    select s.name || '.' || r.name as name, s.name as schema_name, r.name as relation_name
        from meta.schema s
        join meta.relation r on r.schema_id=s.id
        order by s.name, r.name;
