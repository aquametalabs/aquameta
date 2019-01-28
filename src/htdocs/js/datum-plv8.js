var AQ = AQ || {};

AQ.uuid = function() {
    var d = new Date().getTime();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = (d + Math.random()*16)%16 | 0;
        d = Math.floor(d/16);
        return (c=='x' ? r : (r&0x7|0x8)).toString(16);
    });
}


function query_options( options ) {

    var keys = [];

    if (typeof options != 'undefined') {

        // Meta data defaults to true;
        if (typeof options.meta_data == 'undefined') {
            options.meta_data = true;
        }

        // Map the keys of the options object to an array of encoded url components
        Object.keys(options).sort().map(function(key_name) {

            var key = options[key_name];

            switch(key_name) {

                case 'where':
                    // where: { name: 'column_name', op: '=', value: 'value' }
                    // where: [{ name: 'column_name', op: '=', value: 'value' }]
                    if (typeof key.length == 'undefined') key = [key];

                    return key.map(function(where) {
                        return 'where=' + encodeURIComponent(JSON.stringify(where));
                    }).join('&');

                case 'order_by':
                    // So many possibilities...
                    // order_by: '-?column_name'
                    // order_by: ['-?column_name']
                    // order_by: { 'column_name': 'asc|desc' }
                    // order_by: [{ 'column_name': 'asc|desc' }]
                    // order_by: { column: 'column_name', direction: 'asc|desc' }
                    // order_by: [{ column: 'column_name', direction: 'asc|desc' }]
                    if (typeof key.length == 'undefined') key = [key];

                    return key_name + '=' + encodeURIComponent(key.map(function(o,i) {
                        return ((typeof o.direction != 'undefined' && o.direction != 'asc') ? '-' : '') + o.column;
                    }).join(','));

                case 'limit':
                    // limit: number
                case 'offset':
                    // offset: number
                    var parsedNum = parseInt(key);
                    if (!isNaN(parsedNum)) {
                        return key_name + '=' + parsedNum;
                    }
                    return;

                case 'evented':
                    return 'session_id=' + encodeURIComponent(JSON.stringify(key));

                case 'meta_data':
                case 'args':
                case 'exclude':
                case 'include':
                    return key_name + '=' + encodeURIComponent(JSON.stringify(key));
            }
        }

                                        // Remove all undefined elements of the array
                                       ).forEach(function(e) {
            if (typeof e != 'undefined') keys.push(e);
        });
    }

    // Return the query string by joining the array with &'s
    return keys.length ? '?' + keys.join('&') : '?';
}



/*--------------------------------- * Database * ---------------------------------*/
function Endpoint( url ) {

    this.url = url;
    
    var resource = function( method, meta_id, args, data ) {

        args = args || {};

        // URLs
        var id_url = meta_id.to_url(true); // ID part of the URL only
        var url_without_query = this.url + id_url;
        var query_ops = query_options(args);
        var url_with_query = url_without_query + query_ops;

        // Settings object to send with 'fetch' method
        var init_obj = {
            method: method
        };

        // Don't add data on GET requests
        if (method != 'GET') {
            init_obj.body = JSON.stringify(data);
        }

        // var request = fetch(method == 'GET' ? url_with_query : url_without_query, init_obj);
        var request = {
            "then": function(f) {
                return f;
            },
            "catch": function(f) {
                return f;
            }
        }

        var response = plv8.execute('select * from endpoint.request($1,$2,$3,$4,$5)', [
            '0.2',
            method,
            url_without_query,
            JSON.stringify(query_ops),
            '{}'
        ]);

        plv8.elog(WARNING, 'FAT ASS RESPONSE: '+JSON.stringify(response));

        // Read json stream
        /*
        var json = response.json();

        if (response.status >= 200 && response.status < 300) {
            return json;
        }
        */
        
        return request;
    }

/*
	return {
        url: this.url,
        get: function( meta_id, args )        { return resource.call(this, 'GET', meta_id, args); }.bind(this),
        post: function( meta_id, data )       { return resource.call(this, 'POST', meta_id, {}, data); }.bind(this),
            patch: function( meta_id, data )      { return resource.call(this, 'PATCH', meta_id, {}, data); }.bind(this),
                delete: function( meta_id, args )     { return resource.call(this, 'DELETE', meta_id, args); }.bind(this)
};
*/
    return {
        url: this.url,
        get: function( meta_id, args )        { return resource.call(this, 'GET', meta_id, args); }.bind(this),
        post: function( meta_id, data )       { return resource.call(this, 'POST', meta_id, {}, data); }.bind(this),
        patch: function( meta_id, data )      { return resource.call(this, 'PATCH', meta_id, {}, data); }.bind(this),
        delete: function( meta_id, args )     { return resource.call(this, 'DELETE', meta_id, args); }.bind(this)
};
}


