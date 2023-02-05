begin;

set search_path=endpoint;

create function endpoint.get_mimetype_id(_mimetype text) returns uuid as $$
    select id from endpoint.mimetype where mimetype=_mimetype;
$$ language sql;

create function endpoint.set_mimetype(
    _schema name,
    _table name,
    _column name,
    _mimetype text
) returns void as $$
insert into endpoint.column_mimetype (column_id, mimetype_id)
select c.id, m.id
from meta.relation_column c
         cross join endpoint.mimetype m
where c.schema_name   = _schema and
        c.relation_name = _table and
        c.name          = _column and
        m.mimetype = _mimetype
$$ language sql;


commit;
