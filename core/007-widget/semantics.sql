/*******************************************************************************
 * Widget - Semantics
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

set search_path=semantics;

insert into semantics.relation (relation_id, widget_id) values
(
    ( select relation_id from meta.relation_id('widget', 'widget') ),
    ( select id from widget.widget where name = 'widget_widget_listitem_identifier')
);

commit;
