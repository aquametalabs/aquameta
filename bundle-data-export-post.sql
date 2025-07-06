delete from bundle.blob;
delete from bundle.repository;
delete from bundle.ignored_schema;
delete from bundle.ignored_table;

\i bundle-data-export.sql

delete from bundle.ignored_schema;
delete from bundle.ignored_table;

select bundle.checkout(name) from repository;

