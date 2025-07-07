/******************************************************************************
 * ENDPOINT SERVER
 * HTTP request handler for a datum REST interface
 * HTTP arbitrary resource server
 ******************************************************************************/

/****************************************************************************************************
 *
 * FUNCTION suffix_clause
 *
 * Builds limit, offset, order by, and where clauses from json
 *
 ****************************************************************************************************/

create or replace function endpoint.suffix_clause(
    args json
) returns text as $$

    declare
        _limit text := '';
        _offset text := '';
        _order_by text := '';
        _where text := 'where true';
        r record;

    begin
        for r in select * from json_each(args) loop

            -- Limit clause
            -- URL
            -- /endpoint?$limit=10
            if r.key = 'limit' then
                select ' limit ' || quote_literal(json_array_elements_text)
                from json_array_elements_text(r.value::text::json)
                into _limit;

            -- Offset clause
            -- URL
            -- /endpoint?$offest=5
            elsif r.key = 'offset' then
                select ' offset ' || quote_literal(json_array_elements_text)
                from json_array_elements_text(r.value::text::json)
                into _offset;

            -- Order by clause
            -- URL
            -- /endpoint?$order_by=city
            -- /endpoint?$order_by=[city,-state,-full_name]
            elsif r.key = 'order_by' then
                if pg_typeof(r.value) = 'json'::regtype then
                    select ' order by ' ||
                        string_agg(case substring(q.val from 1 for 1)
                                       when '-' then substring(q.val from 2) || ' desc'
                                       else q.val end,
                        ', ')
                    from (select json_array_elements_text as val from json_array_elements_text(r.value)) q
                    into _order_by;
                else
                    select ' order by ' ||
                        case substring(r.value::text from 1 for 1)
                            when '-' then substring(r.value::text from 2) || ' desc'
                            else r.value::text
                            end
                    into _order_by;
                end if;

            -- Where clause
            -- URL
            -- /endpoint?$where={name=NAME1,op=like,value=VALUE1}
            -- /endpoint?$where=[{name=NAME1,op=like,value=VALUE1},{name=NAME2,op='=',value=VALUE2}]
            elsif r.key = 'where' then

                if pg_typeof(r.value) = 'json'::regtype then

                    if json_typeof(r.value) = 'array' then -- { where: JSON array }

                        /*
                        select json->>'name' as name, json->>'op' as op, json->>'value' as value from
                            (select json_array_elements_text(value)::json as json from
                                (( select value from json_each('{"where": ["{\"name\":\"bundle_name\",\"op\":\"=\",\"value\":\"com.aquameta.core.ide\"}", "{\"name\":\"name\",\"op\":\"=\",\"value\":\"development\"}"]}'))
                                ) v)
                            b;
                        */
                        select _where || ' and ' || string_agg( name || '::text ' || op || ' ' ||


                            case when op = 'in' then
                                -- Value is array
                                case when json_typeof(json) = 'array' then
                                   (select '(' || string_agg(quote_literal(array_val), ',') || ')'
                                   from json_array_elements_text(json) as array_val)
                                -- Value is object
                                when json_typeof(json) = 'object' then
                                   quote_literal(json) || '::json'
                                else
                                    quote_literal(value)
                                end
                            else
                                quote_literal(value)
                            end

                            , '::text and ' )

                        from (
                            select element->>'name' as name, element->>'op' as op, element->'value' as json, element->>'value' as value
                            from (select json_array_elements_text::json as element from json_array_elements_text(r.value)) j
                            ) v
                        into _where;

                    elsif json_typeof(r.value) = 'object' then -- { where: JSON object }
                        select _where || ' and ' || name || '::text ' || op || ' ' ||

                            case when op = 'in' then
                                -- Value is array
                                case when json_typeof(value::json) = 'array' then
                                   (select '(' || string_agg(quote_literal(array_val), ',') || ')'
                                   from json_array_elements_text(value::json) as array_val)
                                -- Value is object
                                when json_typeof(value::json) = 'object' then
                                   quote_literal(value) || '::json'
                                else
                                    quote_literal(value)
                                end
                            end
                        || '::text'

                        from json_to_record(r.value::json) as x(name text, op text, value text)
                        into _where;

                    end if;

                else -- Else { where: regular value } -- This is not used in the client

                    select _where || ' and ' || quote_ident(name) || '::text ' || op || ' ' || quote_literal(value) || '::text'
                    from json_to_record(r.value::json) as x(name text, op text, value text)
                    into _where;

                end if;

            else
            end if;
        end loop;
        return  _where || _order_by || _limit || _offset;
    end;
$$
language plpgsql;



/******************************************************************************
 * REQUEST HANDLERS
 *
 * Functions called by endpoint.request, returning JSON/REST responses
 ******************************************************************************/

/****************************************************************************************************
 * FUNCTION multiple_row_insert                                                                      *
 ****************************************************************************************************/
create or replace function endpoint.multiple_row_insert(
    relation_id meta.relation_id,
    args json
) returns setof json as $$

    declare
        _schema_name text;
        _relation_name text;
        r json;
        q text;

    begin
        select (relation_id).schema_name into _schema_name;
        select (relation_id).name into _relation_name;

        select array_to_json(array_agg(t.json_array_elements))
        from
            (
                select json_array_elements(endpoint.row_insert(relation_id, json_array_elements)->'result')
                from json_array_elements(args)
            ) t
        into r;

        q := 'select (''{' ||
                --"columns":'' || endpoint.columns_json($1, $2) || '',
                '"result":'' || ($3) || ''
            }'')::json';

        return query execute q
        using _schema_name,
            _relation_name,
            r;
    end;

$$
language plpgsql;



/****************************************************************************************************
 * FUNCTION rows_insert                                                                              *
 ****************************************************************************************************/
create or replace function endpoint.rows_insert(
    args json
) returns void as $$

    declare
        row_id meta.row_id;
        --q text;

    begin
        -- raise notice 'ROWS INSERT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
        -- raise notice 'TOTAL ROWS: %', json_array_length(args);
        -- raise notice 'da json: %', args;

        -- insert rows
        for i in 0..json_array_length(args) - 1 loop
            row_id := (args->i->'row_id')::meta.row_id;
            -- raise notice '########################### inserting row %: % @@@@@ %', i, row_id, args->i;
            -- raise notice '% =  %', row_id, args->i->'row';

            -- disable triggers (except blob... hack hack)
            if row_id::meta.relation_id != meta.relation_id('bundle','blob') then
                execute 'alter table ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) || ' disable trigger all';
            end if;

            -- Doesn't seem to be used
            --q := 'insert into ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) || ' select * from json_to_record (' || quote_literal(args->i->'row') || ')';
            -- raise notice '(NOT) QUERY: %', q;
            -- execute q;

            perform endpoint.row_insert(row_id::meta.relation_id, args->i->'row');
            --perform endpoint.row_insert((row_id::meta.schema_id).name, 'table', (row_id::meta.relation_id).name, args->i->'row');
        end loop;

        -- enable triggers
        for i in 0..json_array_length(args) - 1 loop
            row_id := (args->i->'row_id')::meta.row_id;
            execute 'alter table ' || quote_ident((row_id::meta.schema_id).name) || '.' || quote_ident((row_id::meta.relation_id).name) || ' enable trigger all';
        end loop;
    end
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION row_insert                                                                              *
 ****************************************************************************************************/