/*--------------------------------- * Database * ---------------------------------*/
AQ.Database = function( url, settings ) {
    this.settings = settings;

    // Not sure which name is better
    this.endpoint = this.connection = new Endpoint(url, this.settings.evented);
    this.query_string = query_options;
};
AQ.Database.prototype.constructor = AQ.Database;
AQ.Database.prototype.schema = function( name ) { return new AQ.Schema(this, name); };

/*--------------------------------- * Schema * ---------------------------------*/
AQ.Schema = function( database, name ) {
    this.database = database;
    this.name = name;
    this.id = { name: this.name };
};
AQ.Schema.prototype.constructor = AQ.Schema;
AQ.Schema.prototype.relation = function( name )         { return new AQ.Relation(this, name); };
AQ.Schema.prototype.table = function( name )            { return new AQ.Table(this, name); };
AQ.Schema.prototype.view = function( name )             { return new AQ.View(this, name); };
AQ.Schema.prototype.function = function( identifier, args, options )   {

    // Function identifier (name and parameter list)
    if (typeof identifier == 'object') {
        var name = identifier.name;
        var parameter_type_list = identifier.parameters;
    }
    // Selecting a function without specifying the parameters
    else {
        var name = identifier;
    }

    options = options || {};

    // Arguments
    options.args = {};

    // `args = undefined` will pass no arguments into the server-side function
    if (typeof args != 'undefined') {

        // some_function?args={ kwargs: {} } -- Key/value object
        if (!(args instanceof Array) && args instanceof Object) {
            options.args.kwargs = args;
        }
        // some_function?args={ vals: [] } -- Array
        else {
            if (!(args instanceof Array)) {
                // Regular value is placed into array
                args = [ args ];
            }
            options.args.vals = args;
        }
    }

    var fn = new AQ.Function(this, name, parameter_type_list);

    return this.database.endpoint.get(fn, options)
    .then(function(response) {

        if (!response) {
            throw 'Empty response';
        }
        else if (!response.result.length) {
            throw 'Result set empty';
        }
        if(response.result.length > 1) {
            return new AQ.FunctionResultSet(fn, response);
        }
        return new AQ.FunctionResult(fn, response);

    }.bind(this)).catch(function(err) {
        throw 'Function call request failed: ' + err;
    });
};

