/*******************************************************************************
 * Documentation
 * General Purpose Documentation System 
 * 
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

set search_path=documentation;


------------------------------------------------------------------------------
-- 1. DDL Documentation
-- These are for documenting database objects, like schemas, tables, views,
-- functions, etc.
------------------------------------------------------------------------------

/*
create table "schema" (
    id uuid not null default public.uuid_generate_v4() primary key,
    schema_id meta.schema_id not null,
    content text not null default ''
);

create table "table" (
    id uuid not null default public.uuid_generate_v4() primary key,
    relation_id meta.relation_id not null,
    content text not null default ''
);

*/

create table bundle_doc (
    id uuid not null default public.uuid_generate_v4() primary key,
    bundle_id uuid references bundle.bundle(id),
    title text not null default '',
    content text not null default ''
);

create table row_doc (
    id uuid not null default public.uuid_generate_v4() primary key,
    row_id meta.row_id not null,
    title text not null default '',
    content text not null default ''
);