create or replace function endpoint.row_insert(
    relation_id meta.relation_id,
    args json
) returns setof json as $$

    declare
       _schema_name text;
       _relation_name text;
       q text;


    /*
    TODO: This doesn't work with bytea columns because when you insert text
    into a bytea column because it thinks it's the client_encoding instead of
    hex.  -- this function is entirely wrong anywya, it is detecting json not
    by looking at the column type but by looking at the VALUE.  WTF.
    */

    begin
        _schema_name := (relation_id::meta.schema_id).name;
        _relation_name := (relation_id).name;

        q := '
            with inserted_row as (
                insert into ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) ||
                case when args::text = '{}'::text then
                    ' default values '
                else
                    ' (' || (
                        select string_agg(quote_ident(json_object_keys), ',' order by json_object_keys)
                        from json_object_keys(args)

                    ) || ') values (' || (



                           select string_agg('
                                   case when json_typeof($3->' || quote_literal(json_object_keys) || ') = ''array'' then ((
                                            select ''{'' || string_agg(value::text, '', '') || ''}''
                                            from json_array_elements(($3->>' || quote_literal(json_object_keys) || ')::json)
                                        ))
                                        when json_typeof($3->' || quote_literal(json_object_keys) || ') = ''object'' then
                                            ($3->' || quote_literal(json_object_keys) || ')::text
                                        else ($3->>' || quote_literal(json_object_keys) || ')::text
                                   end::' || case when json_typeof((args->json_object_keys)) = 'object' then 'json::'
                                                  else ''
                                             end || c.type_name, ',
                                   '
                                   order by json_object_keys
                           ) from json_object_keys(args)
                           inner join meta.relation_column c
                                   on c.schema_name = _schema_name and
                                      c.relation_name = _relation_name and
                                      c.name = json_object_keys
                           left join meta.type t on c.type_id = t.id



                    ) || ') '
                end ||
                'returning *
            )
            select (''{
                "columns": ' || endpoint.columns_json(_schema_name, _relation_name, null::text[], null::text[]) || ',
                "pk":"' || coalesce(endpoint.pk_name(_schema_name, _relation_name), 'null') || '",
                "result": [{ "row": '' || row_to_json(inserted_row.*, true) || '' }]
            }'')::json
            from inserted_row
        ';

        -- raise notice 'ROW_INSERT ############: %', q;
        return query execute q
        using _schema_name,
            _relation_name,
            args;
    end
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION row_update                                                                              *
 ****************************************************************************************************/

-- TODO: rewrite this entirely.  Hacked in some non-composite-pk support for 0.5 to get things working
create or replace function endpoint.row_update(
    row_id meta.row_id,
    args json
) returns json as $$ -- FIXME: use json_to_row upon 9.4 release, alleviates all the destructuring below
    declare
        _schema_name text;
        _relation_name text;
        pk text;
    begin
        -- raise notice 'ROW_UPDATE ARGS: %, %, %, %, %', _schema_name, relation_type, _relation_name, pk, args::text;
        select (row_id::meta.schema_id).name into _schema_name;
        select (row_id::meta.relation_id).name into _relation_name;
        select row_id.pk_values[1]::text into pk;

        execute (
            select 'update ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) || ' as r
                    set ' || (
                       select string_agg(
                           quote_ident(keys) || ' =
                               case when json_typeof($1->' || quote_literal(keys) || ') = ''array'' then ((
                                        select ''{'' || string_agg(value::text, '', '') || ''}''
                                        from json_array_elements(($1->>' || quote_literal(keys) || ')::json)
                                    ))
                                    when json_typeof($1->' || quote_literal(keys) || ') = ''object'' then
                                        ($1->' || quote_literal(keys) || ')::text
                                    else ($1->>' || quote_literal(keys) || ')::text
                               end::' || case when json_typeof((args->keys)) = 'object' then 'json::'
                                              else ''
                                         end || c.type_name, ',
                           '
                       ) from json_object_keys(args) keys
                       inner join meta.relation_column c
                               on c.schema_name = _schema_name and
                                  c.relation_name = _relation_name and
                                  c.name = keys
                   ) || ' where ' || (
                       select 'r.' || quote_ident((row_id).pk_column_names[1]) || ' = ' || quote_literal((row_id).pk_values[1])
                   )
        ) using args;

        return '{}';
    end;
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION rows_select                                                                             *
 ****************************************************************************************************/

create or replace function endpoint.rows_select(
    relation_id meta.relation_id,
    args json
) returns json as $$
declare
    schema_name text;
    relation_name text;
    row_query text;
    rows_json text;
    suffix text;
    exclude text[];
    include text[];
    column_list text;

begin
    select (relation_id).schema_name into schema_name;
    select (relation_id).name into relation_name;

    -- Suffix
    select endpoint.suffix_clause(args) into suffix;

    -- Column list
    -- Exclude
    select array_agg(val)
    from ((
        select json_array_elements_text(value::json) as val
        from json_array_elements_text(args->'exclude')
    )) q
    into exclude;

    -- Include
    select array_agg(val)
    from ((
        select json_array_elements_text(value::json) as val
        from json_array_elements_text(args->'include')
    )) q
    into include;

    if exclude is not null or include is not null then
        select endpoint.column_list(schema_name, relation_name, 'r'::text, exclude, include) into column_list;
    else
        select 'r.*' into column_list;
    end if;

    row_query := 'select ''['' || string_agg(q.js, '','') || '']'' from (
                          select ''{ "row":'' || row_to_json(t.*, true) || '' }'' js
                          from ((select ' || column_list || ' from ' || quote_ident(schema_name) || '.' || quote_ident(relation_name) || ' r ' || suffix || ')) as t
                     ) q';

    raise notice 'ROW QUERY: %', row_query;

    execute row_query into rows_json;

    return '{' ||
           case when args->>'meta_data' = '["true"]' then
                                        '"columns":' || endpoint.columns_json(schema_name, relation_name, exclude, include) || ',' ||
                                        '"pk":"' || coalesce(endpoint.pk_name(schema_name, relation_name), 'null') || '",'
                else ''
               end ||
           '"result":' || coalesce(rows_json, '[]') || '}';