/*--------------------------------- * Relation * ---------------------------------*/
AQ.Relation = function( schema, name ) {
    this.schema = schema;
    this.name = name;
    this.id = { schema_id: this.schema.id, name: this.name };
};
AQ.Relation.prototype.constructor = AQ.Relation;
AQ.Relation.prototype.to_url = function( id_only ) {
    return id_only ? '/relation/' + this.schema.name + '/' + this.name :
    this.schema.database.endpoint.url + '/relation/' + this.schema.name + '/' + this.name;
};
AQ.Relation.prototype.column = function( name ) {
    return new AQ.Column(this, name);
};
AQ.Relation.prototype.rows = function( options ) {

    return this.schema.database.endpoint.get(this, options)
    .then(function(rows) {

        if (rows == null) {
            throw 'Empty response';
        }/*
                else if (rows.result.length < 1) {
                    throw 'No rows returned';
                }*/
        return new AQ.Rowset(this, rows, options);

    }.bind(this)).catch(function(err) {
        throw 'Rows request failed: ' + err;
    });
};
AQ.Relation.prototype.row = function() {

    // Multiple different ways to call 'row' function

    // 1. Calling with Options object
    if (typeof arguments[0] == 'object') {

        var obj = arguments[0];
        var args = arguments[1] || {};

        // AQ.Relation.row({ where: { column_name: 'column_name', op: '=', value: 'value' } })
        // Maybe it should be this one: AQ.Relation.row({ where: { column_name: value } })
        if (typeof obj.where != 'undefined') {
            args.where = obj.where;
        }
        // AQ.Relation.row({ column_name: 'column_name', op: '=', value: 'value' })
        // Maybe it should be this one: AQ.Relation.row({ column_name: value })
        else {
            args.where = obj;
        }

    }
    // 2. Calling with column_name and value
    else if (typeof arguments[0] == 'string') {

        // AQ.Relation.row(column_name, value [, options_obj])
        var name = arguments[0];
        var value = arguments[1];
        var args = arguments[2] || {};

        args.where = { name: name, op: '=', value: value };

    }
    // 3. Calling AQ.Relation.row() without arguments
    else {
        var args = {};
    }

    return this.schema.database.endpoint.get(this, args)
    .then(function(row) {

        if (row == null) {
            throw 'Empty response';
        }
        else if (row.result.length == 0) {
            throw 'No row returned';
        }
        else if (row.result.length > 1) {
            throw 'Multiple rows returned';
        }
        return new AQ.Row(this, row);

    }.bind(this)).catch(function(err) {
        throw 'Row request failed: ' + err;
    });
};

/*--------------------------------- * Table * ---------------------------------*/
AQ.Table = function( schema, name ) {
    this.schema = schema;
    this.name = name;
    this.id = { schema_id: this.schema.id, name: this.name };
};
AQ.Table.prototype = Object.create(AQ.Relation.prototype);
AQ.Table.prototype.constructor = AQ.Table;
AQ.Table.prototype.insert = function( data ) {

    if (typeof data == 'undefined') {
        // table.insert({}) is equivalent to table.insert()
        // both will insert default values
        data = {};
    }

    // Return inserted row promise
    return this.schema.database.endpoint.patch(this, data)
    .then(function(inserted_row) {

        if (inserted_row == null) {
            throw 'Empty response';
        }
        if (typeof data.length != 'undefined' && data.length > 1) {
            return new AQ.Rowset(this, inserted_row, null);
        }
        return new AQ.Row(this, inserted_row);

    }.bind(this)).catch(function(err) {
        throw 'Insert failed: ' + err;
    });

};

/*--------------------------------- * View * ---------------------------------*/
AQ.View = function( schema, name ) {
    this.schema = schema;
    this.name = name;
    this.id = { schema_id: this.schema.id, name: this.name };
};
AQ.View.prototype = Object.create(AQ.Relation.prototype);
AQ.View.prototype.constructor = AQ.View;

/*--------------------------------- * Rowset * ---------------------------------*/
AQ.Rowset = function( relation, response, server_arguments ) {
    this.relation = relation;
    this.schema = relation.schema;
    this.columns = response.columns || null;
    this.pk_column_name = response.pk || null;
    this.rows = response.result;
    this.length = response.result.length;
    this.server_arguments = server_arguments || {};
};
AQ.Rowset.prototype.constructor = AQ.Rowset;
AQ.Rowset.prototype.map = function(fn) {
    return this.rows.map(function(row) {
        return new AQ.Row(this.relation, { columns: this.columns, pk: this.pk_column_name, result: [ row ] });
    }.bind(this)).map(fn);
};
AQ.Rowset.prototype.forEach = function(fn) {
    return this.rows.map(function(row) {
        return new AQ.Row(this.relation, { columns: this.columns, pk: this.pk_column_name, result: [ row ] });
    }.bind(this)).forEach(fn);
};
AQ.Rowset.prototype.reload = function() {
    return this.relation.rows(this.server_arguments);
};

/**
     * Call AQ.Rowset.where with (where_obj) or use shorthand notation (field, value) - filter results programmatically
     *
     * @param {Object} where_obj
     * @param {[Boolean]} return_first
     * @param {[Boolean]} async
     *
     * OR
     *
     * @param {String} field
     * @param {Any} value
     * @param {[Boolean]} return_first
     * @param {[Boolean]} async
     *
     * @returns {Promise}
     */
