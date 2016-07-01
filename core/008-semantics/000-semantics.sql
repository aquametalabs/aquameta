/*******************************************************************************
 * Semantics
 * A space to decorate the db schema with meaning
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;

create schema semantics;
set search_path=semantics;

create table semantics.semantic_relation_purpose (
    id uuid primary key default public.uuid_generate_v4(),
    purpose text not null
);

create table semantics.semantic_relation (
    id meta.relation_id primary key,
    purpose_id uuid references semantics.semantic_relation_purpose(id),
    widget_id uuid references widget.widget(id) not null,
    priority integer not null default 0
);

insert into semantics.semantic_relation_purpose (purpose) values 
    -- Old
    ('list_item_identifier'),
    ('grid_view_row'),

    -- Keepers
    ('overview'),
    ('list_view'),
    ('list_item'),
    ('row_detail'),
    ('new_row'),
    ('grid_view'),
    ('grid_row');


create table semantics.semantic_column_purpose (
    id uuid primary key default public.uuid_generate_v4(),
    purpose text not null
);

create table semantics.semantic_type (
    id meta.type_id primary key,
    purpose_id uuid references semantics.semantic_column_purpose(id) not null,
    widget_id uuid references widget.widget(id) not null,
    priority integer not null default 0
);

-- Breaking changes
create table semantics.semantic_column (
    id meta.column_id primary key,
    purpose_id uuid references semantics.semantic_column_purpose(id) not null,
    widget_id uuid references widget.widget(id) not null,
    priority integer not null default 0
);


insert into semantics.semantic_column_purpose (purpose) values
    -- Old
    ('form_field_label'),
    ('form_field_display'),
    ('form_field_edit uuid'),
    ('grid_view_label'),
    ('grid_field_display'),
    ('grid_field_edit'),

    -- Keepers
    ('form_field'),
    ('form_label'),
    ('form_display'),
    ('form_edit'),
    ('grid_label'),
    ('grid_display'),
    ('grid_edit');

create table semantics.foreign_key (
    id meta.foreign_key_id primary key,
    inline boolean default false
);




/*
 *
 *  Function thate returns display, edit, and new widget names for a given column
 *
 */
drop type if exists column_widgets cascade;
create type column_widgets as (
    display_widget_name text,
    edit_widget_name text,
    new_widget_name text
);
create or replace function semantics.column_semantics(schema text, relation text, column_name text)
returns semantics.column_widgets as $$

declare
    r semantics.column_widgets;
begin

with column_widgets as (
    select *
    from unnest(array['display', 'edit', 'new'], (

        select array[sc.display_widget_id, sc.edit_widget_id, sc.new_widget_id]
        from semantics."column" sc
        where (sc.id::meta.schema_id).name = schema
        and (sc.id::meta.relation_id).name = relation
        and (sc.id).name = column_name
        )

    ) as t(widget_use, widget_id)

), type_widgets as (
    select *
    from unnest(array['display', 'edit', 'new'], (

        select array[st.display_widget_id,  st.edit_widget_id, st.new_widget_id]
        from semantics.type st
            join meta."column" mc on mc.type_id = st.id
        where mc.schema_name = schema
        and mc.relation_name = relation
        and mc.name = column_name
        )

    ) as t(widget_use, widget_id)

), widgets as (
    select distinct on (r.widget_use) r.widget_use, w.name
    from (
        select * from column_widgets
        union all
        select * from type_widgets
    ) r
        join widget.widget w on w.id = r.widget_id
    where r.widget_id is not null
)

select
    ( select name from widgets where widget_use = 'display')::text,
    ( select name from widgets where widget_use = 'edit')::text,
    ( select name from widgets where widget_use = 'new')::text
into r;

return r;

end

$$ language plpgsql;