end;
$$
    language plpgsql;


/****************************************************************************************************
 * FUNCTION row_select                                                                              *
 ****************************************************************************************************/

create or replace function endpoint.row_select(
    row_id meta.row_id,
    args json
) returns json as $$

    declare
        _schema_name text;
        _relation_name text;
        pk_column_name text;
        pk text;

        row_query text;
        row_json text;
        columns_json text;

        exclude text[];
        include text[];
        column_list text;

    begin
        -- raise notice 'ROW SELECT ARGS: %, %, %, %', schema_name, table_name, queryable_type, pk;
        set local search_path = endpoint;

        select (row_id::meta.schema_id).name into _schema_name;
        select (row_id::meta.relation_id).name into _relation_name;
        select (row_id).pk_column_name into pk_column_name;
        select row_id.pk_value into pk;


        -- Column list
        -- Exclude
        select array_agg(val)
        from ((
            select json_array_elements_text(value::json) as val
            from json_array_elements_text(args->'exclude')
        )) q
        into exclude;

        -- Include
        select array_agg(val)
        from ((
            select json_array_elements_text(value::json) as val
            from json_array_elements_text(args->'include')
        )) q
        into include;

        if exclude is not null or include is not null then
            select endpoint.column_list(_schema_name, _relation_name, '', exclude, include) into column_list;
        else
            select '*' into column_list;
        end if;


        row_query := 'select ''[{"row": '' || row_to_json(t.*, true) || ''}]'' from ' ||
                        '(select ' || column_list || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name) ||
                        ' where ' || quote_ident(pk_column_name) || '=' || quote_literal(pk) ||
                            (
                                select '::' || c.type_name
                                from meta.relation_column c
                                where c.schema_name = _schema_name and
                                   c.relation_name = _relation_name and
                                   c.name = pk_column_name -- FIXME column integration
                            ) ||
                    ') t';
/*
-- This pk lookup only works if relation has a primary key in meta.column... what about foreign tables and views?
-- Also foreign data does not show up unless you use a subquery to get it to run first... Not sure why

        row_query := 'select ''[{"row": '' || row_to_json(t.*) || ''}]'' from '
                     || quote_ident(schema_name) || '.' || quote_ident(relation_name)
                     || ' as t where ' || (
                         select quote_ident(pk_name) || ' = ' || quote_literal(pk) || '::' || pk_type
                         from endpoint.pk(schema_name, relation_name) p
                     );
*/
        execute row_query into row_json;

        --return '{"columns":' || columns_json(_schema_name, _relation_name) || ',"result":' || coalesce(row_json::text, '[]') || '}';
        return '{' ||
               case when args->>'meta_data' = '["true"]' then
                   '"columns":' || endpoint.columns_json(_schema_name, _relation_name, exclude, include) || ',' ||
                   '"pk":"' || endpoint.pk_name(_schema_name, _relation_name) || '",'
               else ''
               end ||
               '"result":' || coalesce(row_json::text, '[]') || '}';
    end;
$$
language plpgsql;


/****************************************************************************************************
 * FUNCTION field_select                                                                            *
 ****************************************************************************************************/

create or replace function endpoint.field_select(
    field_id meta.field_id,
    out field text,
    out mimetype text
) returns record as $$

    declare
        _schema_name text;
        _relation_name text;
        pk_values text[];
        pk_column_names text[];
        pk_types text;
        field_name text;
        field_type text;
        stmt text;
        pk_stmt text;

    begin
        raise notice 'FIELD SELECT ARGS: %', field_id;
        set local search_path = endpoint;

        select (field_id).schema_name into _schema_name;
        select (field_id).relation_name into _relation_name;
        select (field_id).pk_values into pk_values;
        select (field_id).pk_column_names into pk_column_names;
        select (field_id).column_name into field_name;

        -- Find pk_types
        select type_name
        from meta.column
        where id = field_id::meta.column_id
        into pk_types;

        -- Find field_type
        select type_name
        from meta.column
        where schema_name = _schema_name
            and relation_name = _relation_name
            and name = field_name
        into field_type;

        if field_type <> 'endpoint.resource_bin' then
            -- Find mimetype for this field
            select m.mimetype
            from endpoint.column_mimetype cm
                join endpoint.mimetype m on m.id = cm.mimetype_id
            where cm.column_id = field_id::meta.column_id
            into mimetype;
        end if;

        -- Default mimetype
        mimetype := coalesce(mimetype, 'application/json');
        pk_stmt := meta._pk_stmt(
            field_id.pk_column_names,
            field_id.pk_values,
            '%1$I = %2$L' -- refactor for composite-pk meta is skipping pk_type and type casting, not sure if that'll cause problems
        );

        if field_type = 'endpoint.resource_bin' then
            /*
            -- first try at a rewrite
            stmt := format(
                'select (%I).mimetype, encode((%I).content, ''escape'')
                     from %I.%I as t
                     where (%s)
                     into mimetype, field'
                field_name,
                field_name,
                _schema_name,
                _relation_name,
                pk_stmt
            );
            execute stmt;
            */

            execute 'select (' || quote_ident(field_name) || ').mimetype, encode((' || quote_ident(field_name) || ').content, ''escape'')'
                || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where (' || pk_stmt || ')' into mimetype, field;
        elsif field_type = 'pg_catalog.bytea' then
            execute 'select encode(' || quote_ident(field_name) || ', ''escape'') from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where (' || pk_stmt || ')' into field;
        else
            execute 'select ' || quote_ident(field_name) || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where (' || pk_stmt || ')' into field;
        end if;

        /*

        before composite-pk meta refactor:

        if field_type = 'endpoint.resource_bin' then
            execute 'select (' || quote_ident(field_name) || ').mimetype, encode((' || quote_ident(field_name) || ').content, ''escape'')'
                || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where ' || quote_ident(pk_column_name) || ' = ' || quote_literal(pk) || '::' || pk_type into mimetype, field;
        elsif field_type = 'pg_catalog.bytea' then
            execute 'select encode(' || quote_ident(field_name) || ', ''escape'') from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where ' || quote_ident(pk_column_name) || ' = ' || quote_literal(pk) || '::' || pk_type into field;
        else
            execute 'select ' || quote_ident(field_name) || ' from ' || quote_ident(_schema_name) || '.' || quote_ident(_relation_name)
                || ' as t where ' || quote_ident(pk_column_name) || '::text = ' || quote_literal(pk) || '::text' / * || pk_type * / into field;
        end if;
        */

        -- implicitly returning field and mimetype
    end;
$$
language plpgsql;




