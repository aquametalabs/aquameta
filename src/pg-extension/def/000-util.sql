/*******************************************************************************
 * Definitions Catalog
 * A view for every type of PostgreSQL object that contains it's definition statement
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

/******************************************************************************
 * require_one and require_all()
 *****************************************************************************/
create function def.require_all(fields public.hstore, required_fields text[]) returns void as $$
    declare
        f record;

    begin
        -- hstore needs this
        set local search_path=public,def;
        for f in select unnest(required_fields) as field_name loop
            if (fields->f.field_name) is null then
                raise exception '% is a required field.', f.field_name;
            end if;
        end loop;
    end;
$$ language plpgsql;


create function def.require_one(fields public.hstore, required_fields text[]) returns void as $$
    declare
        f record;

    begin
        -- hstore needs this
        set local search_path=public,def;
        for f in select unnest(required_fields) as field_name loop
            if (fields->f.field_name) is not null then
                return;
            end if;
        end loop;

        raise exception 'One of the fields % is required.', required_fields;
    end;
$$ language plpgsql;
