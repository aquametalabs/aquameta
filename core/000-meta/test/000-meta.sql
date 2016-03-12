begin;
    set search_path=public,meta;

create extension if not exists pgtap;

select plan(115);


/****************************************************************************************************
 * meta.schema                                                                                      *
 ****************************************************************************************************/

-- insert
insert into meta.schema (name) values ('test_schema');
select has_schema('test_schema');
select ok(
    exists(select 1 from meta.schema where name = 'test_schema'),
    'Inserted schema should appear in meta.schema.'
);

-- update
update meta.schema set name = 'test_schema2' where name = 'test_schema';
select hasnt_schema('test_schema', 'Renamed schema''s old name should not exist.');
select has_schema('test_schema2', 'Renamed schema''s new name should exist.');

-- delete
delete from meta.schema where name = 'test_schema2';
select hasnt_schema('test_schema2');
select ok(
    not exists(select 1 from meta.schema where name = 'test_schema2'),
    'Deleted schema shouldn''t appear in meta.schema.'
);


/****************************************************************************************************
 * meta.sequence                                                                                    *
 ****************************************************************************************************/

insert into meta.sequence (schema_id, name, start_value, minimum_value, maximum_value, increment, cycle)
values (meta.schema_id('public'), 'test_seq_1', 1, 1, 100, 1, false);
select has_sequence('public', 'test_seq_1', 'Sequence inserted with schema_id should exist.');

update meta.sequence set name = 'test_seq_2'
where schema_name = 'public' and name = 'test_seq_1';
select hasnt_sequence('public', 'test_seq_1', 'Sequence renamed: old name should not exist.');
select has_sequence('public', 'test_seq_2', 'Sequence renamed: new name should exist.');

delete from meta.sequence where schema_name = 'public' and name = 'test_seq_2';
select hasnt_sequence('public', 'test_seq_2', 'Sequence deleted: should not exist.');


/****************************************************************************************************
 * meta.table                                                                                       *
 ****************************************************************************************************/

create schema test_schema;

-- insert with schema_id
insert into meta.table (schema_id, name) values (row('public')::meta.schema_id, 'test_people');
select has_table('public', 'test_people', 'Table inserted with schema_id should exist.');
select ok(
    exists(select 1 from meta.table where id = row(row('public'), 'test_people')::meta.relation_id),
    'Table inserted with schema_id should appear in meta.table.'
);

-- insert with schema_name
insert into meta.table (schema_name, name) values ('public', 'test_places');
select has_table('public', 'test_places', 'Table inserted with schema_name should exist.');
select ok(
    exists(select 1 from meta.table where id = row(row('public'), 'test_places')::meta.relation_id),
    'Table inserted with schema_name should appear in meta.table.'
);

-- set schema with schema_id
update meta.table set schema_id = row('test_schema')::meta.schema_id where id = row(row('public'), 'test_places')::meta.relation_id;
select hasnt_table('public', 'test_places', 'Table with schema changed via schema_id: old name should not exist.');
select has_table('test_schema', 'test_places', 'Table with schema changed via schema_id: new name should exist.');

-- set schema with schema_name
update meta.table set schema_name = 'public' where id = row(row('test_schema'), 'test_places')::meta.relation_id;
select hasnt_table('test_schema', 'test_places', 'Table with schema changed via schema_name: old name should not exist.');
select has_table('public', 'test_places', 'Table with schema changed via schema_name: new name should exist.');

-- rename
update meta.table set name = 'test_people2' where name = 'test_people';
select hasnt_table('public', 'test_people', 'Renamed table''s old name should not exist.');
select has_table('public', 'test_people2', 'Renamed table''s new name should exist.');

-- delete 
delete from meta.table where id = row(row('public'), 'test_places')::meta.relation_id;
select hasnt_table('public', 'test_places');


/****************************************************************************************************
 * meta.view                                                                                        *
 ****************************************************************************************************/

-- insert with schema_id
insert into meta.view (schema_id, name, query) values (row('public')::meta.schema_id, 'test_view1', 'select 1');
select has_view('public', 'test_view1', 'View inserted with schema_id should exist.');
select ok(
    exists(select 1 from meta.view where id = row(row('public'), 'test_view1')::meta.relation_id),
    'View inserted with schema_id should appear in meta.view.'
);
select ok(
    exists(select 1 from public.test_view1),
    'View inserted with schema_id should be queryable.'
);