/******************************************************************************
 * FUNCTION rows_select_function

some_function?args={ vals: [] } -- Array
some_function?args={ kwargs: {} } -- Key/value object
some_function?args={ kwargs: {} }&column=name

This function should do some much smarter stuff with return type
Should be able to select a single column when not returning SETOF
Some of the logic from the column-specific rows_select_function()
We also want to use column_mimetype if we are only sending one column back

 *****************************************************************************/

create or replace function endpoint.rows_select_function(
    function_id meta.function_id,
    args json,
    out result text,
    out mimetype text
) returns record as $$

    declare
        _function_id alias for function_id;
        function_return_type text;
        row_is_composite boolean;
        columns_json text;
        function_args text;
        _row record;
        rows_json text[];
        suffix text;
        return_column text;
        meta_data text;
        result_type text;

    begin
        -- Get function row
        select return_type
        from meta.function f
        where f.schema_name = (_function_id).schema_name
            and f.name = (_function_id).name
            and f.parameters = (_function_id).parameters
        into function_return_type;

        -- Meta data
        meta_data := args->>'meta_data';
        if meta_data = '["true"]' then

            -- Find is return type is composite
            select t.composite
            from meta.function f
                join meta.type t on t.id = f.return_type_id
            where f.id = _function_id
            into row_is_composite;


            -- Build columns_json
            if row_is_composite or result_type = 'record' then

              select string_agg(row_to_json(q.*, true)::text, ',')
              from (
                    select pga.attname as name,
                        pgt2.typname as "type"
                    from pg_catalog.pg_type pgt
                        inner join pg_class pgc
                            on pgc.oid = pgt.typrelid
                        inner join pg_attribute pga
                            on pga.attrelid = pgc.oid
                        inner join pg_type pgt2
                            on pgt2.oid = pga.atttypid
                    where pgt.oid = function_return_type::regtype
                        and pga.attname not in ('tableoid','cmax','xmax','cmin','xmin','ctid')
              ) q
              into columns_json;

            else

                select row_to_json(q.*)
                from (select (_function_id).name as name, function_return_type as "type") q
                into columns_json;

            end if;
        end if;

        -- Suffix clause: where, order by, offest, limit
        suffix := endpoint.suffix_clause(args);

        -- Return column
        return_column := json_array_elements_text(args->'column');

        -- Args
        select json_array_elements_text::json
        from json_array_elements_text(args->'args') into args;

        -- Function Arguments
        if args->'kwargs' is not null then

            -- Build function arguments string
            -- Cast to type_name found in meta.function_parameter
            -- Using coalesce(function_args, '') so we can call function without arguments
            select coalesce(
                string_agg(quote_ident(r.key) || ':=' ||
                case when -- pg_typeof(r.value) = 'json'::regtype and
                    json_typeof(r.value) = 'object' then
                    quote_literal(r.value) || '::json::'
                else
                    quote_literal(btrim(r.value::text, '"')) || '::'
                end ||
                fp.type_name, ','),
            '')
            from json_each(args->'kwargs') r
                join meta.function_parameter fp on
                    fp.schema_name = (_function_id).schema_name and -- Trick to speed up query
                    fp.function_id = _function_id and
                    fp.name = r.key
            into function_args;

        elsif args->'vals' is not null then
            -- Transpose JSON array to comma-separated string
            select string_agg(quote_literal(value), ',')
            from json_array_elements_text(args->'vals') into function_args;
        else
            -- No arguments
            select '' into function_args;
        end if;


        if return_column is null then

            -- Default mimetype
            mimetype := 'application/json';

            /*** FIXME: this is broken */

            -- Loop through function call results
            for _row in execute 'select * from ' || quote_ident((_function_id).schema_name) || '.' || quote_ident((_function_id).name)
                                || '(' || function_args || ') ' || suffix
            loop
                rows_json := array_append(rows_json, '{ "row": ' || row_to_json(_row, true) || ' }');
            end loop;

            -- Result JSON object
            select '{' ||
                case when meta_data = '["true"]' then
                    '"columns":[' || columns_json || '],'
                else ''
                end ||
                '"result":' || coalesce('[' || array_to_string(rows_json,',') || ']', '[]') || '}'
             into result;

        else

            execute 'select ' || return_column || ', pg_typeof(' || return_column || ') from ' ||
                quote_ident((_function_id).schema_name) || '.' || quote_ident((_function_id).name) ||
                '(' || function_args || ') ' || suffix into result, result_type;

            if result_type <> 'resource_bin' and result_type <> 'endpoint.resource_bin' then

                -- Get mimetype
                select m.mimetype
                from endpoint.function_field_mimetype ffm
                    join endpoint.mimetype m on m.id = ffm.mimetype_id
                where ffm.schema_name = (_function_id).schema_name
                    and ffm.function_name = (_function_id).name
                    and field_name = return_column
                into mimetype;

                -- Default mimetype
                mimetype := coalesce(mimetype, 'application/json');

                if result_type = 'bytea' or result_type = 'pg_catalog.bytea' then
                    result := encode(result::bytea, 'escape');
                end if;

            else

                mimetype := (result::endpoint.resource_bin).mimetype;
                result := encode((result::endpoint.resource_bin).content, 'escape');

            end if;

        end if;


        -- implicitly returning function result and mimetype

    end;
$$
language plpgsql;


create or replace function endpoint.anonymous_rows_select_function(
    _schema_name text,
    _function_name text,
    args json,
    out result text,
    out mimetype text
) returns record as $$

    declare
        _mimetype alias for mimetype;
        columns_json text;
        function_args text;
        suffix text;
        _row record;
        rows_json text[];
        return_column text;
        result_type text;

    begin
        -- Build columns_json TODO ?
        columns_json := '';

        -- Return column
        return_column := json_array_elements_text(args->'column');

        -- Suffix clause: where, order by, offest, limit
        suffix := endpoint.suffix_clause(args);

        -- Args
        select json_array_elements_text::json
        from json_array_elements_text(args->'args') into args;

        -- Function Arguments
        if  args->'vals' is not null then
            -- Transpose JSON array to comma-separated string
            select string_agg(quote_literal(value), ',') from json_array_elements_text(args->'vals') into function_args;
        else
            -- No arguments
            function_args := '';
        end if;

        if return_column is null then

            -- Default mimetype
            mimetype := 'application/json';

            -- Loop through function call results
            for _row in execute 'select * from ' || quote_ident(_schema_name) || '.' || quote_ident(_function_name)
                                || '(' || function_args || ') ' || suffix
            loop
                rows_json := array_append(rows_json, '{ "row": ' || row_to_json(_row, true) || ' }');
            end loop;

            -- Result JSON object
            select '{"result":' || coalesce('[' || array_to_string(rows_json,',') || ']', '[]') || '}' into result;

        else

            execute 'select ' || return_column || ', pg_typeof(' || return_column || ') from ' || quote_ident(_schema_name) || '.' || quote_ident(_function_name)
                                || '(' || function_args || ') ' || suffix into result, result_type;

            if result_type <> 'resource_bin' and result_type <> 'endpoint.resource_bin' then

                -- Get mimetype
                select m.mimetype
                from endpoint.function_field_mimetype ffm
                    join endpoint.mimetype m on m.id = ffm.mimetype_id
                where ffm.schema_name = _schema_name
                    and ffm.function_name = _function_name
                    and field_name = return_column
                into mimetype;

                -- Default mimetype
                mimetype := coalesce(mimetype, 'application/json');

                if result_type = 'bytea' or result_type = 'pg_catalog.bytea' then
                    result := encode(result::bytea, 'escape');
                end if;

            else

                mimetype := (result::endpoint.resource_bin).mimetype;
                result := encode((result::endpoint.resource_bin).content, 'escape');

            end if;

        end if;

        -- implicitly returning function result and mimetype
    end;
