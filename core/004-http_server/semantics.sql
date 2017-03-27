/*******************************************************************************
 * WWW - Semantics
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

set search_path = semantics;

insert into semantics.relation (relation_id, widget_id) values
(
    ( select relation_id from meta.relation_id('www', 'resource') ),
    ( select id from widget.widget where name = 'www_resource_listitem_identifier')
);

insert into semantics.relation (relation_id, widget_id) values
(
    ( select relation_id from meta.relation_id('www', 'mimetype') ),
    ( select id from widget.widget where name = 'www_mimetype_listitem_identifier')
);

commit;
