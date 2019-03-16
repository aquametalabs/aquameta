/*******************************************************************************
 * Meta Helper Utilities
 * Handy functions for working with meta-related stuff.
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
create or replace function meta.row_exists(in row_id meta.row_id, out answer boolean) as $$
    declare
        stmt text;
    begin
        execute 'select (count(*) = 1) from ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) ||
                ' where ' || quote_ident((row_id.pk_column_id).name) || ' = ' || quote_literal(row_id.pk_value)
            into answer;
    exception
        when others then answer := false;

    end;
$$ language plpgsql;


/*
create or replace function meta.row_delete(in row_id meta.row_id, out answer boolean) as $$
$$ language plpgsql;
*/