AQ.Rowset.prototype.where = function() {

    var first = false, async = true, where_obj = {};
    if (typeof arguments[0] == 'object') {
        // AQ.Rowset.where(where_obj [, return_first] [, async]);
        where_obj = arguments[0];
        var field = where_obj.field;
        var value = where_obj.value;
        if (arguments.length > 1) first = arguments[1];
        if (arguments.length > 2) async = arguments[2];

    }
    else if (typeof arguments[0] == 'string' && arguments.length > 1) {
        // AQ.Rowset.where(field, value [, return_first] [, async]);
        var field = arguments[0];
        var value = arguments[1];
        if (arguments.length > 2) first = arguments[2];
        if (arguments.length > 3) async = arguments[3];
    }

    return new Promise(function(resolve, reject) {

        // TODO lots of logic here
        // The new rowset that is returned must be in the same format as the response from the server

        if (first) {
            for (var i = 0; i < this.rows.length; i++) {
                if (this.rows[i].row[field] == value) {
                    resolve(new AQ.Row(this.relation, { columns: this.columns, result: [ this.rows[i] ] }));
                }
            }
            reject('could not find ' + field + ' ' + value);
        }
        else {
            var return_rowset = [];
            for (var i = 0; i < this.rows.length; i++) {
                if (this.rows[i].row[field] == value) {
                    return_rowset.push(this.rows[i]);
                }
            }
            resolve(new AQ.Rowset(this.relation, { columns: this.columns, result: return_rowset }));
        }


        // 2

        // maybe we don't need to search the entire row and instead we return the first item found
        /*
            var new_rowset = _.filter(this.rows, function(el) {
                //return AQ.equals.call(this, el[field], val);
            });
*/
        if (new_rowset.length == 1) {
            return new AQ.Row(this.relation, new_rowset);
        }
        else if (new_rowset.length > 1) {
            throw 'Multiple Rows Returned';
        }

        // if row does not exist
        return null;

    }.bind(this));

};
AQ.Rowset.prototype.order_by = function( column, direction ) {
    /*
        var ordered = _.sortBy(this.rows, function(el) {
            return el.row[column];
        });
*/
    if (direction !== 'asc') {
        ordered.reverse();
    }
    return new AQ.Rowset(this.relation, { columns: this.columns, result: ordered });
};
AQ.Rowset.prototype.limit = function( lim ) {
    if (lim <= 0) {
        throw 'Bad limit';
    }
    return new AQ.Rowset(this.relation, { columns: this.columns, result: this.rows.slice(0, lim) });
};
AQ.Rowset.prototype.related_rows = function( self_column_name, related_relation_name, related_column_name, options ) {

    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.relation.schema.database;

    var values = this.map(function(row) {
        return row.get(self_column_name);
    });

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: 'in',
        value: values
    });


    return db.schema(schema_name).relation(relation_name).rows(options);
};
AQ.Rowset.prototype.related_row = function( self_column_name, related_relation_name, related_column_name, options ) {

    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.relation.schema.database;

    var values = this.map(function(row) {
        return row.get(self_column_name);
    });

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: 'in',
        value: values
    });

    return db.schema(schema_name).relation(relation_name).row(options);

};