create or replace function semantics.relation_widget (
    relation_id meta.relation_id,
    widget_purpose text,
    bundle_names text[],
    default_bundle text,
    out bundle_name text,
    out widget_name text
) as
$$

    declare
        column_name text;
        widget_id uuid;

    begin
        -- Find all the possible widgets referenced in semantics for this relation and purpose
        with possible_widgets as (
            select w.id, w.name, r.priority
            from semantics.semantic_relation r
                join semantics.semantic_relation_purpose rp on rp.id = r.purpose_id
                join widget.widget w on w.id = r.widget_id
            where r.id = relation_id
                and rp.purpose = widget_purpose
        )

        -- Get the bundle its from
        select r.bundle_name, r.widget_name
        from (

            -- Committed widgets
            select b.name as bundle_name, pw.name as widget_name, pw.priority
            from bundle.bundle b
                join bundle.commit c on c.id = b.head_commit_id
                join bundle.rowset r on r.commit_id = c.id
                join bundle.rowset_row rr on rr.rowset_id = r.id
                join possible_widgets pw on pw.id = (rr.row_id).pk_value::uuid
            where b.name = any( bundle_names )
                and rr.row_id::meta.relation_id = meta.relation_id('widget','widget')

            union

            -- Staged widgets
            select b.name as bundle_name, pw.name as widget_name, pw.priority
            from bundle.bundle b
                join bundle.stage_row_added sra on sra.bundle_id = b.id
                join possible_widgets pw on pw.id = (sra.row_id).pk_value::uuid
            where b.name = any( bundle_names )
                and sra.row_id::meta.relation_id = meta.relation_id('widget','widget')

            union

            -- Default widget
            select default_bundle as bundle_name, widget_purpose as widget_name, 0 as priority
        ) r
        order by r.priority desc
        limit 1
        into bundle_name, widget_name;

    end;
$$ language plpgsql;



create or replace function semantics.column_widget (
    column_id meta.column_id,
    widget_purpose text,
    bundle_names text[],
    default_bundle text,
    out bundle_name text,
    out widget_name text
) as
$$

    declare
        column_name text;
        widget_id uuid;

    begin
        -- Find all the possible widgets referenced in semantics for this column or type and purpose
        with possible_widgets as (
            select w.id, w.name, r.priority, 'column' as column_or_type
            from semantics.semantic_column c
                join semantics.semantic_column_purpose cp on cp.id = c.purpose_id
                join widget.widget w on w.id = c.widget_id
            where c.id = column_id
                and cp.purpose = widget_purpose

            union

            select w.id, w.name, r.priority, 'type' as column_or_type
            from semantics.semantic_type t
                join semantics.semantic_column_purpose cp on cp.id = t.purpose_id
                join widget.widget w on w.id = t.widget_id
            where t.id = (select type_id from meta.column where id = column_id)
                and cp.purpose = widget_purpose
        )

        -- Get the bundle its from
        select r.bundle_name, r.widget_name
        from (

            -- Committed widgets
            select b.name as bundle_name, pw.name as widget_name, pw.priority, pw.col_or_type
            from bundle.bundle b
                join bundle.commit c on c.id = b.head_commit_id
                join bundle.rowset r on r.commit_id = c.id
                join bundle.rowset_row rr on rr.rowset_id = r.id
                join possible_widgets pw on pw.id = (rr.row_id).pk_value::uuid
            where b.name = any( bundle_names )
                and rr.row_id::meta.relation_id = meta.relation_id('widget','widget')

            union

            -- Staged widgets
            select b.name as bundle_name, pw.name as widget_name, pw.priority, pw.col_or_type
            from bundle.bundle b
                join bundle.stage_row_added sra on sra.bundle_id = b.id
                join possible_widgets pw on pw.id = (sra.row_id).pk_value::uuid
            where b.name = any( bundle_names )
                and sra.row_id::meta.relation_id = meta.relation_id('widget','widget')

            union

            -- Default widget
            select default_bundle as bundle_name, widget_purpose as widget_name, 0 as priority, 'z' as col_or_type
        ) r
        order by col_or_type asc, r.priority desc
        limit 1
        into bundle_name, widget_name;

    end;
$$ language plpgsql;


commit;
