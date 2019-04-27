/*******************************************************************************
 * Semantics
 * A space to decorate the db schema with meaning
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/*
column_purpose
---------------------
new_field
grid_field_display
form_edit
grid_display
grid_label
form_field
form_display
grid_view_label
grid_edit
grid_field_edit
form_label
form_field_edit uuid
form_field_display
form_field_label

                column_id                 |  purpose   |      widget_name
------------------------------------------+------------+-----------------------
 ("(""(endpoint)"",resource)",content)    | form_field | form_field_html
 ("(""(endpoint)"",template)",content)    | form_field | form_field_html
 ("(""(endpoint)"",template_route)",args) | form_field | form_field_javascript
 ("(""(widget)"",dependency_js)",content) | form_field | form_field_javascript
 ("(""(widget)"",widget)",common_js)      | form_field | form_field_javascript
 ("(""(widget)"",widget)",css)            | form_field | form_field_css
 ("(""(widget)"",widget)",html)           | form_field | form_field_html
 ("(""(widget)"",widget)",post_js)        | form_field | form_field_javascript
 ("(""(widget)"",widget)",pre_js)         | form_field | form_field_javascript
 ("(""(widget)"",widget)",server_js)      | form_field | form_field_javascript

relation_purpose
----------------
grid_row
grid_view
row_detail
text_identifier
list_item
list_view
new_row


       relation_id       |     purpose     | widget_name
-------------------------+-----------------+---------------------------------------------
 ("(endpoint)",resource) | row_detail      | row_detail_resource
 ("(endpoint)",template) | row_detail      | row_detail_template
 ("(widget)",widget)     | text_identifier | semantics_widget_widget_listitem_identifier
 ("(widget)",widget)     | row_detail      | row_detail_widget
 ("(widget)",widget)     | row_detail      | row_detail_widget
*/

set search_path=semantics;

create table semantics.relation_purpose (
    id uuid not null default public.uuid_generate_v4() primary key,
    purpose text not null
);

create table semantics.relation (
    id uuid not null default public.uuid_generate_v4() primary key,
    relation_id meta.relation_id not null,
    purpose_id uuid references semantics.relation_purpose(id) not null,
    widget_id uuid references widget.widget(id) not null,
    priority integer not null default 0
);

/*
moved to bundle....
insert into semantics.relation_purpose (purpose) values
    ('overview'),
    ('list_view'),
    ('list_item'),
    ('row_detail'),
    ('new_row'),
    ('grid_view'),
    ('grid_row');
*/


create table semantics.column_purpose (
    id uuid not null default public.uuid_generate_v4() primary key,
    purpose text not null
);

create table semantics."type" (
    id uuid not null default public.uuid_generate_v4() primary key,
    type_id meta.type_id,
    purpose_id uuid references semantics.column_purpose(id) not null,
    widget_id uuid references widget.widget(id) not null,
    priority integer not null default 0
);

create table semantics."column" (
    id uuid not null default public.uuid_generate_v4() primary key,
    column_id meta.column_id,
    purpose_id uuid references semantics.column_purpose(id) not null,
    widget_id uuid references widget.widget(id) not null,
    priority integer not null default 0
);


/*
moved to bundle

insert into semantics.column_purpose (purpose) values
    ('new_field'),
    ('form_field'),
    ('form_label'),
    ('form_display'),
    ('form_edit'),
    ('grid_label'),
    ('grid_display'),
    ('grid_edit');
*/


create table semantics.foreign_key (
    id uuid not null default public.uuid_generate_v4() primary key,
    foreign_key_id meta.foreign_key_id,
    inline boolean default false
);


/*
 * semantics.relation_widget()
 *
 * first look for a widget specifically for this relation.
 * second, fall back to a widget with the same name as the specified purpose.
 *
 */