/*--------------------------------- * Row * ---------------------------------*/
AQ.Row = function( relation, response ) {
    this.relation = relation;
    this.schema = relation.schema;
    this.row_data = response.result[0].row;

    this.cached_fields = {};
    this.columns = response.columns || null;
    this.pk_column_name = null;
    this.pk_value = null;
    this.id = null;
    this.to_url = function() {
        console.error('You must call a row with "meta_data: true" in order to use the to_url function');
        throw 'Datum.js: Programming Error';
    };

    if (typeof response.pk != 'undefined') {
        this.pk_column_name = response.pk;
        this.pk_value = this.get(this.pk_column_name);
        // this.id = {"pk_column_id":{"relation_id":{"schema_id":{"name":this.schema.name},"name":this.relation.name},"name":this.pk_column_name},"pk_value": this.pk_value}
        this.id = {
            pk_column_id: {
                relation_id: this.relation.id,
                name: this.pk_column_name
            },
            pk_value: this.pk_value
        };

        this.to_url = function( id_only ) {
            return id_only ? '/row/' + this.relation.schema.name + '/' + this.relation.name + '/' + /*JSON.stringify(this.pk_value)*/ this.pk_value :
            this.relation.schema.database.endpoint.url + '/row/' + this.relation.schema.name + '/' + this.relation.name + '/' + /*JSON.stringify(this.pk_value)*/ this.pk_value;
        };

    }
};
AQ.Row.prototype = {
    constructor: AQ.Row,
    get: function( name )           { return this.row_data[name]; },
    set: function( name, value )    { this.row_data[name] = value; return this; },
    to_string: function()           { return JSON.stringify(this.row_data); },
    clone: function()               { return new AQ.Row(this.relation, { columns: this.columns, pk: this.pk_column_name, result: [{ row: this.row_data }]}); },
    field: function( name ) {
        if (typeof this.cached_fields[name] == 'undefined') {
            this.cached_fields[name] = new AQ.Field(this, name, name === this.pk_column_name);
        }
        return this.cached_fields[name];
    },
    fields: function() {
        if (this.columns != null) {
            return this.columns.map(function(c) {
                return this.field(c.name);
            }.bind(this));
        }
        return null;
    }
};
AQ.Row.prototype.update = function() {
    return this.relation.schema.database.endpoint.patch(this, this.row_data)
    .then(function(response) {

        if(response == null) {
            throw 'Empty response';
        }
        return this;

    }.bind(this)).catch(function(err) {
        throw 'Update failed: ' + err;
    });
};
AQ.Row.prototype.delete = function() { 
    return this.relation.schema.database.endpoint.delete(this)
    .then(function(response) {

        if(response == null) {
            throw 'Empty response';
        }

    }).catch(function(err) {
        throw 'Delete failed: ' + err;
    });
};
AQ.Row.prototype.related_rows = function( self_column_name, related_relation_name, related_column_name, options )  {

    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.relation.schema.database;

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: '=',
        value: this.get(self_column_name)
    });

    return db.schema(schema_name).relation(relation_name).rows(options);
};
AQ.Row.prototype.related_row = function( self_column_name, related_relation_name, related_column_name, options ) {

    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.relation.schema.database;

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: '=',
        value: this.get(self_column_name)
    });

    return db.schema(schema_name).relation(relation_name).row(options);
};

/*--------------------------------- * Column * ---------------------------------*/
AQ.Column = function( relation, name ) {
    this.relation = relation;
    this.name = name;
    this.id = { relation_id: relation.id, name: name };
};
AQ.Column.prototype.constructor = AQ.Column;

/*--------------------------------- * Field * ---------------------------------*/
AQ.Field = function( row, name, pk ) {
    this.row = row;
    this.column = new AQ.Column(row.relation, name);
    this.is_primary_key = pk;
    this.name = name;
    this.value = row.get(name);
    this.id = { row_id: this.row.id, column_id: this.column.id };
    this.to_url = function( id_only ) {
        if (this.row.pk_value == null) {
            console.error('You must call a row with "meta_data: true" in order to use the to_url function');
            throw 'Datum.js: Programming Error';
        }
        return id_only ? '/field/' + this.row.relation.schema.name + '/' + this.row.relation.name + '/' + /*JSON.stringify(this.row.pk_value)*/ this.row.pk_value + '/' + this.column.name :
        this.row.relation.schema.database.endpoint.url + '/field/' + this.row.relation.schema.name + '/' + this.row.relation.name + '/' + /*JSON.stringify(this.row.pk_value)*/ this.row.pk_value + '/' + this.column.name;
    };
};
AQ.Field.prototype = {
    constructor: AQ.Field,
    get: function()          { return this.row.get(this.name); },
    set: function(value)     { this.value = value; return this.row.set(this.name, value); },
    update: function()       { return this.row.update(); } // TODO: This is wrong
};