$$
language plpgsql;


-- This function should disappear. Factor column selection into previous rows_select_function()
create or replace function endpoint.rows_select_function(
    function_id meta.function_id,
    args json,
    column_name text
) returns text as $$

    declare
        row_type regtype;
        row_is_composite boolean;
        columns_json text;
        function_args text;
        result text;

    begin
        select case when substring(q.ret from 1 for 6) = 'SETOF ' then substring(q.ret from 6)
                else q.ret
            end::regtype
        from (select pg_get_function_result(function_id.schema_name || '.' || (function_id.name)::regproc) as ret) q
        into row_type;

        -- Find is return type is composite
        select t.composite
        from meta.function f
            join meta.type t on t.id = f.return_type_id
        where f.id = function_id
        into row_is_composite;

        -- select typtype = 'c' from pg_type into row_is_composite where pg_type.oid = row_type;

        -- Build columns_json
        if row_is_composite then

            select string_agg(row_to_json(q.*, true)::text, ',')
            from (
                select pga.attname as name,
                    pgt2.typname as "type"
                from pg_type pgt
                    inner join pg_class pgc
                        on pgc.oid = pgt.typrelid
                    inner join pg_attribute pga
                        on pga.attrelid = pgc.oid
                    inner join pg_type pgt2
                        on pgt2.oid = pga.atttypid
                where pgt.oid = row_type
                    and pga.attname not in ('tableoid','cmax','xmax','cmin','xmin','ctid')
            ) q
            into columns_json;

        else

            select row_to_json(q.*, true)
            from (select (function_id).name as name, row_type as "type") q
            into columns_json;

        end if;


        -- Build function arguments string
        select coalesce(
            string_agg(quote_ident(r.key) || ':=' || quote_literal(r.value) || '::' || fp.type_name, ','),
        '')
        from json_each_text(args) r
            join meta.function_parameters fp on
                fp.function_id = function_id and
                fp.name = r.key
        into function_args;


        -- Loop through function call results
        execute 'select ' || quote_ident(column_name) || ' from ' || quote_ident(function_id.schema_name) || '.' || quote_ident(function_id.name)
                || '(' || function_args || ')' into result;

        return result;
    end;
$$
language plpgsql;


/******************************************************************************
 * FUNCTION row_delete
 *****************************************************************************/

create or replace function endpoint.row_delete(
    row_id meta.row_id
) returns json as $$

    declare
        _schema_name text;
        _table_name text;
        pk text;

    begin
        select (row_id).schema_name into _schema_name;
        select (row_id).relation_name into _table_name;
        select row_id.pk_value::text into pk;

        execute 'delete from ' || quote_ident(_schema_name) || '.' || quote_ident(_table_name) ||
                ' where ' || (
                    select quote_ident(c.name) || ' = ' || quote_literal(pk) || '::' || c.type_name
                    from meta.relation_column c
                    where schema_name = _schema_name
                       and relation_name = _table_name
                       and name = (row_id).pk_column_name
                );

        return '{}';
    end;

$$
language plpgsql;

/****************************************************************************************************
 * FUNCTION rows_delete                                                                             *
 ****************************************************************************************************/

create or replace function endpoint.rows_delete(
    relation_id meta.relation_id,
    args json
) returns json as $$

    declare
        _schema_name text;
        _table_name text;
        pk text;
        suffix text;

    begin
        select (relation_id).schema_name into _schema_name;
        select (relation_id).relation_name into _table_name;

        -- Suffix
        select endpoint.suffix_clause(args) into suffix;

        execute 'delete from ' || quote_ident(_schema_name) || '.' || quote_ident(_table_name) || ' ' || suffix;

        return '{}';
    end;

$$
language plpgsql;


/****************************************************************************************************
 * path conversion functions for row_id, relation_id, field_id
 ****************************************************************************************************/

/*
 * Function: urldecode_arr
 * Author: Marc Mamin
 * Source: PostgreSQL Tricks (http://postgres.cz/wiki/postgresql_sql_tricks#function_for_decoding_of_url_code)
 * Decode URLs
 */
create or replace function endpoint.urldecode_arr(url text)
returns text as $$
begin
  return
   (with str as (select case when $1 ~ '^%[0-9a-fa-f][0-9a-fa-f]' then array[''] end
                                      || regexp_split_to_array ($1, '(%[0-9a-fa-f][0-9a-fa-f])+', 'i') plain,
                       array(select (regexp_matches ($1, '((?:%[0-9a-fa-f][0-9a-fa-f])+)', 'gi'))[1]) encoded)
     select  coalesce(string_agg(plain[i] || coalesce( convert_from(decode(replace(encoded[i], '%',''), 'hex'), 'utf8'), ''), ''), $1)
        from str,
             (select  generate_series(1, array_upper(encoded,1) + 2) i from str) blah);
end
$$ language plpgsql immutable strict;


------------------------------ function

create or replace function endpoint.path_to_function_id(value text) returns meta.function_id as $$
select meta.function_id(
    endpoint.urldecode_arr((string_to_array(value, '/'))[1]::text), -- schema name
    endpoint.urldecode_arr((string_to_array(value, '/'))[2]::text), -- function name
    endpoint.urldecode_arr((string_to_array(value, '/'))[3]::text)::text[] -- array of ordered parameter types, e.g. {uuid,text,text}
)
$$ immutable language sql;

create or replace function endpoint.function_id_to_path(value meta.function_id) returns text as $$
select (value).schema_name || '/' ||
    (value).name || '/' ||
    (value).parameters::text
$$ immutable language sql;


------------------------------ relation

