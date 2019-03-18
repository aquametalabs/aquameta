Meta: A writable system catalog extension for PostgreSQL
========================================================

This extension provides two facilities:

1. A set of "meta-identifiers" for unambiguously referencing database objects like tables, views, schemas, roles, etc.
2. A writable system catalog that makes DDL operations accessible via DML operations, allowing PostgreSQL administration via INSERT, UPDATE and DELETE.  It is similar in function to `pg_catalog`, but is updatable and is laid out more sensibly.

INSTALL
-------

Install the extension into PostgreSQL's `extension/` directory:
```shell
make install
```

From a PostgreSQL shell, install meta's required extensions:
```sql
CREATE EXTENSION hstore SCHEMA public;
CREATE EXTENSION [pg_catalog_get_defs](https://github.com/aquametalabs/aquameta/tree/master/src/pg-extension/pg_catalog_get_defs) SCHEMA pg_catalog;
```

Finally, install the meta extension:
```sql
CREATE EXTENSION meta;
```

USAGE
-----

### Schema
```sql
insert into meta.schema (name) values ('bookstore');
update meta.schema set name = 'book_store' where name = 'bookstore';
delete from meta.schema where name = 'book_store';
```
### Table
```sql
insert into meta.table (schema, name) values ('bookstore', 'book');
update meta.table set name = 'books' where schema = 'bookstore' and name = 'book';
delete from meta.table where name = 'books';
```
### Column
```sql
insert into meta.column (schema, "table", name, type, nullable)
values ('bookstore', 'book', 'price', 'numeric', false);

update meta.column set "default" = 0
where schema = 'bookstore' and "table" = 'book' and name = 'price';
-- or alternatively
update meta.column set "default" = 0
where id = ('bookstore', 'book', 'price')::meta.column_id;

delete from meta.column where id = ('bookstore', 'book', 'price')::meta.column_id;
```
### View
```sql
insert into meta.view (schema, name, query)
values ('bookstore', 'inexpensive_books', 'select * from bookstore.book where price < 5;');

update meta.view
set query = 'select * from bookstore.book where price < 10;'
where id = ('bookstore', 'inexpensive_books')::meta.view_id;
```
### Check Constraint
```sql
insert into meta.constraint_check (schema, "table", name, "check")
values ('bookstore', 'book', 'min_price', 'price > 1');

update meta.constraint_check
set "check" = 'price > 0.50'
where schema = 'bookstore' and "table" = 'book' and name = 'min_price';
```
### Unique Constraint
```sql
insert into meta.constraint_unique (schema, "table", name, columns)
values ('bookstore', 'book', 'unique_name', array['name']);

update meta.constraint_unique
set columns = array['category_id', 'name']
where schema = 'bookstore' and "table" = 'book' and name = 'unique_name';
```