/*--------------------------------- * Function * ---------------------------------*/
AQ.Function = function( schema, name, args ) {
    this.schema = schema;
    this.name = name;

    if(args instanceof Array) {
        this.args = '{' + args.join(',') + '}';
    }
    else {
        this.args = args;
    }

    this.id = { schema_id: this.schema.id, name: this.name, args: this.args };
    this.to_url = function( id_only ) {
        var base_url = id_only ? '' : this.schema.database.endpoint.url;
        if (typeof this.args != 'undefined') {
            return base_url + '/function/' + this.schema.name + '/' + this.name + '/' + this.args;
        }
        return base_url + '/function/' + this.schema.name + '/' + this.name;
    };
};
AQ.Function.prototype.constructor = AQ.Function;

/*--------------------------------- * Function Result * ---------------------------------*/
AQ.FunctionResult = function( fn, response ) {
    this.function = fn;
    this.schema = fn.schema;
    this.row_data = response.result[0].row;
    this.rows = response.result;
    this.columns = response.columns;
};
AQ.FunctionResult.prototype = {
    constructor: AQ.FunctionResult,
    get: function( name )           { return this.row_data[name]; },
    to_string: function()           { return JSON.stringify(this.row_data); }
};
AQ.FunctionResult.prototype.map = function(fn) {
    return this.rows.map(function(row) {
        return new AQ.FunctionResult(this.function, { columns: this.columns, result: [ row ] });
    }.bind(this)).map(fn);
};
AQ.FunctionResult.prototype.forEach = function(fn) {
    return this.rows.map(function(row) {
        return new AQ.FunctionResult(this.function, { columns: this.columns, result: [ row ] });
    }.bind(this)).forEach(fn);
};
AQ.FunctionResult.prototype.related_rows = function( self_column_name, related_relation_name, related_column_name, options )  {
    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.function.schema.database;

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: '=',
        value: this.get(self_column_name)
    });

    return db.schema(schema_name).relation(relation_name).rows(options);
};
AQ.FunctionResult.prototype.related_row = function( self_column_name, related_relation_name, related_column_name, options ) {
    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.function.schema.database;

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: '=',
        value: this.get(self_column_name)
    });

    return db.schema(schema_name).relation(relation_name).row(options);
};

/*--------------------------------- * Function Result Set * ---------------------------------*/
AQ.FunctionResultSet = function( fn, response ) {
    this.function = fn;
    this.schema = fn.schema;
    this.columns = response.columns;
    this.rows = response.result;
};
AQ.FunctionResultSet.prototype.constructor = AQ.FunctionResultSet;
AQ.FunctionResultSet.prototype.map = function(fn) {
    return this.rows.map(function(row) {
        return new AQ.FunctionResult(this.function, { columns: this.columns, result: [ row ] });
    }.bind(this)).map(fn);
};
AQ.FunctionResultSet.prototype.forEach = function(fn) {
    return this.rows.map(function(row) {
        return new AQ.FunctionResult(this.function, { columns: this.columns, result: [ row ] });
    }.bind(this)).forEach(fn);
};
AQ.FunctionResultSet.prototype.related_rows = function( self_column_name, related_relation_name, related_column_name, options ) {

    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.function.schema.database;

    var values = this.map(function(row) {
        return row.get(self_column_name);
    });

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: 'in',
        value: values
    });

    return db.schema(schema_name).relation(relation_name).rows(options);
};
AQ.FunctionResultSet.prototype.related_row = function( self_column_name, related_relation_name, related_column_name, options ) {

    var relation_parts = related_relation_name.split('.');
    if (relation_parts.length < 2) {
        console.error("Related relation name must be schema qualified (schema_name.relation_name)");
        // throw "Related relation name must be schema qualified (schema_name.relation_name)";
    }

    var schema_name = relation_parts[0];
    var relation_name = relation_parts[1];
    var db = this.function.schema.database;

    var values = this.map(function(row) {
        return row.get(self_column_name);
    });

    options = options || {};
    options.where = options.where instanceof Array ? options.where : (typeof options.where == 'undefined' ?  [] : [options.where]);
    options.where.push({
        name: related_column_name,
        op: 'in',
        value: values
    });

    return db.schema(schema_name).relation(relation_name).row(options);

};
