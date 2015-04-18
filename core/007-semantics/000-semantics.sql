/*******************************************************************************
 * Semantics
 * A space to decorate the db schema with meaning
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;

drop schema if exists semantics cascade;
create schema semantics;
set search_path=semantics;

create table semantics.type (
    id meta.type_id primary key,
    /*
    -- value_generator text default 'field.get("value")', -- for complex types
    display boolean default true,
    display_widget_id uuid references widget.widget(id),
    edit_widget_id uuid references widget.widget(id),
    new_widget_id uuid references widget.widget(id)
    */
    form_field_widget_id uuid references widget.widget(id),
    form_field_label_widget_id uuid references widget.widget(id),
    form_field_display_widget_id uuid references widget.widget(id),
    form_field_edit_widget_id uuid references widget.widget(id),
    grid_view_label_widget_id uuid references widget.widget(id),
    grid_field_display_widget_id uuid references widget.widget(id),
    grid_field_edit_widget_id uuid references widget.widget(id)

);

create table semantics.relation (
    id meta.relation_id primary key,
    /*
    identifier_icon_widget_id uuid references widget.widget(id),
    identifier_listitem_widget_id uuid references widget.widget(id),
    display_widget_id uuid references widget.widget(id),
    edit_widget_id uuid references widget.widget(id),
    new_widget_id uuid references widget.widget(id)
    */


    overview_widget_id uuid references widget.widget(id),
    grid_view_widget_id uuid references widget.widget(id),
    list_view_widget_id uuid references widget.widget(id),
    list_item_identifier_widget_id uuid references widget.widget(id),
    row_detail_widget_id uuid references widget.widget(id),
    grid_view_row_widget_id uuid references widget.widget(id),
    new_row_widget_id uuid references widget.widget(id)
);

/*
create view semantics.relation_identifier_listitem_widget as 
select sr.id, mr.schema_name, mr.name as relation_name, w.name as widget_name from semantics.relation sr 
    join meta.relation mr on sr.id=mr.id
    join widget.widget w on sr.identifier_listitem_widget_id = w.id
    ;


*/








create table semantics."column" (
    id meta.column_id primary key,
    /*
    human_name text,
    display boolean,
    -- previous_column references column(id), -- TODO: column order in table
    display_widget_id uuid references widget.widget(id),
    edit_widget_id uuid references widget.widget(id),
    new_widget_id uuid references widget.widget(id)
    */

    form_field_widget_id uuid references widget.widget(id),
    form_field_label_widget_id uuid references widget.widget(id),
    form_field_display_widget_id uuid references widget.widget(id),
    form_field_edit_widget_id uuid references widget.widget(id),
    grid_view_label_widget_id uuid references widget.widget(id),
    grid_field_display_widget_id uuid references widget.widget(id),
    grid_field_edit_widget_id uuid references widget.widget(id)
);

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




/*
 *
 * Semantics will eventually need to be populated with data on install
 *
 */

------------------------------
--------- TEST DATA ----------
------------------------------



------------------------------
--------- TYPES --------------
------------------------------

/*
TODO: maybe refactor this to match the new system
--all booleans fields displayed and editable
insert into semantics.type (id, display, display_widget_id) values (meta.type_id('pg_catalog', 'bool'), true, (select id from widget.widget where name = 'dev_field_boolean_editable'));
--all text fields displayed and editable
insert into semantics.type (id, display, display_widget_id) values (meta.type_id('pg_catalog', 'text'), true, (select id from widget.widget where name = 'dev_field_editable'));
insert into semantics.type (id, display, display_widget_id) values (meta.type_id('pg_catalog', 'int4'), true, (select id from widget.widget where name = 'dev_field_editable'));
insert into semantics.type (id, display, display_widget_id) values (meta.type_id('pg_catalog', 'float8'), true, (select id from widget.widget where name = 'dev_field_editable'));
insert into semantics.type (id, display, display_widget_id) values (meta.type_id('pg_catalog', 'varchar'), true, (select id from widget.widget where name = 'dev_field_editable'));
insert into semantics.type (id, display, display_widget_id) values (meta.type_id('pg_catalog', 'timestamptz'), true, (select id from widget.widget where name = 'dev_field_editable'));
*/

------------------------------
--------- COLUMNS ------------
------------------------------
--all meta tables displayed but not editable
/*
TODO: maybe refactor this to match the new system
insert into semantics."column" (id, human_name, display) select id, name, 'true' from meta."column" where schema_name='meta';
insert into semantics."column" (id, human_name, display) select id, name, 'false' from meta."column" where schema_name='pg_catalog';



insert into relation (id, identifier_listitem_widget_id) values (meta.relation_id('www','resource'), (select id from widget.widget where name='semantics_www_resource_listitem_identifier'));
insert into relation (id, identifier_listitem_widget_id) values (meta.relation_id('www','mimetype'), (select id from widget.widget where name='semantics_mimetype_listitem_identifier'));
insert into relation (id, identifier_listitem_widget_id) values (meta.relation_id('widget','widget'), (select id from widget.widget where name='semantics_widget_widget_listitem_identifier'));

------------------------------
--------- COLUMNS ------------
------------------------------



--insert into semantics."column" (id, human_name, display) select id, name, 'true' from meta."column" where schema_name='meta';
--insert into semantics."column" (id, human_name, display) select id, name, 'false' from meta."column" where schema_name='pg_catalog';
*/



commit;
