/*
widget.js
---------

a widget is:

- dom element
- unique id
- data-widget-name attribute
- data-widget-id attribute
- args link?


widget() function
-----------------

function widget(selector, args, callback) {}

pipeline:

- fetch widget data
    * widget
    * widget_input
    * widget_dependency_js
    * widget_view
    * widget_import?  would be importing widgets from other bundles via data instead of widget_import()
    * ...plugins...
- inject css into header (avoiding duplication...?)
- parse html string w/ template parser (DoT? is there a better choice here?)
- process inputs
    * validate required inputs
    * how to distinguish between "supported" inputs and just random ones?
- setup javascript scope if present
    * widget()
    * widget_name
    * widget_id
    * input{}
    * xinput{}
    * view{ customers: RowSet }
    * dep{}
    * endpoint (that the widget was loaded from)
- (nice to have) trick the script source tracker to think that the widget code is at the post_js field's URL so we get nice source maps?
- wait for the html to be inserted onto the page????  is this why we used mutation observers?
- run the javascript
- call callback
- return html string



Widget Selector DSL Grammar

1. Import Mode - import a widget into the widget name dsl's namespace

// from bh import *
function widget_import( bundle_name, local_namespace )
widget_import('com.aquameta.beehive', 'bh')

// import *
// is this feature going to collide with the "evolving dsl" below?  probably.  but it simplifies dev environment a lot (true?)
widget_import('com.aquameta.beehive', '' )

// ^^ should these be ui?  probably

// use imported widget namespace

widget('bh:pallet_planner', { default_pallet_count: 22 });


// 2. Evolving dsl for looking up widgets in cool ways
// use/edit/integer
// use/display/temperature
// ...?

widget('/use/edit/integer', { value: 5 })

*/

function uuid() {
    var d = new Date().getTime();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = (d + Math.random()*16)%16 | 0;
        d = Math.floor(d/16);
        return (c=='x' ? r : (r&0x7|0x8)).toString(16);
    });
}

var retrieve_promises = {};
var prepare_promises = {};
widget.namespaces = {};


function widget( name, input, callback ) {

    var context = typeof input != 'undefined' ? Object.create(input) : {};
    context.id = uuid();

    // However we define this
    if (typeof is_dsl_lookup != 'undefined' && is_dsl_lookup == true) {
        // Whatever the DSL lookup is
    }
    else {

        var name_parts = name.split(':');

        if (name_parts.length == 1) {
            // Default namespace lookup
            context.namespace = '';
            context.name = name_parts[0];
        }
        else {
            // Namespaced lookup
            context.namespace = name_parts[0];
            context.name = name_parts[1];
        }

        //console.log(context);

        // Go get this widget - retrieve_promises don't change for calls to the same widget - they are cached by the widget name
        if (context.name in retrieve_promises) {
            retrieve_promise = retrieve_promises[context.name];
        }
        else {
            retrieve_promise = widget.retrieve(context.namespace, context.name);
        }
    }

    // Prepare and render the widget - each prepare_promise is unique because inputs are different - they are cached by the unique uuid created for the context
    prepare_promises[context.id] = widget.prepare(retrieve_promise, context, callback);

    // Return script that calls swap
    return '<script id="widget-stub_' + context.id  + '" data-widget_id="' + context.id + '">' +
              'widget.swap($("#widget-stub_' +  context.id  + '"), "' + context.id + '");'  + 
           '</script>';

}

widget.import = function( bundle_name, namespace, endpoint ) {
    // This will have to be a sweet lookup of widget through bundle and head_db_stage
    widget.namespaces[namespace] = endpoint.schema('widget').table('widget').rows();
};

widget.retrieve = function( namespace, name ) {

    return widget.namespaces[namespace]
        .then(function(rows) {

            //console.log('widget namespace rows', name, rows);
            return rows.where('name', name, true);

        }).then(function(row) {

            //console.log('using this row for a widget!', row);
            if(!row) {
                throw 'Widget does not exist';
            }

            return Promise.all(
                row.related_rows('id', 'widget.widget_view', 'widget_id'),
                row.related_rows('id', 'widget.input', 'widget_id'),
                row.related_rows('id', 'widget.widget_dependency_js', 'widget_id')
                    .then(function(dep_js) {
                        return dep_js.related_row('dependency_js_id', 'widget.dependency_js', 'id')
                    })
            );

        });
};

widget.prepare = function( retrieve_promise, context, callback ) {
    console.log('args to prepare', arguments);
    return retrieve_promise.then(function( widget_data ) {
        console.log('my widget data', widget_data);
    });
};

widget.swap = function( $el, id ) {
    console.log('swapping widgets', retrieve_promises, prepare_promises);
    prepare_promises[id].then(function(widget_data) {

        // Replace stub
        $el.replaceWith(widget_data.rendered_widget);

        // Run post_js
        widget_data.post_js();

        var w = $('#' + widget_data.widget_id);

        // Call widget callback
        if(widget_data.callback) {
            widget_data.callback(w);
        }

        // Trigger widget_loaded? Necessary?
        w.trigger('widget_loaded', w);

        // Delete prepeared_promise
        delete widget.prepare_promises[id];
    });
};


function error( err, widget_name, step_name ) {
    console.error("widget('" + widget_name + "', ...) " + step_name + " failed!");
    throw err;
}


/********************************************************************
COPIED OVER
********************************************************************/
widget.sync = function(rowlist_promise, container, widget_maker, handlers) {
    if(handlers === undefined) {
        handlers = {};
    }

    if (widget_maker === undefined) {
        throw "widget.sync missing widget_maker argument";
    }

    if (container.length < 1) {
      throw "widget.sync failed:  the specified container is empty or not found";
      return;
    }

    if (container.length > 1) {
      throw "widget.sync failed:  the specified container contains multiple elements";
      return;
    }

    if (!container instanceof jQuery) {
      throw "widget.sync failed:  the specified container is not a jQuery object";
      return;
    }

}