create or replace function endpoint.path_to_relation_id(value text) returns meta.relation_id as $$
select meta.relation_id(
    endpoint.urldecode_arr((string_to_array(value, '/'))[1]::text), -- Schema name
    endpoint.urldecode_arr((string_to_array(value, '/'))[2]::text) -- Relation name
)
$$ immutable language sql;

create or replace function endpoint.relation_id_to_path(value meta.relation_id) returns text as $$
select (value).schema_name || '/' || value.name
$$ immutable language sql;


------------------------------ field

create or replace function endpoint.path_to_field_id(value text) returns meta.field_id as $$
declare
    parts text[];
    schema_name text;
    relation_name text;
    pk_value text;
    column_name text;
    pk_column_name text;
begin
    select string_to_array(value, '/') into parts;
    select endpoint.urldecode_arr(parts[1]::text) into schema_name;
    select endpoint.urldecode_arr(parts[2]::text) into relation_name;
    select endpoint.urldecode_arr(parts[3]::text) into pk_column_name;
    select endpoint.urldecode_arr(parts[4]::text) into pk_value;
    select endpoint.urldecode_arr(parts[5]::text) into column_name;

    return meta.field_id(
        schema_name,
        relation_name,
        pk_column_name,
        pk_value,
        column_name
    );

end;
$$ immutable language plpgsql;

create or replace function endpoint.field_id_to_path(value meta.field_id) returns text as $$
select (value).schema_name || '/' ||
    (value).relation_name || '/' ||
    (value).pk_column_name || '/' ||
    (value).pk_value || '/' ||
    (value).column_name
$$ immutable language sql;


------------------------------ row

create or replace function endpoint.path_to_row_id(value text) returns meta.row_id as $$
declare
    parts text[];
    schema_name text;
    relation_name text;
    pk_value text;
    pk_column_name text;
begin
    select string_to_array(value, '/') into parts;
    select endpoint.urldecode_arr(parts[1]::text) into schema_name;
    select endpoint.urldecode_arr(parts[2]::text) into relation_name;
    select endpoint.urldecode_arr(parts[3]::text) into pk_column_name;
    select endpoint.urldecode_arr(parts[4]::text) into pk_value;

    return meta.row_id(
        schema_name,
        relation_name,
        pk_column_name,
        pk_value
    );

end;
$$ immutable language plpgsql;



/****************************************************************************************************
request (version, verb, path, query_args, post_data)

A request is routed to one of the following:
  - endpoint.request (/endpoint/{version}/...)
  - endpoint.resource.path (/some_file.html)
  - endpoint.resource_binary (/some_image.gif)
  - endpoint.resource_function (/$path/to/$some/url_pattern)
  - endpoint.template (WIP) (?)

Here, endpoint.request just handles REST requests.  Routing decision tree is as follows:
  1) What is the "op", the entity that is being interacted with:
        /endpoint/row/{row_id}
        /endpoint/relation/{relation_id}
        /endpoint/function/{function_id}
        /endpoint/field/{field_id}
  2) What is the verb?
  - GET
  - POST
  - PATCH
  - DELETE
  3) What arguments are being passed?
  - array
  - object





 ****************************************************************************************************/

create or replace function endpoint.request(
    version text,
    verb text,
    path text,
    query_args json,
    post_data json,
    out status integer,
    out message text,
    out response text,
    out mimetype text
) returns setof record as $$

    declare
        session_id uuid; -- null if not evented
        row_id meta.row_id;
        relation_id meta.relation_id;
        function_id meta.function_id;
        field_id meta.field_id;
        relation_subscribable boolean;
        op text;
        op_params text;

        -- GET STACK DIAGNOSTICS vars
        v_state text;
        v_msg text;
        v_detail text;
        v_hint text;
        v_context text;
        exception_msg text;

    begin
        set local search_path = endpoint,meta,public;

        -- GET/POST requests are synonymous. Long query strings are converted to POST in the client
        if verb = 'GET' then

            -- Look for session_id in query string
            select btrim(json_array_elements_text, '"')::uuid
            from json_array_elements_text(query_args->'session_id')
            into session_id;

        elsif verb = 'POST' then

            -- Look for session_id in post data
            select btrim(json_array_elements_text, '"')::uuid
            from json_array_elements_text(post_data->'session_id')
            into session_id;

        end if;

        op := substring(path from '([^/]+)(/{1})'); -- row, relation, function, etc.
        op_params := substring(path from char_length(op) + 2); -- everything after {op}/

        raise notice '##### endpoint.request % % %', version, verb, path;
        raise notice '##### op and params: % %', op, op_params;
        raise notice '##### query string args: %', query_args::text;
        raise notice '##### POST data: %', post_data::text;

        case op
        ------------------------------ row
        when 'row' then

            -- URL /endpoint/row/{row_id}
            row_id := endpoint.path_to_row_id(op_params);

            if verb = 'GET' then

                -- Subscribe to row
                if session_id is not null then
                    perform event.subscribe_row(session_id, row_id);
                end if;

                -- Get single row
                return query select 200, 'OK'::text, (select endpoint.row_select(row_id, query_args))::text, 'application/json'::text;

            elsif verb = 'POST' then

                -- Subscribe to row
                if session_id is not null then
                    perform event.subscribe_row(session_id, row_id);
                end if;

                -- Get single row
                return query select 200, 'OK'::text, (select endpoint.row_select(row_id, post_data))::text, 'application/json'::text;

            elsif verb = 'PATCH' then

                -- Update row
                return query select 200, 'OK'::text, (select endpoint.row_update(row_id, post_data))::text, 'application/json'::text;

            elsif verb = 'DELETE' then

                -- Delete row
                return query select 200, 'OK'::text, (select endpoint.row_delete(row_id))::text, 'application/json'::text;

            else
                -- HTTP method not allowed for this resource: 405
                return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;
            end if;


        ------------------------------ relation

        when 'relation' then

            -- URL /endpoint/relation/{relation_id}
            relation_id := endpoint.path_to_row_id(op_params);

            if verb = 'GET' then

                -- Subscribe to relation
                if session_id is not null then

                    -- TODO: Fix when views become subscribable
                    -- If relation is subscribable
                    select type='BASE TABLE' from meta.relation where id = relation_id into relation_subscribable;
                    if relation_subscribable then
                        perform event.subscribe_table(session_id, relation_id);
                    end if;

                end if;

                -- Get rows
                return query select 200, 'OK'::text, (select endpoint.rows_select(relation_id, query_args))::text, 'application/json'::text;

            elsif verb = 'POST' then

                -- Subscribe to relation
                if session_id is not null then

                    -- TODO: Fix when views become subscribable
                    -- If relation is subscribable
                    select type='BASE TABLE' from meta.relation where id = relation_id into relation_subscribable;
                    if relation_subscribable then
                        perform event.subscribe_table(session_id, relation_id);
                    end if;

                end if;

                -- Get rows
                return query select 200, 'OK'::text, (select endpoint.rows_select(relation_id, post_data))::text, 'application/json'::text;

            elsif verb = 'PATCH' then

                if json_typeof(post_data) = 'object' then
                    -- Insert single row
                    return query select 200, 'OK'::text, (select endpoint.row_insert(relation_id, post_data))::text, 'application/json'::text;
                elsif json_typeof(post_data) = 'array' then
                    -- Insert multiple rows
                    return query select 200, 'OK'::text, (select endpoint.multiple_row_insert(relation_id, post_data))::text, 'application/json'::text;
                end if;

            elsif verb = 'DELETE' then

                -- Delete rows
                return query select 200, 'OK'::text, (select endpoint.rows_delete(relation_id, query_args))::text, 'application/json'::text;

            else
                -- HTTP method not allowed for this resource: 405
                return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;
            end if;

        ------------------------------ function
        
        when 'function' then
            -- If function is called without a parameter type list
            if array_length((string_to_array(op_params, '/')), 1) = 2 then

                op_params := op_params || '/{}';
                function_id := endpoint.path_to_function_id(op_params);

                if verb = 'GET' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.anonymous_rows_select_function((function_id).schema_name, function_id.name, query_args) as rsf;

                elsif verb = 'POST' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.anonymous_rows_select_function((function_id).schema_name, function_id.name, post_data) as rsf;

                else
                    -- HTTP method not allowed for this resource: 405
                    return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;

                end if;

            -- Calling a function with a specified parameter type list -- Exact function id known -- is this ever used??
            else

                -- URL /endpoint/function/{function_id}
                function_id := endpoint.path_to_function_id(op_params);

                if verb = 'GET' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.rows_select_function(function_id, query_args) as rsf;

                elsif verb = 'POST' then
                    -- Get record from function call
                    return query select 200, 'OK'::text, rsf.result::text, rsf.mimetype::text from endpoint.rows_select_function(function_id, post_data) as rsf;

                else
                    -- HTTP method not allowed for this resource: 405
                    return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;

                end if;

            end if;

        ------------------------------ field
        when 'field' then

            -- URL /endpoint/field/{field_id}
            field_id := endpoint.path_to_field_id(op_params);

            if verb = 'GET' or verb = 'POST' then

                -- Subscribe to field
                if session_id is not null then
                    perform event.subscribe_field(session_id, field_id);
                end if;

                -- Get field
                return query select 200, 'OK'::text, fs.field::text, fs.mimetype::text from endpoint.field_select(field_id) as fs;

            else
                -- HTTP method not allowed for this resource: 405
                return query select 405, 'Method Not Allowed'::text, ('{"status_code": 405, "title": "Method not allowed"}')::text, 'application/json'::text;
            end if;

        else
            -- Resource not found: 404
            return query select 404, 'Not Found'::text, ('{"status_code": 404, "title": "Not Found"}')::text, 'application/json'::text;

        end case;

    exception