create or replace function semantics.relation_widget (
    relation_id meta.relation_id,
    widget_purpose text,
    default_bundle text
) returns setof widget.widget as
$$
begin
    return query execute 'select ' || (
        select string_agg(name, ', ' order by position)
        from meta.column
        where schema_name='widget'
            and relation_name='widget' ) ||
    ' from (
        select w.*, r.priority
        from semantics.relation r
            join semantics.relation_purpose rp on rp.id = r.purpose_id
            join widget.widget w on w.id = r.widget_id
        where r.relation_id = meta.relation_id(' || quote_literal((relation_id::meta.schema_id).name) || ', ' || quote_literal((relation_id).name) || ')
            and rp.purpose = ' || quote_literal(widget_purpose) ||
        'union
        select *, -1 as priority from widget.bundled_widget(' || quote_literal(default_bundle) || ', ' || quote_literal(widget_purpose) || ')
    ) a
    order by priority desc
    limit 1';
end;
$$ language plpgsql;


/*
 * semantics.relation_widget()
 *
 * first look for a widget specifically for this column.
 * second, look for a widget specifically for this column's type.
 * third, fall back to a widget with the same name as the specified purpose.
 *
 */
create or replace function semantics.column_widget (
    column_id meta.column_id,
    widget_purpose text,
    default_bundle text
) returns setof widget.widget as
$$
begin
    return query execute 'select ' || (
        select string_agg(name, ', ' order by position)
        from meta.column
        where schema_name='widget'
            and relation_name='widget' ) ||
    ' from (
        select w.*, c.priority, ''c'' as type
        from semantics.column c
            join semantics.column_purpose cp on cp.id = c.purpose_id
            join widget.widget w on w.id = c.widget_id
        where c.column_id = meta.column_id(' || quote_literal((column_id::meta.schema_id).name) || ', ' ||
                                         quote_literal((column_id::meta.relation_id).name) || ', ' ||
                                         quote_literal((column_id).name) || ')
            and cp.purpose = ' || quote_literal(widget_purpose) ||
        ' union
        select w.*, t.priority, ''t'' as type
        from semantics.type t
            join semantics.column_purpose cp on cp.id = t.purpose_id
            join widget.widget w on w.id = t.widget_id
            join meta.column mc on mc.type_id = t.type_id
        where mc.id = meta.column_id(' || quote_literal((column_id::meta.schema_id).name) || ', ' ||
                                         quote_literal((column_id::meta.relation_id).name) || ', ' ||
                                         quote_literal((column_id).name) || ')
            and cp.purpose = ' || quote_literal(widget_purpose) ||
        ' union
        select *, -1 as priority, ''z'' as type
        from widget.bundled_widget(' || quote_literal(default_bundle) || ', ' || quote_literal(widget_purpose) || ')
    ) a
    order by type asc, priority desc
    limit 1';
end;
$$ language plpgsql;



/*
 * some convenience views
 *
 */

create or replace view type_summary as
select
    t.type_id,
    cp.id as column_purpose_id,
    cp.purpose,
    w.id as widget_id,
    w.name as widget_name
from semantics.type t
    join semantics.column_purpose cp on t.purpose_id = cp.id
    join widget.widget w on t.widget_id = w.id;



create view column_summary as
select
    c.id as column_id,
    cp.id as column_purpose_id,
    cp.purpose,
    w.id as widget_id,
    w.name as widget_name
from meta.column c
    join semantics.column sc on c.id = sc.column_id
    join semantics.column_purpose cp on sc.purpose_id = cp.id
    join widget.widget w on sc.widget_id = w.id;



create view relation_summary as
select
    c.id as relation_id,
    cp.id as relation_purpose_id,
    cp.purpose,
    w.id as widget_id,
    w.name as widget_name
from meta.relation c
    join semantics.relation sc on c.id = sc.relation_id
    join semantics.relation_purpose cp on sc.purpose_id = cp.id
    join widget.widget w on sc.widget_id = w.id;
