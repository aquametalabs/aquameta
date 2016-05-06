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

function($, endpoint, widget, other deps) {
    function(id, name, input1, input2, ...etc, views) {
        var w = $('#'+id);

        // post_js

        // sourceMap='/widget/lkdjsf/post_js'
    }
}

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

/*******************************************************************************
* Widget.js
*
* Created by Aquameta Labs, an open source company in Portland Oregon, USA.
* Company: http://aquameta.com/
* Project: http://blog.aquameta.com/
******************************************************************************/
(function(window, $, doT, AQ, undefined) {
    'use strict';

    var retrieve_promises = {};
    var prepare_promises = {};
    widget.namespaces = {};

    doT.templateSettings.strip = false;

    var caches = {};
    if('WeakMap' in window) {
        caches.input_defaults = new WeakMap();
        caches.pre_js = new WeakMap();
        caches.html = new WeakMap();
        caches.css = new WeakMap();
        caches.post_js = new WeakMap();
    }



    function widget( name, input, callback ) {

        if (!name || typeof name != 'string') {
            throw "in call to widget, name argument is invalid or missing";
        }

        var context = typeof input != 'undefined' ? Object.assign({}, input) : {};
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
                var retrieve_promise = retrieve_promises[context.name];
            }
            else {
                var retrieve_promise = widget.retrieve(context.namespace, context.name);
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

        // TODO: This will have to be a sweet lookup of widget through bundle and head_db_stage
        widget.namespaces[namespace] = endpoint.schema('widget').table('widget').rows();

    };



    widget.retrieve = function( namespace, name ) {

        return widget.namespaces[namespace]
            .then(function(rows) {

                // Get the correct widget
                //console.log('widget namespace rows', name, rows);
                return rows.where('name', name, true);

            }).then(function(row) {

                //console.log('using this row for a widget!', row);
                if(!row) {
                    throw 'Widget does not exist';
                }

                // Boot off to all related widget data
                return Promise.all([
                    row,
                    row.related_rows('id', 'widget.input', 'widget_id'),
                    row.related_rows('id', 'widget.widget_view', 'widget_id')
                        .then(function(widget_view) {

                            if (!widget_view) {
                                return null;
                            }
                            var db = row.relation.schema.database;
                            var view_id = widget_view.get('view_id');
                            return db.schema(view_id.schema_id.name).view(view_id.name);

                        }), // This may need .bind(this)
                    row.related_rows('id', 'widget.widget_dependency_js', 'widget_id')
                        .then(function(dep_js) {

                            if (!dep_js) {
                                return null;
                            }
                            return dep_js.related_row('dependency_js_id', 'widget.dependency_js', 'id')

                        })
                ]);

            });
    };



    widget.prepare = function( retrieve_promise, context, callback ) {
        //console.log('args to prepare', arguments);
        return retrieve_promise.then(function( widget_data ) {

            //console.log('retrieve_promise resolved', widget_data);

            var widget_row = widget_data[0];
            var inputs = widget_data[1];
            var views = widget_data[2];
            var deps_js = widget_data[3];

            // Do some preparation
            // Process inputs
            if (inputs != null) {
                for (var i = 0; i < inputs.length; i++) {
                    var input_name = inputs[i].get('name');

                    if(typeof context[input_name] != 'undefined') {
                        if(inputs[i].get('optional')) {
                            context[input_name] = cached_get_or_create('input_defaults', inputs[i], function() {
                                var default_code = inputs[i].get('default_value');

                                try {
                                    if(default_code) {
                                        return eval('(' + default_code + ')');
                                    }
                                    else {
                                        return undefined;
                                    }
                                }
                                catch (e) {
                                    console.error("Widget default eval failure", input_row.field('default_value').value);
                                    throw e;
                                }
                            });
                        }
                        else {
                            error('Missing required input ' + input_name, context.name, 'Inputs');
                        }
                    }
                }
            }

            // Load views into context
            if (views != null) {
                for (var i = 0; i < views.length; i++) {
                    context[views[i].schema.name + '_' + views[i].name] = views[i];
                }
            }

            // Deps?
            if (deps_js != null) {
                for (var i = 0; i < deps_js; i++) {
                    try {
                        var dep_js = eval(deps_js[i].get('content'));
                        // Cache this
                    }
                    catch(e) {
                        error(e, context.name, 'DEP_JS Could not load dep' + dep_js[i].get('name') + ':' + dep_js[i].get('version'));
                    }
                }
            }

            var rendered_widget = widget.render(widget_row, context);
            var post_js_function = widget.create_post_js_function(widget_row, context, deps_js);

            // Return rendered widget and post_js function
            return {
                html: rendered_widget,
                widget_id: context.id,
                post_js: post_js_function,
                callback: callback
            };

        });
    };



    widget.render = function( widget_row, context ) {

        //console.log('render params', arguments);

        // Create html template
        var html_template = cached_get_or_create('html', widget_row, function() {
            return doT.template(widget_row.get('html') || '');
        });

        // Compile html template
        try {
            var html = html_template(context);
        } catch(e) {
            error(e, context.name, 'HTML');
        }

        //var help = widget_row.get('help');

        // Render html
        try {
            var rendered = $(html).attr('data-widget', context.name)
                .attr('data-widget_id', context.id);
                /*
                .data('inputs', inputs)
                .data('help', help);
                */
        } catch(e) {
            error(e, context.name, 'HTML (adding data-* attributes)');
        }
                                
        // If CSS exists and has not yet been applied
        if (widget_row.get('css') != null && $('style[data-widget="' + context.name + '"]').length == 0) {

            // Create css template
            var css_template = cached_get_or_create('css', widget_row, function() {
                return doT.template(widget_row.get('css') || '');
            });

            // Try to run css template
            try {
                var css = css_template(context);
            } catch(e) {
                error(e, context.name, 'CSS');
            }

            // Add css to dom
            $('<style type="text/css" data-widget="' + context.name + '">' + css + '</style>').appendTo(document.head);
        }

        return rendered;
    };



    widget.create_post_js_function = function( widget_row, context, deps_js ) {
        // Create post_js function with deps, inputs, views, required deps, sourceMap

        //return function() { console.log('post_js called'); };

        // This may become a common function between all calls to the same widget
        // Then inputs will all come in on the input argument

        // First we'll do proof of tech by supporting the old argument method

        var post_js = cached_get_or_create('post_js', widget_row, function() {

            var context_keys = Object.keys(context).sort();

            try {
                var js_code = Function.apply(null, context_keys.concat([
                        '\n\nvar w = $("#"+id);\n\n' +
                        widget_row.get('post_js') +
                        '\n\n//# sourceURL=' + widget_row.get('id') + '/' + widget_row.get('name') + '/post_js\n\n'
                    ])
                );
                /*
                var js_code = Function(
                    '(function(' + context_keys.join(',') + ') { \n' +
                        'var w = $("#"+id);\n\n' +
                        widget_row.get('post_js') +
                        '\n//# sourceURL=' + widget_row.get('id') + '/' + widget_row.get('name') + '/post_js\n' +
                    '}).apply(null, this.context_vals);'
                );
                */
            }
            catch(e) {
                error(e, widget_row.get('name'), 'Creating post_js function');
            }

            //console.log('my js code', js_code);

            // Pass inputs into js_code function

            var dep_keys = [];
            if (deps_js != null) {
                dep_keys.concat[deps_js];
                /*
                for (var i = 0; i < deps_js.length; i++) {
                    dep_keys.push(deps_js[i]);
                    //dep_keys.push(deps_js[i].get('variable') || 'non_amd_module');
                }
                */
            }

            Object.assign(dep_keys, {
                '$': $,
                db: widget_row.relation.schema.database,
                endpoint: widget_row.relation.schema.database, // to be removed
                widget: widget,
                AQ: AQ
            });

            dep_keys.sort();

            /*
            try {
                var post_js_with_inputs = Function.apply(null, Object.keys(context).sort().concat([ js_code ]));
                    //'(function() { \n' + Object.keys(// _.keys(context).sort().join(', ') + ') { \n' +
                        //js_code +
                    //'\n }).apply(null, this.context_vals);'
                //]));
            }
            catch(e) {
                error(e, widget_row.get('name'), 'Creating post_js function');
            }
            */

            return {
                fn: js_code,
                context_keys: context_keys,
                dep_keys: dep_keys
            };

        });

        // Get context values
        var context_vals = [];
        for (var i = 0; i < post_js.context_keys.length; i++) {
            context_vals.push( context[post_js.context_keys[i]] );
        }

        // Get dependency values
        var dep_vals = [];
        for (var i = 0; i < post_js.dep_keys.length; i++) {
            dep_vals.push( dependencies[post_js.dep_keys[i]] );
        }

        return function() { post_js.fn.apply(null, context_vals) }.bind(this);

    };



    widget.swap = function( $element, id ) {

        prepare_promises[id].then(function(rendered_widget) {

            //console.log('prepare_promise resolved', rendered_widget);

            // Replace stub
            $element.replaceWith(rendered_widget.html);

            // Run post_js - or this may have to be done with a script tag appended to the widget
            rendered_widget.post_js();

            var w = $('#' + rendered_widget.widget_id);

            // Call widget callback
            if(rendered_widget.callback) {
                rendered_widget.callback(w);
            }

            // Trigger widget_loaded? Necessary?
            // w.trigger('widget_loaded', w);

            // Delete prepeared_promise
            delete prepare_promises[id];
        });
    };



    widget.purge_cache = function( widget_name ) {
        return widget.retrieve(widget_name).then(function(resources) {
            delete retrieve_promises[widget_name];
            //delete prepare_promises[widget_name];

            if('WeakMap' in window) {
                caches.input_defaults.delete(resources.widget_row)
                caches.pre_js.delete(resources.widget_row);
                caches.html.delete(resources.widget_row);
                caches.css.delete(resources.widget_row);
                caches.post_js.delete(resources.widget_row);
                console.log("Cache cleared.");
            }
        });
    };



    function uuid() {
        var d = new Date().getTime();
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = (d + Math.random()*16)%16 | 0;
            d = Math.floor(d/16);
            return (c=='x' ? r : (r&0x7|0x8)).toString(16);
        });
    }



    function error( err, widget_name, step_name ) {
        console.error("widget('" + widget_name + "', ...) " + step_name + " failed!");
        throw err;
    }



    function cached_get_or_create( cache_name, cache_key, create_func ) {
        if(cache_name in caches && caches[cache_name].has(cache_key)) {
            var r = caches[cache_name].get(cache_key);
        }
        else {
            var r = create_func();
            if(cache_name in caches) caches[cache_name].set(cache_key, r);
        }
        return r;
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

    window.widget = widget;
}(window, jQuery, doT, AQ));