/*
        when undefined_table then
            return query select 404, 'Not Found'::text, ('{"status_code": 404, "title": "Not Found", "message":"'|| replace(SQLERRM, '"', '\"') || '; '|| replace(SQLSTATE, '"', '\"') ||'"}')::text, 'application/json'::text;
*/

        when others then
            GET STACKED DIAGNOSTICS
                v_state   = RETURNED_SQLSTATE,
                v_msg     = MESSAGE_TEXT,
                v_detail  = PG_EXCEPTION_DETAIL,
                v_hint    = PG_EXCEPTION_HINT,
                v_context = PG_EXCEPTION_CONTEXT;

            exception_msg := json_build_object(
                'state', v_state,
                'message', v_msg,
                'detail', v_detail,
                'context', v_context,
                'sqlerr', SQLERRM,
                'sqlstate', SQLSTATE
            )::text;

            raise warning '%', exception_msg;
                return query select
                    500,
                    'Server Error'::text,
                    ('{ "status_code": 500, "title": "Server Error", "message": ' || exception_msg || '}')::text,
                    'application/json'::text;
    end;
$$
language plpgsql;








/******************************************************************************
 * endpoint.register
 ******************************************************************************/

/*
create or replace function endpoint.register (_email text,
    _password text,
    fullname text default '',
    send_email boolean default true,
    out code integer,
    out message text,
    out role_name text
) returns record language plpgsql strict security definer
as $$

    declare
	_user_row record;
        _role_id meta.role_id;

    begin
        begin
            insert into endpoint.user (email, name, active) values (_email, fullname, false) returning * into _user_row;
        exception when others then
            code := 1;
            message := 'A user with this email address already exists';
            role_name := null;
            return;
        end;

        select (_user_row.role_id).name into _role_id;

        -- Set role password
        update meta.role set password = _password where id = _role_id;

        -- Inherit from generic user
        insert into meta.role_inheritance (role_id, member_role_id) values (meta.role_id('user'), _role_id);

        -- Send email to {email}
/*
        if send_email = true then
            perform email.send(
                (select smtp_server_id from endpoint.site_settings where active=true),
                (select auth_from_email from endpoint.site_settings where active=true),
                array[_user_row.email],
                'Activate your new account',
                'Use this code to activate your account ' || _user_row.activation_code
            );
        end if;
*/

        code := 0;
        role_name := (_role_id).name;
        message := 'Success';
    end
$$;
*/

/******************************************************************************
 * endpoint.register_confirm
 ******************************************************************************/

/*
create or replace function endpoint.register_confirm (_email text, _confirmation_code text, send_email boolean default true) returns void
    language plpgsql strict security definer
as $$

    declare
        _user_row record;
        _role_id meta.role_id;

    begin
        -- 1. check for existing user.  throw exceptions for
          -- a. non-matching code
        execute 'select * from endpoint.user where email=' || quote_literal(_email) || ' and activation_code=' || quote_literal(_confirmation_code) into _user_row;
        if _user_row is null then
            raise exception 'Invalid confirmation code';
        end if;

          -- b. already active user
        if _user_row.active then
            raise exception 'User already activated';
        end if;


        -- 2. update user set active=true;
        update endpoint.user set active=true, activation_code=null::uuid where email=_email and activation_code=_confirmation_code::uuid returning (role_id).name into _role_id;


        -- 3. update role set login=true
        update meta.role set can_login = true where id = _role_id;

        -- 4. send email?
/*
        if send_email then
            perform email.send(
                (select smtp_server_id from endpoint.site_settings where active=true),
                (select auth_from_email from endpoint.site_settings where active=true),
                array[_user_row.email],
                'Welcome!',
                'Your account is now active.'
            );
        end if;
* /

        return;
    end
$$;

*/

 */
