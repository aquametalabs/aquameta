delete from bundle.blob;
delete from bundle.repository;
delete from bundle.ignored_schema;
delete from bundle.ignored_table;

\i bundle-data-export.sql

delete from bundle.ignored_schema;
delete from bundle.ignored_table;


select bundle.checkout('io.bundle.core.repository');
select bundle.checkout('org.aquameta.core.mimetypes');
select bundle.checkout('org.aquameta.core.endpoint');
select bundle.checkout('org.aquameta.core.widget');
select bundle.checkout('org.aquameta.core.ide');
select bundle.checkout('org.aquameta.core.semantics');
select bundle.checkout('org.aquameta.ui.bundle');
select bundle.checkout('org.aquameta.ui.editor');
select bundle.checkout('org.aquameta.ui.fsm');
select bundle.checkout('org.aquameta.ui.layout');
select bundle.checkout('org.aquameta.ui.tags');
select bundle.checkout('org.aquameta.core.bootloader');
select bundle.checkout('org.aquameta.games.snake');
