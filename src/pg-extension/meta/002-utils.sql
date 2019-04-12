/*******************************************************************************
 * Meta Helper Utilities
 * Handy functions for working with meta-related stuff.
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/
create or replace function meta.row_exists(in row_id meta.row_id, out answer boolean) as $$
    declare
        stmt text;
    begin
        stmt := format (
            'select (count(*) = 1) from %I.%I where %I::text = %L',
                (row_id::meta.schema_id).name,
                (row_id::meta.relation_id).name,
                (row_id.pk_column_id).name,
                row_id.pk_value
            );

        -- raise warning '%s', stmt;
        execute stmt into answer;

    end;
$$ language plpgsql;


/*
create or replace function meta.row_delete(in row_id meta.row_id, out answer boolean) as $$
$$ language plpgsql;
*/
