/*******************************************************************************
 * Datum.js
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/
define(['/jQuery.min.js', '/underscore.min.js'], function($, _, undefined) {

    'use strict';
    var AQ = AQ || {};

    function Endpoint( url, evented ) {

        this.url = url;
        this.evented = false;
        this.cache = {};
        if(this.evented) {
        }

        function build_query_string( options ) {

            if(typeof options == 'undefined') return '';

            var return_url = '',
                argsCount = 0;

            if (typeof options.where !== 'undefined') { // where: { 'column_name': 'value' }
                if (!argsCount) return_url += '?';
                if (typeof options.where.length == 'undefined') options.where = [options.where];
                for (var i = 0; i < options.where.length; i++) {
                    var where = options.where[i];
                    if (argsCount++) return_url += '&';
                    return_url += 'where=' + encodeURIComponent(JSON.stringify(where));
                }
            }
            if (typeof options.order_by !== 'undefined') { // order_by: [{ 'column_name': 'asc|desc' }]
                if (!argsCount) return_url += '?';
                if (typeof options.order_by.length == 'undefined') options.order_by = [options.order_by];
                for (var i = 0; i < options.order_by; i++) {
                    var order_by = options.order_by[i];
                    if (argsCount++) return_url += '&';
                    return_url += 'order_by=' + (typeof order_by['column'] !== 'undefined' && order_by['direction'] == 'asc') ? '+' : '-';
                    return_url += encodeURIComponent(order_by['column']);
                }
            }
            if (typeof options.limit !== 'undefined') { // limit: number
                if (!argsCount) return_url += '?';
                var parsedLimit = parseInt(options.limit);
                if (!isNaN(parsedLimit)) {
                    if (argsCount++) return_url += '&';
                    return_url += 'limit=' + parsedLimit;
                }
            }
            if (typeof options.offset !== 'undefined') { // offset: number
                if (!argsCount) return_url += '?';
                var parsedOffset = parseInt(options.offset);
                if (!isNaN(parsedOffset)) {
                    if (argsCount++) return_url += '&';
                    return_url += 'offset=' + parsedOffset;
                }
            }
            if (typeof options.args !== 'undefined') { // args: object
                if (!argsCount) return_url += '?';
                if (argsCount++) return_url += '&';
                return_url += 'args=' + encodeURIComponent(JSON.stringify(options.args));
            }
            return return_url;
        }

        var create_session = function() {

            connect_socket()
            .then(function(socket) {
                return socket.send_method('request')
            })
            .then(function(socket) {
                return socket.send_method('session_attach');
            })
            .catch(function(error) {
                console.log(error);
            });

        };

        // Sends thenable socket, whether it had to be created or not
        var connect_socket = function() { return new WebSocket(); };

        // Boolean, whether socket is connected or not
        var socket_connected = function() { return false; };

        // Grabs current connection and sends method
        var socket_send = function(message) { return; }; 

        var resource = function( method, meta_id, args, data, use_cache ) {

            // Default use_cache to false
            use_cache = use_cache || false;

            // URLs
            var url_without_query = url + meta_id.to_url();
            var url_with_query = url_without_query + build_query_string(args);

            // Check cache
            if (use_cache && url_with_query in this.cache) {
                return this.cache[url_with_query];
            }

            // If this connection is evented, get event session_id
            if (this.evented && typeof args['session_id'] == 'undefined') {
                args['session_id'] = document.cookie.replace(/(?:(?:^|.*;\s*)SESSION\s*\=\s*([^;]*).*$)|^.*$/, "$1");
            }

            // Send websocket method if this connection uses websocket
            if (socket_connected()) {
                return socket_send({
                        verb: method,
                        uri: url_without_query,
                        query: args,
                        data: data
                    });
            }

            // If query string is too long, upgrade GET method to POST
            if(method == 'GET' && (location.host + url_with_query).length > 1000) {
                method = 'POST';
            }

            // This makes the uWSGI server send back json errors
            var headers = new Headers();
            headers.append('Content-Type', 'application/json');

            // Settings object to send with 'fetch' method
            var init_obj = {
                method: method,
                headers: headers
            };

            // Don't add data on GET requests
            if (method != 'GET') {
                init_obj.body = JSON.stringify(data);
            }

            var request = fetch(method == 'GET' ? url_with_query : url_without_query, init_obj)
                .then(function(response) {

                    // Read json stream
                    var json = response.json();

                    if (response.status >= 200 && response.status < 300) {
                        return json;
                    }

                    // If bad request (code 300 or higher), reject promise
                    return json.then(Promise.reject.bind(Promise));

                }).catch(function(error) {

                    // Log error in collapsed group
                    console.groupCollapsed(method, error.status_code, error.title);
                    console.error(error.message);
                    console.groupEnd();
                    return null;

                }.bind(this));

            if (use_cache && (method == 'GET' || method == 'POST')) {
                this.cache[url_with_query] = request;
            }

            return request;
        }

        return {
            get: function( meta_id, args, use_cache )        { return resource.call(this, 'GET', meta_id, args, {}, use_cache); }.bind(this),
            post: function( meta_id, data, use_cache )       { return resource.call(this, 'POST', meta_id, {}, data, use_cache); }.bind(this),
            patch: function( meta_id, data )                 { return resource.call(this, 'PATCH', meta_id, {}, data); }.bind(this),
            delete: function( meta_id, args )                { return resource.call(this, 'DELETE', meta_id, args); }.bind(this)
        };
    }

    /**
     * for checking object equality for meta id composite types
     * function id_object_equality(obj1, obj2) {
     *
     * @param {(AQ.CompositeType,Object)} obj1
     * @param {(AQ.CompositeType,Object)} obj2
     * @returns {Boolean} Whether obj1 equals obj2
     */
    AQ.equals = function( obj1, obj2 ) {
        if (obj1 instanceof AQ.CompositeType && obj2 instanceof AQ.CompositeType) {
            return obj1.equals(obj2);
        }
        else if (obj1 instanceof Object && obj2 instanceof Object) {
            return _.isEqual.apply(this, arguments);
        }
        else {
            return obj1 === obj2;
        }
    }

    /**
     * ---------------------------------
     * Database
     * ---------------------------------
     */
    AQ.Database = function( url, settings, ready_callback ) {
        this.url = url;
        this.settings = settings;

        // Not sure which name is better
        this.endpoint = this.connection = new Endpoint(this.url);

        if(this.settings.evented != 'no') {

            this.connection.create_session()
            .catch(function(conn) {

                if(this.settings.evented == 'yes') {
                    throw 'Websocket connection refused';
                }

                // if this.settings.evented == 'try', fail silently

            }.bind(this));
        }
    };
    AQ.Database.prototype.constructor = AQ.Database;
    AQ.Database.prototype.schema = function( name ) { return new AQ.Schema(this, name); };

    /**
     * Shortcut method to get a relation from a relation_id
     * 
     *  var table = db.relation(relation_id);
     *
     *  In lieu of:
     *
     *  var table;
     *  db.schema('meta').view('relation').row('id', row.get('relation_id'))
     *  .result(function(relation_row) {
     *      table = schema(relation_row.get('schema_name')).relation(relation_row.get('name'));
     *  });
     *
     * @param {[AQ.RelationID,Object]} relation_id
     * @returns {AQ.Relation}
     */
    AQ.Database.prototype.relation = function( relation_id ) {
        if (relation_id instanceof AQ.RelationID) {

            // think more about this
            return new AQ.Schema(relation_id.schema().name()).relation(relation_id.name());

            // wouldn't this be the appropriate way to write this?
            // return relation_id.schema().relation(relation_id.name());
        }
        else {
            // Ordinary object
            return new AQ.Schema(relation_id.schema_id.name).relation(relation_id.name);
        }
    };

    /*
     * Shortcut method to get a row from a row_id
     *
     * @param {[AQ.RowID,Object]} row_id
     * @returns {AQ.Row}
     */
    AQ.Database.prototype.row = function( row_id ) {
        if (row_id instanceof AQ.RowID) {

            return new AQ.Schema(row_id.relation().schema().name()).relation(row_id.relation().name()).row(row_id);

            // and this too?
            return row_id.relation().row(row_id);

        }
        else {
            // Ordinary object
            return new AQ.Schema(row_id.relation_id.schema_id.name).relation(row_id.relation_id.name).row(row_id.pk_column_name, row_id.pk_value);
        }
    };

    /**
     * ---------------------------------
     * Schema
     * ---------------------------------
     */
    AQ.Schema = function( database, name ) {
        this.database = database;
        this.name = name;
        this.id = new AQ.SchemaID(this);
    };
    AQ.Schema.prototype.constructor = AQ.Schema;
    AQ.Schema.prototype.relation = function( name )         { return new AQ.Relation(this, name); };
    AQ.Schema.prototype.table = function( name )            { return new AQ.Table(this, name); };
    AQ.Schema.prototype.view = function( name )             { return new AQ.View(this, name); };
    AQ.Schema.prototype.function = function( name, args )   { return new AQ.Function(this, name, args); };

    /**
     * ---------------------------------
     * Relation
     * ---------------------------------
     */
    AQ.Relation = function( schema, name ) {
        this.schema = schema;
        this.name = name;
        this.id = new AQ.RelationID(this);
    };
    AQ.Relation.prototype.constructor = AQ.Relation;
    AQ.Relation.prototype.rows = function( options ) {
        return this.schema.database.endpoint.get(this.id, options, options.use_cache)
            .then(function(rows) {

                if (rows == null || rows.result.length < 1) {
                    return null;
                }
                return new AQ.Rowset(this, rows);

            }.bind(this));
    };
    AQ.Relation.prototype.row = function() {
        var args = {};
        var use_cache = false;

        // 2 different ways to call 'row' function
        if (arguments.length == 1) {
            // options object
            var obj = arguments[0];

            if (typeof obj['where'] != 'undefined') {
                args.where = obj.where;
            }
            else {
                args.where = obj;
            }

            if (typeof obj['use_cache'] != 'undefined') {
                use_cache = obj['use_cache'];
            }

        }
        else if (arguments.length >= 2) {
            // column_name and value
            var name = arguments[0];
            var value = arguments[1];
            use_cache = arguments[2] || false;

            args.where = { name: name, op: '=', value: value };

        }
        else {
            throw 'Unsupported call to AQ.Relation.row()';
        }

        return this.schema.database.endpoint.get(this.id, args, use_cache)
            .then(function(row) {

                if (row == null || row.result.length != 1) {
                    return null;
                }
                return new AQ.Row(this, row);

            }.bind(this));
    };

    /**
     * ---------------------------------
     * Table
     * ---------------------------------
     */
    AQ.Table = function( schema, name ) {
        this.schema = schema;
        this.name = name;
        this.id = new AQ.RelationID(this);
    };
    AQ.Table.prototype = Object.create(AQ.Relation.prototype);
    AQ.Table.prototype.constructor = AQ.Table;
    AQ.Table.prototype.insert = function( data ) {

        var insert_promise = this.schema.database.endpoint.patch(this.id, data);

        // Return inserted row promise
        return insert_promise.then(function(inserted_row) {

            if (inserted_row == null) {
                return null;
            }
            if (typeof data.length != 'undefined' && data.length > 1) {
                return new AQ.Rowset(this, inserted_row);
            }
            return new AQ.Row(this, inserted_row);

        }.bind(this));

    };

    /**
     * ---------------------------------
     * View
     * ---------------------------------
     */
    AQ.View = function( schema, name ) {
        this.schema = schema;
        this.name = name;
        this.id = new AQ.RelationID(this);
    };
    AQ.View.prototype = Object.create(AQ.Relation.prototype);
    AQ.View.prototype.constructor = AQ.View;

    /**
     * ---------------------------------
     * Rowset
     * ---------------------------------
     */
    AQ.Rowset = function( relation, response ) {
        this.relation = relation;
        this.columns = response.columns;
        this.rows = response.result;
    };
    AQ.Rowset.prototype.constructor = AQ.Rowset;

    AQ.Rowset.prototype.map = function(fn) {
        return this.rows.map(function(row) {
            return new AQ.Row(this.relation, { columns: this.columns, result: [ row ] });
        }.bind(this)).map(fn);
    };

    AQ.Rowset.prototype.forEach = function(fn) {
        return this.rows.map(function(row) {
            return new AQ.Row(this.relation, { columns: this.columns, result: [ row ] });
        }.bind(this)).forEach(fn);
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
            var new_rowset = _.filter(this.rows, function(el) {
                return AQ.equals.call(this, el[field], val);
            });
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
        var ordered = _.sortBy(this.rows, function(el) {
            return el.row[column];
        });
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
        
    AQ.Rowset.prototype.related_rows = function( self_column_name, related_relation_name, related_column_name, use_cache ) {

        var relation_parts = related_relation_name.split('.');
        if (relation_parts.length < 2) {
            console.error("Related relation name must be schema qualified (schema_name.relation_name)");
            // throw "Related relation name must be schema qualified (schema_name.relation_name)";
        }

        var schema_name = relation_parts[0];
        var relation_name = relation_parts[1];

        var values = [];
        for (var i = 0; i < this.rows.length; i++) {
            values.push(this.rows[i].row[self_column_name]);
        }

        var options = {
            where: {
                name: related_column_name,
                op: 'in',
                value: values
            },
            use_cache: use_cache || false
        };

        var db = this.relation.schema.database;
        return db.schema(schema_name).relation(relation_name).rows(options);
    };

    AQ.Rowset.prototype.related_row = function( self_column_name, related_relation_name, related_column_name, use_cache ) {

        var relation_parts = related_relation_name.split('.');
        if (relation_parts.length < 2) {
            console.error("Related relation name must be schema qualified (schema_name.relation_name)");
            // throw "Related relation name must be schema qualified (schema_name.relation_name)";
        }

        var schema_name = relation_parts[0];
        var relation_name = relation_parts[1];

        var values = [];
        for (var i = 0; i < this.rows.length; i++) {
            values.push(this.rows[i].row[self_column_name]);
        }

        var options = {
            where: {
                name: related_column_name,
                op: 'in',
                value: values
            },
            use_cache: use_cache || false
        };

        var db = this.relation.schema.database;
        return db.schema(schema_name).relation(relation_name).row(options);

    };

    /**
     * ---------------------------------
     * Row
     * ---------------------------------
     */
    AQ.Row = function( relation, response ) {
        this.relation = relation;
        this.row_data = response.result[0].row;
        this.columns = response.columns;
        this.id = new AQ.RowID(this);
        this.pk_value = this.row_data.id; // TODO hardcoded
        this.pk_column_name = null; // TODO this too
        this.pk = function() { return; }; // ?
    };
    AQ.Row.prototype = {
        constructor: AQ.Row,
        get: function( name )           { return this.row_data[name]; },
        set: function( name, value )    { this.row_data[name] = value; return this; },
        to_string: function()           { return JSON.stringify(this.row_data); },
        field: function( name )         { return new AQ.Field(this, name); }
    };

    AQ.Row.prototype.update = function() {
        return this.relation.schema.database.endpoint.patch(this.id, this.row_data)
            .then(function(response) {

                if(response == null) {
                    return null;
                }
                return this;

            }.bind(this));
    };

    AQ.Row.prototype.delete = function() { 
        return this.relation.schema.database.endpoint.delete(this.id)
            .then(function(response) {

                if(response == null) {
                    return null;
                }
                return true;

            });
    };

    AQ.Row.prototype.related_rows = function( self_column_name, related_relation_name, related_column_name, use_cache )  {

        var relation_parts = related_relation_name.split('.');
        if (relation_parts.length < 2) {
            console.error("Related relation name must be schema qualified (schema_name.relation_name)");
            // throw "Related relation name must be schema qualified (schema_name.relation_name)";
        }

        var schema_name = relation_parts[0];
        var relation_name = relation_parts[1];

        var options = {
            where: {
                name: related_column_name,
                op: '=',
                value: this.get(self_column_name)
            },
            use_cache: use_cache || false
        };

        var db = this.relation.schema.database;
        return db.schema(schema_name).relation(relation_name).rows(options);
    };

    AQ.Row.prototype.related_row = function( self_column_name, related_relation_name, related_column_name, use_cache ) {

        var relation_parts = related_relation_name.split('.');
        if (relation_parts.length < 2) {
            console.error("Related relation name must be schema qualified (schema_name.relation_name)");
            // throw "Related relation name must be schema qualified (schema_name.relation_name)";
        }

        var schema_name = relation_parts[0];
        var relation_name = relation_parts[1];
        var db = this.relation.schema.database;
        var options = {
            where: {
                name: related_column_name,
                op: '=',
                value: this.get(self_column_name)
            },
            use_cache: use_cache || false
        };
        return db.schema(schema_name).relation(relation_name).row(options);
    };

    /**
     * ---------------------------------
     * Column
     * ---------------------------------
     */
    AQ.Column = function( relation, name ) {
        this.relation = relation;
        this.name = name;
        this.id = new AQ.ColumnID(this);
    };
    AQ.Column.prototype.constructor = AQ.Column;

    /**
     * ---------------------------------
     * Field
     * ---------------------------------
     */
    AQ.Field = function( row, name ) {
        this.row = row;
        this.column = new AQ.Column(row.relation, name);
        this.name = name;
        this.value = row.get(name);
        this.id = new AQ.FieldID(this);
    };
    AQ.Field.prototype = {
        constructor: AQ.Field,
        update: function()       { return this.row.update(); }
    };

    /**
     * ---------------------------------
     * Function
     * ---------------------------------
     */
    AQ.Function = function( schema, name, args ) {
        this.schema = schema;
        this.name = name;

        if(args instanceof Array) {
            this.args = '{' + args.join(',') + '}';
        }
        else {
            this.args = args;
        }

        this.id = new AQ.FunctionID(this);

    };
    AQ.Function.prototype.constructor = AQ.Function;
    AQ.Function.prototype.call = function(fn_args) {

/*
some_function?args={ vals: [] } -- Array
some_function?args={ kwargs: {} } -- Key/value object
some_function?args={ kwargs: {} }&column=name
*/

        var options_obj = { args: {} };

        if (fn_args instanceof Array) {
            options_obj.args.vals = fn_args;
        }

        return this.schema.database.endpoint.get(this.id, options_obj)
            .then(function(response) {

                if(response == null) {
                    return null;
                }
                return response;

            });
    };

    /**
     * ---------------------------------
     * CompositeType Base
     * ---------------------------------
     */
    AQ.CompositeType = function( obj ) {
        this.json = obj;
    };
    AQ.CompositeType.prototype = {
        constructor: AQ.CompositeType,
        isCompositeType: function()     { return true; },
        to_json: function()             { return this.json; },
        to_string: function()           { return JSON.stringify(this.json); },
    };
        /* Could do some multi dimension thing? Not sure if this means anything
        get: function(key)              { return this.json[key]; },
        set: function(key, value)       { return this.json[key] = value; },
        */

    /**
     * ---------------------------------
     * SchemaID
     * ---------------------------------
     */
    AQ.SchemaID = function( schema ) {
        this.schema = schema;
        this.json = { name: schema.name };
    };
    AQ.SchemaID.prototype = Object.create(AQ.CompositeType.prototype);
    AQ.SchemaID.prototype.constructor = AQ.SchemaID;
    AQ.SchemaID.prototype.equals = function (that) {
        return ( that instanceof AQ.Schema || that instanceof AQ.SchemaID ) ?
            this.name === that.name :
            _.isEqual(this, that);
    };

    /**
     * ---------------------------------
     * RelationID
     * ---------------------------------
     */
    AQ.RelationID = function( relation ) {
        this.relation = relation;
        this.json = { schema_id: this.relation.schema.id.to_json(), name: this.relation.name };
    };
    AQ.RelationID.prototype = Object.create(AQ.CompositeType.prototype);
    AQ.RelationID.prototype.constructor = AQ.RelationID;
    AQ.RelationID.prototype.to_url = function() {
        return '/relation/' + this.relation.schema.name + '/' + this.relation.name;
    };
    AQ.RelationID.prototype.equals = function (that) {
        return ( that instanceof AQ.Relation || that instanceof AQ.RelationID ) ?
            ( this.schema_id.equals(that.schema.id) && this.name === that.name ) :
            _.isEqual(this, that);
    };

    /**
     * ---------------------------------
     * RowID
     * ---------------------------------
     */
    AQ.RowID = function( row ) {
        this.row = row;
        this.json = { relation_id: row.relation.id.json, pk_column_name: row.pk_column_name, pk_value: row.pk_value }; 
    };
    AQ.RowID.prototype = Object.create(AQ.CompositeType.prototype);
    AQ.RowID.prototype.constructor = AQ.RowID;
    AQ.RowID.prototype.to_url = function() {
        return '/row/' + this.row.relation.schema.name + '/' + this.row.relation.name + '/' + this.row.pk_value;
    };
    AQ.RowID.prototype.equals = function (that) {
        return ( that instanceof AQ.Row || that instanceof AQ.RowID ) ?
            ( this.row.relation.id.equals(that.relation.id) && this.row.pk_column_name === that.pk_column_name && this.row.pk_value === that.pk_value ) :
            _.isEqual(this, that);
    };

    /**
     * ---------------------------------
     * ColumnID
     * ---------------------------------
     */
    AQ.ColumnID = function( column ) {
        this.column = column;
        this.json = { relation_id: column.relation.id.json, name: column.name };
    };
    AQ.ColumnID.prototype = Object.create(AQ.CompositeType.prototype);
    AQ.ColumnID.prototype.constructor = AQ.ColumnID;
    AQ.ColumnID.prototype.equals = function (that) {
        return ( that instanceof AQ.Column || that instanceof AQ.ColumnID ) ?
            ( this.relation_id.equals(that.relation.id) && this.name === that.name ) :
            _.isEqual(this, that);
    };

    /**
     * ---------------------------------
     * FieldID
     * ---------------------------------
     */
    AQ.FieldID = function( field ) {
        this.field = field;
        this.json = { row_id: field.row.id.json, column_id: field.column.id.json };
    };
    AQ.FieldID.prototype = Object.create(AQ.CompositeType.prototype);
    AQ.FieldID.prototype.constuctor = AQ.FieldID;
    AQ.FieldID.prototype.to_url = function() {
        return '/field/' + this.field.row.relation.schema.name + '/' + this.field.row.relation.name + '/' + this.field.row.pk_value + '/' + this.field.column.name;
    };
    AQ.FieldID.prototype.equals = function (that) {
        return ( that instanceof AQ.Field || that instanceof AQ.FieldID ) ?
            ( this.field.row.id.equals(that.row.id) && this.name === that.name ) :
            _.isEqual(this, that);
    };

    /**
     * ---------------------------------
     * FunctionID
     * ---------------------------------
     */
    AQ.FunctionID = function( fn ) {
        this.fn = fn;
        this.json = { schema_id: fn.schema.id.json, name: fn.name, args: fn.args };
    };
    AQ.FunctionID.prototype = Object.create(AQ.CompositeType.prototype);
    AQ.FunctionID.prototype.constructor = AQ.FunctionID;
    AQ.FunctionID.prototype.to_url = function() {
        return '/function/' + this.fn.schema.name + '/' + this.fn.name + '/' + this.fn.args;
    };
    AQ.FunctionID.prototype.equals = function (that) {
        return ( that instanceof AQ.Function || that instanceof AQ.FunctionID ) ?
            // TODO: the rest of function id comparison logic
            ( this.schema_id.equals(that.schema.id) && false ) :
            _.isEqual(this, that);
    };

    window.AQ = AQ;
    return AQ;

});
