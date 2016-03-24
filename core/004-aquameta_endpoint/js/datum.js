console.log('Aquameta Datum.js - Copyright(c) 2015 - Aquameta Labs');

/*
 * Aquameta Datum.js
 * 
 * This API enables CRUD operation and function calls against a Aquameta's 
 * PostgreSQL/REST interface.  Because every operation in Aquameta is either 
 * a funciton call or some form of simple data manipulation, this API should
 * be sufficient to access everything Aquameta can do.
 * 
 * That means:
 * - It is not an ORM.
 * - It does not enable execution of raw SQL.
 * - It is not meant to expose the features of PostgreSQL. 
 * - It does not introspect the table structure of the database.
 * 
 * It does two things only:
 * 
 * 1. CRUD:
 * - read data from specified relations, optionally sorting and filtering it.
 * - insert, update and delete data from specified relations.
 * 
 * 2. FUNCTION CALLS
 * - call database functions and hand back the function's result data
 * 
 * With only this you can programming.
 * 
 * 
 * Example usage:
 * 
 * var db = AQ.Database('/endpoint');
 * db.schema('beehive').table('customers_customer').rows({
 *     id: 3,
 *     limit: 50,
 *     offset: 50,
 *     where: ...
 *     order_by: ...
 *     events: true,
 * });
 * 
 */

var AQ = AQ || {};

/**************************************************************************
* Database
**************************************************************************/

AQ.Database = function( url, settings ) {
    this.url = url;
    this.settings = settings;

    // Chain
    this.schema = function( name )         { return new AQ.Schema(this, name); }


    return this;
}




/*
 * Schema
 */

AQ.Schema = function( db, name ) {
    // Self
    this.db = db;
    this.name = name;
    this.id = function()                   { return { 'name': this.name }; }
    this.meta_row = function()             { return db.schema('meta').relation('schema').row({ id: this.id() }); }

    // Chain
    this.table = function( name )          { return new AQ.Table(this, name); }
    this.view = function( name )           { return new AQ.View(this, name); }
    this.relation = function( name )       { return new AQ.Relation(this, name); }
    this.function = function( name, args ) { return new AQ.Function(this, name, args); }


    return this;
}





/*
 * Relation
 * Base class for Table, View, Function
 * 
 */

AQ.Relation = function( schema, name ) {
    // Self
    this.db = schema.db;
    this.schema = schema;
    this.name = name;
    this.id = function()                 { return { schema_id: this.schema.id(), name: name }; }
    this.meta_row = function()           { return db.schema('meta').table('relation').row({ id: this.id() }); }

    // Chain
    this.row = function( options )       { return new AQ.RowFactory(this, 'select', options); }
    this.rows = function( options )      { return new AQ.RowSetFactory(this, 'select', options); }


    return this;
}


/*
 * Table subclasses Relation
 * 
 * https://developer.mozilla.org/en-US/docs/Web/JavaScript/Introduction_to_Object-Oriented_JavaScript
 * 
 */
AQ.Table = function ( schema, name ) { AQ.Relation.call(this, schema, name); }
AQ.Table.prototype = Object.create(AQ.Table.prototype);
AQ.Table.prototype.constructor = AQ.Table;

// Table.insert ( values )
AQ.Table.prototype.insert = function ( values ) { return new AQ.RowFactory(this, 'insert', values) }



/*
 * View subclasses Relation
 * 
 */
AQ.View = function( schema, name ) { AQ.Relation.call(this, schema, name); }
AQ.View.prototype = Object.create(AQ.View.prototype);
AQ.View.prototype.constructor = AQ.View;

// View.poll
AQ.View.prototype.poll = function ( interval ) {
    // ?
}

/*
 * Function subclasses Relation
 * 
 */
AQ.Function = function( schema, name) { /* ? */ }
AQ.Function.prototype = Object.create(AQ.Function.prototype);
AQ.Function.prototype.constructor = AQ.Function;