-- insert with schema_name
insert into meta.view (schema_name, name, query) values ('public', 'test_view2', 'select 2');
select has_view('public', 'test_view2', 'View inserted with schema_name should exist.');
select ok(
    exists(select 1 from meta.view where id = row(row('public'), 'test_view2')::meta.relation_id),
    'View inserted with schema_name should appear in meta.view.'
);
select ok(
    exists(select 1 from public.test_view2),
    'View inserted with schema_name should be queryable.'
);

-- set schema with schema_id
update meta.view set schema_id = row('test_schema')::meta.schema_id where id = row(row('public'), 'test_view1')::meta.relation_id;
select hasnt_view('public', 'test_view1', 'View with schema changed via schema_id: old name should not exist.');
select has_view('test_schema', 'test_view1', 'View with schema changed via schema_id: new name should exist.');

-- set schema with schema_name
update meta.view set schema_name = 'public' where id = row(row('test_schema'), 'test_view1')::meta.relation_id;
select hasnt_view('test_schema', 'test_view1', 'View with schema changed via schema_name: old name should not exist.');
select has_view('public', 'test_view1', 'View with schema changed via schema_name: new name should exist.');

-- rename
update meta.view set name = 'test_view3' where name = 'test_view2';
select hasnt_view('public', 'test_view2', 'Renamed view''s old name should not exist.');
select has_view('public', 'test_view3', 'Renamed view''s new name should exist.');

-- delete 
delete from meta.view where id = row(row('public'), 'test_view1')::meta.relation_id;
select hasnt_view('public', 'test_view1', 'View deleted should not exist.');


/****************************************************************************************************
 * meta.column                                                                                      *
 ****************************************************************************************************/

create table test_schema.people();

-- insert with relation_id
insert into meta.column (relation_id, name, "type_name") values (row(row('test_schema'), 'people')::meta.relation_id, 'name', 'text');
select has_column('test_schema', 'people', 'name', 'Column inserted with relation_id should exist.');
select col_type_is('test_schema', 'people', 'name', 'text', 'Column inserted with type text should have type text.');
select ok(
    exists(select 1 from meta.column where id = row(row(row('test_schema'), 'people'), 'name')::meta.column_id),
    'Column inserted with relation_id should appear in meta.column.'
);

-- insert with schema_name and relation_name
insert into meta.column (schema_name, relation_name, name, "type_name") values ('test_schema', 'people', 'age', 'integer');
select has_column('test_schema', 'people', 'age', 'Column inserted with schema_name and relation_name should exist.');
select ok(
    exists(select 1 from meta.column where id = row(row(row('test_schema'), 'people'), 'name')::meta.column_id),
    'Column inserted with schema_name and relation_name should appear in meta.column.'
);
select col_hasnt_default('test_schema', 'people', 'age', 'Column inserted without default should not have default.');
select col_isnt_pk('test_schema', 'people', 'age', 'Column inserted without primary_key true should not be primary key.');

-- insert primary key
insert into meta.column (schema_name, relation_name, name, "type_name", primary_key) values ('test_schema', 'people', 'id', 'integer', true);
select col_is_pk('test_schema', 'people', 'id', 'Column inserted with primary_key true should be primary key.');

-- insert nullable, default
insert into meta.column (schema_name, relation_name, name, "type_name", "nullable", "default") values ('test_schema', 'people', 'rating', 'integer', false, 0);
select col_not_null('test_schema', 'people', 'rating', 'Column inserted with nullable false should be not null.');
select col_has_default('test_schema', 'people', 'rating', 'Column inserted with default should have default.');
select col_default_is('test_schema', 'people', 'rating', 0, 'Column inserted with default 0 should have default 0.');

-- update type, nullable
update meta.column set "type_name" = 'double precision', "nullable" = true where id = row(row(row('test_schema'), 'people'), 'rating')::meta.column_id;
select col_type_is('test_schema', 'people', 'rating', 'double precision', 'Column type updated should have new type.');
select col_is_null('test_schema', 'people', 'rating', 'Column nullable updated to true should be nullable.');

-- update null default, nullable false
update meta.column set "default" = null, "nullable" = false where id = row(row(row('test_schema'), 'people'), 'rating')::meta.column_id;
select col_not_null('test_schema', 'people', 'rating', 'Column nullable updated to false should be not null.');
select col_hasnt_default('test_schema', 'people', 'rating', 'Column update with null default should not have default.');

