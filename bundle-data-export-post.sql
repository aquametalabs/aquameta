delete from bundle.blob;
delete from bundle.repository;
delete from bundle.ignored_schema;
delete from bundle.ignored_table;

\i bundle-data-export.sql


select bundle.checkout('org.aquameta.core.mimetypes');
select bundle.checkout('org.aquameta.core.endpoint');
select bundle.checkout('org.aquameta.core.widget');
select bundle.checkout('org.aquameta.core.ide');
select bundle.checkout('org.aquameta.ui.bundle');
select bundle.checkout('org.aquameta.ui.editor');

