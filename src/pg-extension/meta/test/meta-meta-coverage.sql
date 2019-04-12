begin;

drop schema if exists meta_meta;
create schema meta_meta;
set search_path=meta_meta, meta;

create table meta_meta.relation (
	-- TYPE
	id serial not null primary key,
	name text not null,
	-- gripe: ERROR:  cannot use column references in default expression
	type_id meta.type_id not null,
	type_constructor_function_id meta.function_id,-- not null,
	type_to_json_comparator_op_id meta.operator_id,-- not null,
	type_to_json_type_constructor_function_id meta.function_id,-- not null,
	type_to_json_cast_id meta.cast_id,-- not null,

	-- VIEW
	relation_id meta.relation_id,-- not null,

	-- create
	relation_create_stmt_function_id meta.function_id,-- not null,
	relation_insert_trigger_function_id meta.function_id,-- not null,
	relation_insert_trigger_id meta.trigger_id,-- not null,

	-- delete
	relation_drop_stmt_function_id meta.function_id,-- not null,
	relation_delete_trigger_function_id meta.function_id,-- not null,
	relation_delete_trigger_id meta.trigger_id not null,

	-- update
	/*
	relation_update_stmt_function_id meta.function_id not null,
	*/
	relation_update_trigger_function_id meta.function_id not null,
	relation_update_trigger_id meta.trigger_id not null
);

/*
create table meta_relation_update_handler (
	id serial not null primary key,
	stmt_function_id meta.function_id not null,
	trigger_function_id meta.function_id not null,
	trigger_id meta.trigger_id not null
);
*/

create or replace function generate_meta_meta_relation (name text, constructor_args text[]) returns void as $$
declare
	-- type
	_type_id meta.type_id;
	_type_constructor_function_id meta.function_id;
	_type_to_json_comparator_op_id meta.operator_id;
	_type_to_json_type_constructor_function_id meta.function_id;
	_type_to_json_cast_id meta.cast_id;

	-- relation
	_relation_id meta.relation_id;

	_relation_create_stmt_function_id meta.function_id;
	_relation_insert_trigger_function_id meta.function_id;
	_relation_insert_trigger_id meta.trigger_id;

	_relation_drop_stmt_function_id meta.function_id;
	_relation_delete_trigger_function_id meta.function_id;
	_relation_delete_trigger_id meta.trigger_id;
	
	_relation_update_trigger_function_id meta.function_id;
	_relation_update_trigger_id meta.trigger_id;
begin
	-- type
	_type_id := meta.type_id('meta', name || '_id');
	_type_constructor_function_id :=
		meta.function_id('meta', name || '_id', constructor_args);
	_type_to_json_comparator_op_id :=
		meta.operator_id('meta', '=', 'meta', name || '_id', 'public', 'json');
	_type_to_json_type_constructor_function_id :=
		meta.function_id('meta', name || '_id', '{"value"}');
	_type_to_json_cast_id :=
		meta.cast_id('meta', name || '_id', 'public', 'json');

	-- relation
	_relation_id :=
		meta.relation_id('meta', name);
	-- create -> insert
	_relation_create_stmt_function_id :=
		meta.function_id('meta', 'stmt_' || name || '_create', constructor_args);
	_relation_insert_trigger_function_id :=
		meta.function_id('meta', name || '_insert', NULL);
	_relation_insert_trigger_id :=
		meta.trigger_id('meta', name, 'meta_' || name || '_insert_trigger');

	-- drop -> delete
	_relation_drop_stmt_function_id :=
		meta.function_id('meta', 'stmt_' || name || '_drop', constructor_args);
	_relation_delete_trigger_function_id :=
		meta.function_id('meta', name || '_delete', NULL);
	_relation_delete_trigger_id :=
		meta.trigger_id('meta', name, 'meta_' || name || '_delete_trigger');

	-- alter -> update
	_relation_update_trigger_function_id :=
		meta.function_id('meta', name || '_update', NULL);
	_relation_update_trigger_id :=
		meta.trigger_id('meta', name, 'meta_' || name || '_update_trigger');

	insert into meta_meta.relation (
        name,
		-- type
		type_id,
		type_constructor_function_id,
		type_to_json_comparator_op_id,
		type_to_json_type_constructor_function_id,
		type_to_json_cast_id,

		-- relation
		relation_id,

		relation_create_stmt_function_id,
		relation_insert_trigger_function_id,
		relation_insert_trigger_id,

		relation_drop_stmt_function_id,
		relation_delete_trigger_function_id,
		relation_delete_trigger_id,
		
		relation_update_trigger_function_id,
		relation_update_trigger_id
	) values (
        name,
		-- type
		_type_id,
		_type_constructor_function_id,
		_type_to_json_comparator_op_id,
		_type_to_json_type_constructor_function_id,
		_type_to_json_cast_id,

		-- relation
		_relation_id,

		_relation_create_stmt_function_id,
		_relation_insert_trigger_function_id,
		_relation_insert_trigger_id,

		_relation_drop_stmt_function_id,
		_relation_delete_trigger_function_id,
		_relation_delete_trigger_id,
		
		_relation_update_trigger_function_id,
		_relation_update_trigger_id
	);
end;
$$ language plpgsql;