-- rename
update meta.column set name = 'score' where id = row(row(row('test_schema'), 'people'), 'rating')::meta.column_id;
select hasnt_column('test_schema', 'people', 'rating', 'Column updated with new name: old name should not exist.');
select has_column('test_schema', 'people', 'score', 'Column updated with new name: new name should exist.');

-- delete
delete from meta.column where id = row(row(row('test_schema'), 'people'), 'score')::meta.column_id;
select hasnt_column('test_schema', 'people', 'score', 'Column deleted should not exist.');


/****************************************************************************************************
 * VIEW meta.foreign_key                                                                            *
 ****************************************************************************************************/

create table test_schema.pirates (
    id serial primary key,
    name text not null,
    ship_id integer not null,
    ship_id2 integer not null
);

create table test_schema.ships (
    id serial primary key,
    name text not null
);

create table test_schema.dinghies (
    id serial primary key,
    name text not null
);

-- insert with table_id
insert into meta.foreign_key (table_id, name, from_column_ids, to_column_ids, on_update, on_delete)
values (
    row(row('test_schema'), 'pirates')::meta.relation_id,
    'pirate_ship_fk',
    array[row(row(row('test_schema'), 'pirates'), 'ship_id')::meta.column_id],
    array[row(row(row('test_schema'), 'ships'), 'id')::meta.column_id],
    'cascade',
    'restrict'
);
select ok(
    exists(select 1 from meta.foreign_key where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk')::meta.foreign_key_id),
    'Foreign key inserted with table_id should exist in meta.foreign_key.'
);
select fk_ok('test_schema', 'pirates', 'ship_id', 'test_schema', 'ships', 'id', 'Inserted foreign key''s columns should be part of a foreign key.');

-- insert with schema_name and table_name
insert into meta.foreign_key (schema_name, table_name, name, from_column_ids, to_column_ids, on_update, on_delete)
values (
    'test_schema',
    'pirates',
    'pirate_ship_fk2',
    array[row(row(row('test_schema'), 'pirates'), 'ship_id')::meta.column_id],
    array[row(row(row('test_schema'), 'ships'), 'id')::meta.column_id],
    'cascade',
    'restrict'
);
select ok(
    exists(select 1 from meta.foreign_key where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk2')::meta.foreign_key_id),
    'Foreign key inserted with schema_name and table_name should exist in meta.foreign_key.'
);

-- update name, from_column_id, to_column_id
update meta.foreign_key set name = 'pirate_ship_fk_two',
                            from_column_ids = array[row(row(row('test_schema'), 'pirates'), 'ship_id2')::meta.column_id],
                            to_column_ids = array[row(row(row('test_schema'), 'dinghies'), 'id')::meta.column_id]
                        where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk2')::meta.foreign_key_id;
select ok(
    not exists(select 1 from meta.foreign_key where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk2')::meta.foreign_key_id),
    'Foreign key updated with new name: old name should not exist.'
);
select ok(
    exists(select 1 from meta.foreign_key where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk_two')::meta.foreign_key_id),
    'Foreign key updated with new name: new name should exist.'
);
select fk_ok('test_schema', 'pirates', 'ship_id2', 'test_schema', 'dinghies', 'id', 'Updated foreign key''s columns should be part of a foreign key.');

-- delete
delete from meta.foreign_key where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk_two')::meta.foreign_key_id;
select ok(
    not exists(select 1 from meta.foreign_key where id = row(row(row('test_schema'), 'pirates'), 'pirate_ship_fk_two')::meta.foreign_key_id),
    'Foreign key deleted: old name should not exist in meta.foreign_key.'
);
select col_isnt_fk('test_schema', 'pirates', 'ship_id2', 'Foreign key deleted: from_column_ids should not be part of a foreign key.');


/****************************************************************************************************
 * VIEW meta.function                                                                               *
 ****************************************************************************************************/

-- insert with schema_id
insert into meta.function (schema_id, name, parameters, definition, return_type, language)
values (row('test_schema')::meta.schema_id, 'add', array['a integer', 'b integer'], 'select a+b', 'integer', 'sql');
select has_function('test_schema', 'add', array['integer', 'integer'], 'Function inserted with schema_id should exist.');
select ok(
    exists(
        select 1 from meta.function
        where id = meta.function_id('test_schema', 'add', array['a integer', 'b integer'])
    ),
    'Function inserted with schema_id should exist in meta.function.'
);
select ok(
    (select test_schema.add(1, 1) = 2),
    'Function inserted with schema_name should be callable.'
);

-- insert with schema_name
insert into meta.function (schema_name, name, parameters, definition, return_type, language)
values ('test_schema', 'subtract', array['a integer', 'b integer'], 'select a-b', 'integer', 'sql');
select has_function('test_schema', 'subtract', array['integer', 'integer'], 'Function inserted with schema_name should exist.');
select ok(
    exists(
        select 1 from meta.function
        where id = meta.function_id('test_schema', 'subtract', array['a integer', 'b integer'])
    ),
    'Function inserted with schema_name should exist in meta.function.'
);
select ok(
    (select test_schema.subtract(1, 1) = 0),
    'Function inserted with schema_name should be callable.'
);

-- update
update meta.function set name = 'sum',
                         parameters = array['x int8', 'y int8'],
                         definition = 'begin return x+y; end;',
                         return_type = 'int8',
                         language = 'plpgsql'
                     where id = meta.function_id('test_schema', 'add', array['a integer', 'b integer']);
select hasnt_function('test_schema', 'add', array['integer', 'integer'], 'Function updated: old function name with old parameters should not exist.');
select has_function('test_schema', 'sum', array['bigint', 'bigint'], 'Function updated: new function name with new parameters should exist.');
select ok(
    exists(select 1 from meta.function where id = row(row('test_schema'), 'sum', array['x bigint', 'y bigint'])::meta.function_id),
    'Function updated: new function name with new parameters should exist in meta.function.'
);
select ok(
    (select test_schema.sum(1, 1) = 2),
    'Function updated: new function should be callable.'
);

-- delete
delete from meta.function where id = row(row('test_schema'), 'sum', array['x bigint', 'y bigint'])::meta.function_id;
select hasnt_function('test_schema', 'sum', array['bigint', 'bigint'], 'Function deleted: old function should not exist.');
select ok(
    not exists(select 1 from meta.function where id = row(row('test_schema'), 'sum', array['a bigint', 'b bigint'])::meta.function_id),
    'Function deleted: old function should not exist in meta.function.'
);


/****************************************************************************************************
 * VIEW meta.trigger                                                                                *
 ****************************************************************************************************/

create function test_schema.ship_bang() returns trigger as $$
    begin
        raise exception 'Bang!';
        return NEW;
    end;
$$ language plpgsql;

create function test_schema.ship_boom() returns trigger as $$
    begin
        raise exception 'Boom!';
        return NEW;
    end;
$$ language plpgsql;

-- insert with relation_id
insert into meta.trigger (relation_id, name, function_id, "when", "insert", "level")
values (row(row('test_schema'), 'ships')::meta.relation_id, 'ship_bang_trig', row(row('test_schema'), 'ship_bang', array[]::text[])::meta.function_id, 'after', true, 'row');
select has_trigger('test_schema', 'ships', 'ship_bang_trig', 'Trigger inserted with relation_id should exist.');
select ok(
    exists(
        select 1 from meta.trigger
        where id = row(row(row('test_schema'), 'ships'), 'ship_bang_trig')::meta.trigger_id
    ),
    'Trigger inserted with relation_id should exist in meta.trigger.'
);
select throws_ok(
    'insert into test_schema.ships (name) values (''Foobar'')',
    'P0001',
    'Bang!',
    'Trigger inserted with relation_id should run on insert into test table.'
);

-- insert with schema_name and relation_name
insert into meta.trigger (schema_name, relation_name, name, function_id, "when", "update", "level")
values ('test_schema', 'ships', 'ship_boom_trig', row(row('test_schema'), 'ship_boom', array[]::text[])::meta.function_id, 'before', true, 'statement');
select has_trigger('test_schema', 'ships', 'ship_boom_trig', 'Trigger inserted with schema_name and relation_name should exist.');
select ok(
    exists(
        select 1 from meta.trigger
        where id = row(row(row('test_schema'), 'ships'), 'ship_boom_trig')::meta.trigger_id
    ),
    'Trigger inserted with schema_name and relation_name should exist in meta.trigger.'
);
select ok(
    exists(
        select 1 from meta.trigger where id = row(row(row('test_schema'), 'ships'), 'ship_boom_trig')::meta.trigger_id and
                                         "when" = 'before' and
                                         "insert" = false and "update" = true and "delete" = false and "truncate" = false and
                                         "level" = 'statement'
    ),
    'Trigger inserted should reflect inserted properties in meta.trigger.'
);
select throws_ok(
    'update test_schema.ships set name = ''Baz'' where name = ''Foobar''',
    'P0001',
    'Boom!',
    'Trigger inserted with schema_name and relation_name should run on insert into test table.'
);

-- update
update meta.trigger set name='ship_bang_trig2',
                        "when"='before',
                        "update"=true,
                        "delete"=true,
                        "truncate"=true,
                        "level"='statement'
                    where id=row(row(row('test_schema'), 'ships'), 'ship_bang_trig')::meta.trigger_id;
select hasnt_trigger('test_schema', 'ships', 'ship_bang_trig', 'Trigger renamed: old name should not exist.');
select has_trigger('test_schema', 'ships', 'ship_bang_trig2', 'Trigger renamed: new name should exist.');

-- delete 
delete from meta.trigger where id = row(row(row('test_schema'), 'ships'), 'ship_boom_trig')::meta.trigger_id;
select hasnt_trigger('test_schema', 'ships', 'ship_boom_trig', 'Trigger deleted: old name should not exist.');
select ok(
    not exists(
        select 1 from meta.trigger
        where id = row(row(row('test_schema'), 'ships'), 'ship_boom_trig')::meta.trigger_id
    ),
    'Trigger deleted: should not exist in meta.trigger.'
);


/****************************************************************************************************
 * VIEW meta.role                                                                                   *
 ****************************************************************************************************/

-- insert name only
insert into meta.role (name) values ('test_user_1');
select has_role('test_user_1', 'Role inserted: should exist.');
select ok(
    exists(
        select 1 from meta.role where id = row('test_user_1')::meta.role_id
    ),
    'Role inserted: should exist in meta.role.'
);
select ok(
    exists(
        -- default val for password is '', default for connection_limit is -1
        select 1 from meta.role where id = row('test_user_1')::meta.role_id and superuser = false and 
                                      inherit = false and create_role = false and create_db = false and
                                      can_login = false and replication = false and connection_limit = -1 and
                                      password = '********' and valid_until is null
    ),
    'Role inserted with name only: should reflect default values in meta.role.'
);

-- insert defaults
insert into meta.role (name, superuser, inherit, create_role, create_db, can_login, replication, connection_limit, password, valid_until)
values ('test_user_2', false, false, false, false, false, false, false, -1, '', null);
select ok(
    exists(
        -- default val for password is '', default for connection_limit is -1
        select 1 from meta.role where id = row('test_user_2')::meta.role_id and superuser = false and 
                                      inherit = false and create_role = false and create_db = false and
                                      can_login = false and replication = false and connection_limit = -1 and
                                      password = '********' and valid_until is null
    ),
    'Role inserted with default values: should reflect inserted values in meta.role.'
);

-- insert with all fields set
insert into meta.role (name, superuser, inherit, create_role, create_db, can_login, replication, connection_limit, password, valid_until)
values ('test_user_3', true, true, true, true, true, true, true, 5, 'foobar', '1997-08-29 02:14:00-07');
select ok(
    exists(
        select 1 from meta.role where id = row('test_user_3')::meta.role_id and superuser = true and 
                                      inherit = true and create_role = true and create_db = true and
                                      can_login = true and replication = true and connection_limit = 5 and
                                      password = '********' and valid_until = '1997-08-29 02:14:00-07'
    ),
    'Role inserted with default values: should reflect inserted values in meta.role.'
);

-- update from defaults to all true
update meta.role set name = 'test_user_4',
                     superuser = true,
                     inherit = true,
                     create_role = true,
                     create_db = true,
                     can_login = true,
                     replication = true,
                     connection_limit = 10,
                     valid_until = '2020-01-01 00:00:00-07'
                 where id = row('test_user_2')::meta.role_id;
select hasnt_role('test_user_2', 'Role renamed: old role name should not exist.');
select has_role('test_user_4', 'Role renamed: new role name should exist.');
select ok(
    exists(
        select 1 from meta.role where id = row('test_user_4')::meta.role_id and superuser = true and 
                                      inherit = true and create_role = true and create_db = true and
                                      can_login = true and replication = true and connection_limit = 10 and
                                      password = '********' and valid_until = '2020-01-01 00:00:00-07'
    ),
    'Role updated with non-default values: should reflect updated values in meta.role.'
);

-- update from defaults to all true/not-null
update meta.role set name = 'test_user_4',
                     superuser = false,
                     inherit = false,
                     create_role = false,
                     create_db = false,
                     can_login = false,
                     replication = false,
                     connection_limit = null,
                     valid_until = '2020-01-01 00:00:00-07'
                 where id = row('test_user_2')::meta.role_id;
select hasnt_role('test_user_2', 'Role renamed: old role name should not exist.');
select has_role('test_user_4', 'Role renamed: new role name should exist.');
select ok(
    exists(
        select 1 from meta.role where id = row('test_user_4')::meta.role_id and superuser = true and 
                                      inherit = true and create_role = true and create_db = true and
                                      can_login = true and replication = true and connection_limit = 10 and
                                      password = '********' and valid_until = '2020-01-01 00:00:00-07'
    ),
    'Role updated with true/not-null values: should reflect updated values in meta.role.'
);
                     
-- update from all true to all false/null
update meta.role set superuser = false,
                     inherit = false,
                     create_role = false,
                     create_db = false,
                     can_login = false,
                     replication = false,
                     connection_limit = null,
                     valid_until = null
                 where id = row('test_user_1')::meta.role_id;
select ok(
    exists(
        select 1 from meta.role where id = row('test_user_1')::meta.role_id and superuser = false and 
                                      inherit = false and create_role = false and create_db = false and
                                      can_login = false and replication = false and connection_limit = -1 and
                                      valid_until is null
    ),
    'Role updated with false/null values: should reflect updated values in meta.role.'
);

-- delete
delete from meta.role where id = row('test_user_1')::meta.role_id;
select hasnt_role('test_user_1', 'Role deleted: should not exist');


/****************************************************************************************************
 * VIEW meta.constraint_unique                                                                      *
 ****************************************************************************************************/

create table test_schema.ninjas (
    id serial primary key,
    name text,
    job text,
    rank integer,
    age integer
);

insert into test_schema.ninjas (name, rank) values ('Bob', 0);

-- insert with table_id and column_ids
insert into meta.constraint_unique (table_id, name, column_ids)
values (
    row(row('test_schema'), 'ninjas')::meta.relation_id, 
    'ninja_name_uniq',
    array[row(row(row('test_schema'), 'ninjas'), 'name')::meta.column_id]
);
select ok(
    exists(
        select 1 from meta.constraint_unique
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_name_uniq')::meta.constraint_id and
              name = 'ninja_name_uniq' and
              column_ids = array[row(row(row('test_schema'), 'ninjas'), 'name')::meta.column_id]
              
    ),
    'Unique constraint inserted with table_id should exist in meta.constraint_unique.'
);
select throws_ok(
    'insert into test_schema.ninjas (name) values (''Bob'');',
    '23505',
    'duplicate key value violates unique constraint "ninja_name_uniq"',
    'Unique constraint inserted with table_id should prevent duplicate insert.'
);

-- insert with schema_name, table_name and column_names
insert into meta.constraint_unique (schema_name, table_name, name, column_names)
values ('test_schema', 'ninjas', 'ninja_rank_uniq', array['rank']);
select ok(
    exists(
        select 1 from meta.constraint_unique
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_rank_uniq')::meta.constraint_id and
              name = 'ninja_rank_uniq' and
              column_ids = array[row(row(row('test_schema'), 'ninjas'), 'rank')::meta.column_id]
              
    ),
    'Unique constraint inserted with schema_name, table_name, and column_names should exist in meta.constraint_unique.'
);

-- update 
update meta.constraint_unique set name = 'ninja_name_job_uniq',
                                  column_ids = array[
                                      row(row(row('test_schema'), 'ninjas'), 'name')::meta.column_id,
                                      row(row(row('test_schema'), 'ninjas'), 'job')::meta.column_id
                                  ]
                              where id = row(row(row('test_schema'), 'ninjas'), 'ninja_name_uniq')::meta.constraint_id;
select ok(
    not exists(
        select 1 from meta.constraint_unique
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_name_uniq')::meta.constraint_id
    ),
    'Renamed unique constraint: old name should not exist.'
);
select ok(
    exists(
        select 1 from meta.constraint_unique
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_name_job_uniq')::meta.constraint_id and
              name = 'ninja_name_job_uniq' and
              column_ids = array[
                  row(row(row('test_schema'), 'ninjas'), 'name')::meta.column_id,
                  row(row(row('test_schema'), 'ninjas'), 'job')::meta.column_id
              ]
    ),
    'Updated unique constraint should exist in meta.constraint_unique.'
);
select lives_ok(
    'insert into test_schema.ninjas (name, job) values (''Bob'', ''Chef'')',
    'Updated unique constraint: new constraint columns should allow insert.'
);
select throws_ok(
    'insert into test_schema.ninjas (name, job) values (''Bob'', ''Chef'')',
    '23505',
    'duplicate key value violates unique constraint "ninja_name_job_uniq"',
    'Updated unique constraint: new constraint columns should deny insert.'
);

-- delete
delete from meta.constraint_unique
where id =  row(row(row('test_schema'), 'ninjas'), 'ninja_rank_uniq')::meta.constraint_id;
select ok(
    not exists(
        select 1 from meta.constraint_unique
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_rank_uniq')::meta.constraint_id
    ),
    'Deleted unique constraint: old name should not exist.'
);
select lives_ok(
    'insert into test_schema.ninjas (name, rank) values (''Joe'', 0);',
    'Deleted unique constraint should no longer apply.'
);


/****************************************************************************************************
 * VIEW meta.constraint_check                                                                       *
 ****************************************************************************************************/

-- insert with table_id and column_ids
insert into meta.constraint_check (table_id, name, check_clause)
values (
    row(row('test_schema'), 'ninjas')::meta.relation_id, 
    'ninja_age_nonzero',
    'age > 0'
);
select ok(
    exists(
        select 1 from meta.constraint_check
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_nonzero')::meta.constraint_id and
              name = 'ninja_age_nonzero' and
              check_clause = '((age > 0))'
    ),
    'Check constraint inserted with table_id should exist in meta.constraint_check.'
);
select throws_ok(
    'insert into test_schema.ninjas (age) values (0);',
    '23514',
    'new row for relation "ninjas" violates check constraint "ninja_age_nonzero"',
    'Check constraint inserted with table_id should prevent undesired insert.'
);

-- insert with schema_name, table_name and column_names
insert into meta.constraint_check (schema_name, table_name, name, check_clause)
values ('test_schema', 'ninjas', 'ninja_age_lt_100', 'age < 100');
select ok(
    exists(
        select 1 from meta.constraint_check
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_lt_100')::meta.constraint_id and
              name = 'ninja_age_lt_100' and
              check_clause = '((age < 100))'
    ),
    'Check constraint inserted with schema_name, table_name, and column_names should exist in meta.constraint_check.'
);
select throws_ok(
    'insert into test_schema.ninjas (age) values (100);',
    '23514',
    'new row for relation "ninjas" violates check constraint "ninja_age_lt_100"',
    'Check constraint inserted with schema_name and table_name should prevent undesired insert.'
);

-- update
update meta.constraint_check set name = 'ninja_age_lt_125',
                                 check_clause = 'age < 125'
                             where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_lt_100')::meta.constraint_id;
select ok(
    not exists(
        select 1 from meta.constraint_check
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_lt_100')::meta.constraint_id
    ),
    'Renamed check constraint: old name should not exist.'
);
select ok(
    exists(
        select 1 from meta.constraint_check
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_lt_125')::meta.constraint_id and
              name = 'ninja_age_lt_125' and
              check_clause = '((age < 125))'
    ),
    'Updated check constraint should exist in meta.constraint_check.'
);
select lives_ok(
    'insert into test_schema.ninjas (age) values (100);',
    'Updated check constraint: new constraint check_clause should allow insert.'
);
select throws_ok(
    'insert into test_schema.ninjas (age) values (125);',
    '23514',
    'new row for relation "ninjas" violates check constraint "ninja_age_lt_125"',
    'Updated check constraint: new constraint check_clause should deny insert.'
);

-- delete
delete from meta.constraint_check
where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_lt_125')::meta.constraint_id;
select ok(
    not exists(
        select 1 from meta.constraint_check
        where id = row(row(row('test_schema'), 'ninjas'), 'ninja_age_lt_125')::meta.constraint_id
    ),
    'Deleted check constraint: old name should not exist.'
);
select lives_ok(
    'insert into test_schema.ninjas (age) values (125);',
    'Deleted check constraint: should no longer apply.'
);

/****************************************************************************************************
 * results                                                                                          *
 ****************************************************************************************************/

select * from finish();

rollback;
