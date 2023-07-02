create or replace function endpoint.get_mimetype_id(_mimetype text) returns uuid as $$
    select id from endpoint.mimetype where mimetype=_mimetype;
$$ language sql;

create or replace function endpoint.set_mimetype(
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




/******************************************************************************
 * FUNCTION columns_json
 *****************************************************************************/

drop type if exists column_type;

create type column_type as (
    name text,
    "type" text
);

-- returns the columns for a provided schema.relation as a json object
create or replace function endpoint.columns_json(
    _schema_name text,
    _relation_name text,
    exclude text[],
    include text[],
    out json json
) returns json as $$
    begin
        execute
            'select (''['' || string_agg(row_to_json(row(c2.name, c2.type_name)::endpoint.column_type, true)::text, '','') || '']'')::json
            from (select * from meta.relation_column c
            where c.schema_name = ' || quote_literal(_schema_name) || ' and
                c.relation_name = ' || quote_literal(_relation_name) ||
                case when include is not null then
                    ' and c.name = any(' || quote_literal(include) || ')'
                else '' end ||
                case when exclude is not null then
                    ' and not c.name = any(' || quote_literal(exclude) || ')'
                else '' end ||
            ' order by position) c2'

            into json;
    end;
$$
language plpgsql;




/****************************************************************************************************
 * FUNCTION pk_name                                                                                 *
 ****************************************************************************************************/

create or replace function pk_name(
    _schema_name name,
    _relation_name name
) returns text as $$
select c.name
from meta.relation_column c --TODO: either use relation_column maybe?  Or go look up the pk of a view somewhere else if we ever add that
where c.schema_name = _schema_name and
        c.relation_name = _relation_name and
    c.primary_key
$$
    language sql security definer;










/****************************************************************************************************
 * FUNCTION column_list
 ****************************************************************************************************/

create or replace function endpoint.column_list(
    _schema_name text,
    _relation_name text,
    table_alias text,
    exclude text[],
    include text[],
    out column_list text
) as $$
begin
    if table_alias = '' then
        table_alias := _schema_name || '.' || _relation_name;
    end if;

    execute
                                    'select string_agg(' || quote_literal(table_alias) || ' || ''.'' || name, '', '')
            from meta.relation_column
            where schema_name = ' || quote_literal(_schema_name) || ' and
                relation_name = ' || quote_literal(_relation_name) ||
                                    case when include is not null then
                                                     ' and name = any(' || quote_literal(include) || ')'
                                         else '' end ||
                                    case when exclude is not null then
                                                     ' and not name = any(' || quote_literal(exclude) || ')'
                                         else '' end
        -- || ' group by position order by position' wrong.
        into column_list;

end;
$$ language plpgsql;