/******************************************************************************
 * endpoint.register_superuser
 ******************************************************************************/

/*
create or replace function endpoint.register_superuser (
    _email text,
    _password text,
    fullname text,
    role_name text,
    out code integer,
    out message text
) returns record language plpgsql
as $$
    begin
        begin
            insert into endpoint.user (email, name, active, role_id) values (_email, fullname, true, meta.role_id(role_name));
        exception when others then
            code := 1;
            message := 'A user with this email address or role already exists';
            role_name := null;
            return;
        end;

        -- Set role password and superuser
        update meta.role
            set superuser=true, password = _password
            where id = meta.role_id(role_name);

        -- Inherit from generic user
        insert into meta.role_inheritance (role_id, member_role_id)values (meta.role_id('user'), meta.role_id(role_name));

        code := 0;
        message := 'Success';
    end
$$;
*/

/******************************************************************************
 * endpoint.login
 ******************************************************************************/

/*
create or replace function endpoint.login (_email text, _password text) returns uuid
    language plpgsql strict security definer
as $$

    declare
        _role_name text;
        _encrypted_password text;
        _session_id uuid := null;

    begin
        -- Build encrypted password by getting role name associated with this email
        select 'md5' || md5(_password || (role_id).name) from endpoint.user where email=_email into _encrypted_password;

        -- Email does not exists in endpoint.user table
        if _encrypted_password is null then
            raise exception 'No user with this email';
        end if;

        -- Look for role with this password
        execute 'select rolname from pg_catalog.pg_authid where rolpassword = ' || quote_literal(_encrypted_password) into _role_name;

        -- _role_name is null if rolpassword does not exist in pg_catalog.pg_auth_id table -- invalid password

        -- Create cookie session for this role/user
        if _role_name is not null then
            insert into endpoint.session (role_id, user_id)values (meta.role_id(_role_name), (select id from endpoint.user where email=_email))returning id into _session_id;
        end if;

        -- Return cookie
        return _session_id;
    end
$$;
*/

/******************************************************************************
 * endpoint.logout
 ******************************************************************************/

/*
create or replace function endpoint.logout (_email text) returns void
    language sql strict security definer
as $$
    -- Should this delete all sessions associated with this user? I think so
    delete from endpoint.session where user_id = (select id from endpoint."user" where email = _email);
$$;
*/

/******************************************************************************
 * endpoint.superuser
 ******************************************************************************/
/*
create or replace function endpoint.superuser (_email text) returns void
    language sql strict security invoker
as $$
    insert into meta.role_inheritance (role_name, member_role_name) values ('aquameta', (select (role_id).name from endpoint."user" where email=_email));
    update meta.role set superuser=true where name=(select (role_id).name from endpoint."user" where email=_email);
$$;
*/

/******************************************************************************
 * endpoint.email
 ******************************************************************************/

/*
create or replace function endpoint.email (from_email text, to_email text[], subject text, body text) returns void as $$

# -- Import smtplib for the actual sending function
import smtplib
from email.mime.text import MIMEText

# -- Create the container (outer) email message.
msg = MIMEText(body)
msg['Subject'] = subject
msg['From'] = from_email
msg['To'] = ', '.join(to_email)

# -- Send the email via our own SMTP server.
s = smtplib.SMTP("localhost")
s.sendmail(from_email, to_email, msg.as_string())
s.quit()

$$ language plpythonu;
*/



/*******************************************************************************
 * template stuff
 * templates can be invoked in two ways:
 *
 * - via template_route
 * - from one template, via a call to the template() function
 *
 */


/*******************************************************************************
 * bundled_template()
 * grabs a template by bundle_name + name
 *******************************************************************************/

/*
create or replace function endpoint.bundled_template (
    bundle_name text,
    template_name text
) returns setof endpoint.template as $$
        select t.*
        from bundle.bundle b
            join bundle.tracked_row tr on tr.bundle_id=b.id
            join endpoint.template t on t.id = (tr.row_id).pk_value::uuid
        where ((tr.row_id)::meta.schema_id).name = 'endpoint'
            and ((tr.row_id)::meta.relation_id).name = 'template'
            and t.name=template_name
            and b.name = bundle_name
$$ language sql;
*/


/*******************************************************************************
 * FUNCTION template_render
 * Renders a template
 *******************************************************************************/

/*
create or replace function endpoint.template_render(
    template_id uuid,
    route_args json default '{}', -- these are the args passed in from the template_route record
    url_args json default '[]' -- these are args that matched a regex part in parentheses
) returns text as $$
    // fetch the template
    var template;
    try {
        var template_rows = plv8.execute('select * from endpoint.template where id=$1', [ template_id ]);
        template_row = template_rows[0];
        plv8.elog(NOTICE, ' template is ' + template_row.id);
    }
    catch( e ) {
        plv8.elog( ERROR, e, e);
        return false;
    }
    plv8.elog(NOTICE, 'template '+template_row.name+' called with route_args '+JSON.stringify(route_args)+', url_args'+JSON.stringify(url_args));

    // setup javascript scope
    var context = {};
    // url_args is an array of vals extracted from the matching url_pattern
    context.url_args = url_args;
    // route_args is an object passed in from template_route.args json
    for (var key in route_args) { context[key] = route_args[key]; }
    plv8.elog(NOTICE, 'context set to '+JSON.stringify(context));

    // doT.js
    var doT_rows = plv8.execute("select * from endpoint.js_module where name='doT'");
    eval( doT_rows[0].code );
    // context.doT = doT;


    plv8.elog(NOTICE, 'done with doT');

    // aquameta-template-plv8
    var aq_template = plv8.execute("select * from endpoint.js_module where name='aquameta-template-plv8'");
    eval( aq_template[0].code );
    // import template() funciton into context, so doT can see it
    context.template = AQ.Template.template;
    plv8.elog(NOTICE, 'done with template: '+template_row.id);


    // render the template
    var htmlTemplate = doT.template(template_row.content);
    var html = htmlTemplate(context);
    plv8.elog(NOTICE, 'html = '+html);

    return html;
$$ language plv8;

*/


/*******************************************************************************
* FUNCTION template_render
* Renders a template
*******************************************************************************/

/*

this will be called by the client-side template lib, whenever that's completed.

create or replace function endpoint.template_render(
    bundle_name text,
    template_name text,
    args json default '{}'
) returns text as $$
    // eval doT.js
    var doT_rows = plv8.execute("select * from endpoint.plv8_module where name='doT' and version='1.1.0'");
    eval(doT_rows[0].code);


    return template( bundle_name, template_name, args);
$$ language plv8;
*/
