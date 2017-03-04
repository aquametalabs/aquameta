/*******************************************************************************
 * Semantics Semantics
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
begin;

set search_path=semantics;

/*

doesn't work:

ERROR:  column "list_item_identifier_widget_id" of relation "relation" does not exist
LINE 1: insert into semantics.relation (id, list_item_identifier_wid...




insert into semantics.relation (id, list_item_identifier_widget_id) values
(
    ( select relation_id from meta.relation_id('semantics', 'relation') ),
    ( select id from widget.widget where name = 'relation_listitem_identifier')
);

insert into semantics.relation (id, list_item_identifier_widget_id) values
(
    ( select relation_id from meta.relation_id('semantics', 'column') ),
    ( select id from widget.widget where name = 'column_listitem_identifier')
);

*/ 
commit;