/**
 * RowSetFactory
 * 
 * Holds a reference to a set of rows in the database.
 * 
 * ARGUMENTS:
 * 
 * relation: the source of the rows
 * action:  the action that produced the rows
 * options: any filters on the rows such as limit, where, etc.
 *
 * - Can be resolved via it's .done() method, which return a promise
 *   of an actual RowSet object.
 * - Can be the beginning (or middle) of a chain, that a related_row(s)
 *   call branches off of.
 * - The methods .related_row() / .related_rows() can be called even if
 *   it is resolved.
 * - Stacking them together unresolved will start to build a JoinGraph
 *   request, so rows from multiple tables can all be resolved via one
 *   JoinGraph request.
 * 
 * Methods that place orders to this factory:
 *   - Relation.rows()
 *   - Table.rows()
 *   - View.rows()
 *   - Function.rows()
 */

AQ.RowSetFactory = function( relation, action, options ) {
    this.result = false;

    this.related_row = function( self_column_name, related_relation_name, related_column_name ) {
    }

    this.related_rows = function( self_column_name, related_relation_name, related_column_name ) {
        if (this.result) {
            this.result.then(function() {
                return new RowSetFactory (related_relation_name, 'select', {
                    // where: { related_column_name + ' in ': results.each()...
                });
            });
        }
    }
    
    // this.url = f

    
    this.done = function() {
        
        // create promise for a RowSet
        this.result = new Promise(function(resolve, reject) {
            // construct request URL
            var url = relation.db.url + '/' +
                relation.schema.name + '/' +
                relation.type + '/' +
                relation.name + '/rows';

            // add query string argslk
            if (typeof options != 'undefined')
                url += AQ.filterURI(options);

            console.log("Requesting URL: ", url);
            $.ajax({
                url: url,
                type: 'PATCH',
                // data: values,
                success: function(response) {
                    resolve (new AQ.RowSet(relation, action, options, response));
                }
            }).fail(reject);

        });
        return this.result;
    }
}




/**
 * RowFactory
 * returned by .row()
 * 
 * - Holds a reference to a row.  
 * - Can be resolved via it's .done() method, which return a promise of an actual Row object.
 * - Can be the beginning (or middle) of a chain, that a related_row(s) call branches off of.
 * 
 */

AQ.RowFactory = function( relation, action, options ) {
    this.url = function() {}
    this.column = function( name ) {
    }
}




/**************************************************************************
* Row and RowSet
**************************************************************************/

// Row
AQ.Row = function( relation, options ) {
    this.db = relation.db;
    this.schema_name = relation.schema_name;
    this.relation_name = relation;
    this.pk_column_name = pk_column_name;
    this.pk_value = pk_value;

    this.related_row = function( self_column_name, related_relation_name, related_column_name ) {

    }

    this.related_row = function( self_column_name, related_relation_name, related_column_name ) {

    }

    // Update

    this.update = function ( values ) {
        console.log("UPDATE! ", values);
    }



    // Delete

    this.delete = function ( options ) {
        console.log("DELETE! ", options);
    }

    return this;
}


// RowSet
AQ.RowSet = function( relation, data ) {
    console.log('RowSet data: ', data);
    return this;
}










/**
* RelationFilter
* Encapsulates all the options that can be passed with a relation request to filter and sort results.
**/

AQ.filterURI = function( options ) {
    var uri_args = '';

    function addArg( key, val ) {
        if (uri_args != '') uri_args += '&';
        else uri_args += '?';

        uri_args += encodeURIComponent(key) + '=' + encodeURIComponent(val);
    }

    // add each option to the URI
    $.each(options, function(key, val) {
        switch(key) {
            case 'id':
                addArg(key, val);
                break;
            case 'order_by':
                addArg(key, val);
                break;
            case 'limit':
                addArg(key, val);
                break;
            case 'offset':
                addArg(key, val);
                break;
            case 'where':
                addArg(key, val);
                break;
            default:
                console.log('Unrecognized filter option will be ignored: '+key);
                break;
        }
    });

    return uri_args;
}






/* from update 

        return new Promise(function(resolve, reject) {
            var url = row.db.url + '/' + row.schema.name + '/table/' + row.name + '/row/' + row.pk_value;

            // add query string args
            if (typeof options != 'undefined')
                url += AQ.filterURI(options);

            console.log("Requesting URL: ", url);
            $.patch({
                url: url,
                data: values,
                success: function(response) {
                    resolve (new AQ.Row(relation, response));
                }
            }).fail(reject);

        });    


*/