-- use the generator function to propogate meta_meta_relation with the stuff that is expected to be there
select 
    generate_meta_meta_relation('schema',      '{"name"}'),
    generate_meta_meta_relation('type',        '{"schema_name", "name"}'),
    generate_meta_meta_relation('cast',        '{"source_type_schema_name", "source_type_name", "target_type_schema_name", "target_type_name"}'),
    generate_meta_meta_relation('operator',    '{"schema_name", "name", "left_arg_type_schema_name", "left_arg_type_name", "right_arg_type_schema_name", "right_arg_type_name"}'),
    generate_meta_meta_relation('sequence',    '{"schema_name", "name"}'),
    generate_meta_meta_relation('relation',    '{"schema_name", "name"}'),
    generate_meta_meta_relation('column',      '{"schema_name", "relation__name", "name"}'),
    generate_meta_meta_relation('foreign_key', '{"schema_name", "relation__name", "name"}'),
    generate_meta_meta_relation('row',         '{"schema_name", "relation_name", "pk_column_name", "pk_value"}'),
    generate_meta_meta_relation('field_id',    '{"schema_name", "relation_name", "pk_column_name", "pk_value", "column_name"}'),
    generate_meta_meta_relation('function',    '{"schema_name", "name", "parameters"}'),
    generate_meta_meta_relation('trigger',     '{"schema_name", "relation_name", "name"}'),
    generate_meta_meta_relation('role',        '{"name"}'),
    generate_meta_meta_relation('connection',  '{"pid", "connection_start"}'),
    generate_meta_meta_relation('constraint',  '{"schema_name", "relation_name", "name"}'),
    generate_meta_meta_relation('constraint_unique', '{"schema_name", "table_name", "name", "column_names"}'),
    -- generate_meta_meta_relation('constraint_check',-- '{"schema_name", "table_name", "name", "column_names"}'),
    generate_meta_meta_relation('extension',   '{"name"}'),
    generate_meta_meta_relation('foreign_data_wrapper',         '{"name"}'),
    generate_meta_meta_relation('foreign_server','{"name"}')
--    generate_meta_meta_relation('foreign_table','{"schema_name", "name"}')
--    generate_meta_meta_relation('foreign_column','{"schema_name", "name"}')
;



-- exist functions for: function, trigger, op, type, relation, cast
create or replace function _exists(in f meta.function_id, out ex boolean) as $$
    select (count(*) = 1) from meta.function where id = f;
$$ language sql;

create or replace function _exists(in t meta.trigger_id, out ex boolean) as $$
    select (count(*) = 1) from meta.trigger where id = t;
$$ language sql;

create or replace function _exists(in o meta.operator_id, out ex boolean) as $$
    select (count(*) = 1) from meta.operator where id = o;
$$ language sql;

create or replace function _exists(in t meta.type_id, out ex boolean) as $$
    select (count(*) = 1) from meta.type where id = t;
$$ language sql;

create or replace function _exists(in r meta.relation_id, out ex boolean) as $$
    select (count(*) = 1) from meta.relation where id = r;
$$ language sql;

create or replace function _exists(in c meta.cast_id, out ex boolean) as $$
    select (count(*) = 1) from meta.cast where id = c;
$$ language sql;




		-- type
create view checker as 
select 
    name,
    _exists(type_id) type_id,
    _exists(type_constructor_function_id) type_constructor_function_id,
    _exists(type_to_json_comparator_op_id) type_to_json_comparator_op_id,
    _exists(type_to_json_type_constructor_function_id) type_to_json_type_constructor,
    _exists(type_to_json_cast_id) type_to_json_cast_id,

    _exists(relation_id) relation_id,

    _exists(relation_create_stmt_function_id) relation_create_stmt_function_id,
    _exists(relation_insert_trigger_function_id) relation_insert_trigger_function_id,
    _exists(relation_insert_trigger_id) relation_insert_trigger_id,

    _exists(relation_drop_stmt_function_id) relation_drop_stmt_function_id,
    _exists(relation_delete_trigger_function_id) relation_delete_trigger_function_id,
    _exists(relation_delete_trigger_id) relation_delete_trigger_id,
    _exists(relation_update_trigger_function_id) relation_update_trigger_function_id,
    _exists(relation_update_trigger_id) relation_update_trigger_id
    from meta_meta.relation
;


create or replace view checker2 as
select
    r.name,

    (r1.id is not null) as type_id,
    (r2.id is not null) as type_constructor_function_id,
    (r3.id is not null) as type_to_json_comparator_op_id,
    (r4.id is not null) as type_to_json_type_constructor_function_id,
    (r5.id is not null) as type_to_json_cast_id,

    (r6.id is not null) as relation_id,

    (r7.id is not null) as relation_create_stmt_function_id,
    (r8.id is not null) as relation_insert_trigger_function_id,
    (r9.id is not null) as relation_insert_trigger_id,

    (r10.id is not null) as relation_drop_stmt_function_id,
    (r11.id is not null) as relation_delete_trigger_function_id,
    (r12.id is not null) as relation_delete_trigger_id,
    (r13.id is not null) as relation_update_trigger_function_id,
    (r14.id is not null) as relation_update_trigger_id

    from meta_meta.relation r

    left join meta.type r1 on type_id = r1.id
    left join meta.function r2 on type_constructor_function_id = r2.id
    left join meta.operator r3 on type_to_json_comparator_op_id = r3.id
    left join meta.function r4 on type_to_json_type_constructor_function_id = r4.id
    left join meta.cast r5 on type_to_json_cast_id = r5.id

    left join meta.relation r6 on relation_id = r6.id

    left join meta.function r7 on relation_create_stmt_function_id = r7.id
    left join meta.function r8 on relation_insert_trigger_function_id = r8.id
    left join meta.trigger r9 on relation_insert_trigger_id = r9.id

    left join meta.function r10 on relation_drop_stmt_function_id = r10.id
    left join meta.function r11 on relation_delete_trigger_function_id = r11.id
    left join meta.trigger r12 on relation_delete_trigger_id = r12.id
    left join meta.function r13 on relation_update_trigger_function_id = r13.id
    left join meta.trigger r14 on relation_update_trigger_id = r14.id
;


commit;
