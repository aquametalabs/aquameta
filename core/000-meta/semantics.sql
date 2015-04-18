/*******************************************************************************
 * Meta Semantics
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

set search_path=semantics;

insert into semantics.relation (id, list_item_identifier_widget_id) values
(
    ( select relation_id from meta.relation_id('meta', 'schema') ),
    ( select id from widget.widget where name = 'meta_schema_listitem_identifier')
);

insert into semantics.relation (id, list_item_identifier_widget_id) values
(
    ( select relation_id from meta.relation_id('meta', 'relation') ),
    ( select id from widget.widget where name = 'relation_listitem_identifier')
);

insert into semantics.relation (id, list_item_identifier_widget_id) values
(
    ( select relation_id from meta.relation_id('meta', 'column') ),
    ( select id from widget.widget where name = 'column_listitem_identifier')
);

commit;
