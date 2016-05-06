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
define(['/doT.min.js', '/Datum.js'], function(doT, AQ, undefined) {
//(function(window, $, doT, AQ, uuid, undefined) {
    'use strict';

    doT.templateSettings.strip = false;

    var retrieve_promises = {};
    var prepare_promises = {};
    var namespaces = {};


    AQ.Widget = {};


    AQ.Widget.load = function ( name, input, callback ) {

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

            // Go get this widget - retrieve_promises don't change for calls to the same widget - they are cached by the widget name
            if (context.name in retrieve_promises) {
                var retrieve_promise = retrieve_promises[context.name];
            }
            else {
                var retrieve_promise = retrieve(context.namespace, context.name);
            }
        }

        // Prepare and render the widget - each prepare_promise is unique because inputs are different - they are cached by the unique uuid created for the context
        prepare_promises[context.id] = prepare(retrieve_promise, context, callback);

        // Return script that calls swap
        return '<script id="widget-stub_' + context.id  + '" data-widget_id="' + context.id + '">' +
                  'AQ.Widget.swap($("#widget-stub_' +  context.id  + '"), "' + context.id + '");'  + 
               '</script>';

    }



    AQ.Widget.import = function( bundle_name, namespace, endpoint ) {

        // TODO: This will have to be a sweet lookup of widget through bundle and head_db_stage
        namespaces[namespace] = endpoint.schema('widget').table('widget').rows();

    };



    function retrieve( namespace, name ) {

        return namespaces[namespace]
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
                        .then(function(deps_js) {

                            if (!deps_js) {
                                return null;
                            }
                            return deps_js.related_rows('dependency_js_id', 'widget.dependency_js', 'id');

                        }).then(function(deps) {

                            if (!deps) {
                                return [];
                            }

                            var base_url = deps.relation.schema.database.url;
                            return Promise.all(

                                deps.rows.map(function(dep) {
                                    return System.import(base_url + '/field/widget/dependency_js/' + dep.row.id + '/content').then(function(dep_module) {
                                        console.log('my module', dep_module);
                                        return {
                                            url: base_url + '/field/widget/dependency_js/' + dep.row.id + '/content',
                                            name: dep.row.variable || 'non_amd_module',
                                            /* TODO: This value thing is a hack. For some reason, jwerty doesn't load properly here */
                                            value: typeof dep_module == 'object' ? dep_module[Object.keys(dep_module)[0]] : dep_module
                                        };
                                    });
                                })
                            );

                        })
                ]);

            });
    };



    function prepare( retrieve_promise, context, callback ) {
        //console.log('args to prepare', arguments);
        return retrieve_promise.then(function( widget_data ) {

            //console.log('retrieve_promise resolved', widget_data);
            var [ widget_row, inputs, views, deps_js ] = widget_data;

            context = Object.assign({
                    db: widget_row.relation.schema.database,
                    endpoint: widget_row.relation.schema.database
                }, context);

            // Do some preparation
            // Process inputs
            if (inputs != null) {

                for (var i = 0; i < inputs.length; i++) {
                    var input_name = inputs[i].get('name');

                    if(typeof context[input_name] != 'undefined') {
                        if(inputs[i].get('optional')) {
                            context[input_name] = (function() {
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
                            }());
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

            var rendered_widget = render(widget_row, context);
            var post_js_function = create_post_js_function(widget_row, context, deps_js);

            // Return rendered widget and post_js function
            return {
                html: rendered_widget,
                widget_id: context.id,
                post_js: post_js_function,
                callback: callback
            };

        });
    };



    function render( widget_row, context ) {
        //console.log('render params', arguments);

        // Create html template
        var html_template = doT.template(widget_row.get('html') || '');

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
            var css_template = doT.template(widget_row.get('css') || '');

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



    function create_post_js_function( widget_row, context, deps_js ) {

        var context_keys = Object.keys(context).sort();

        // Get context values
        var context_vals = [];
        for (var i = 0; i < context_keys.length; i++) {
            context_vals.push( context[context_keys[i]] );
        }

        var dep_names = [];
        var dep_values = [];
        if (deps_js != null) {
            deps_js.forEach(function(dep_js) {
                dep_names.push(dep_js.name);
                dep_values.push(dep_js.value);
            });
        }

        try {
            /*
            var post_js = Function.apply(context, context_keys.concat([
                    '\n\nvar w = $("#"+id);\n\n' +
                    widget_row.get('post_js') +
                    '\n\n//# sourceURL=' + widget_row.get('id') + '/' + widget_row.get('name') + '/post_js\n\n'
                ])
            );
            */

            /*
            * Creating an script that looks like this
            * function(dep1_name, dep2_name, ...) {
            *   function(input1, input2) {
            *       post_js
            *   }.apply(this.this.context_vals);
            * }.apply(this, this.dep_vals);
            */
            var post_js = Function(
                '(function(' + dep_names.join(',') + ') { \n' +
                    '(function(' + context_keys.join(',') + ') { \n' +
                        'var w = $("#"+id);\n\n' +
                        widget_row.get('post_js') +
                        '\n//# sourceURL=' + widget_row.get('id') + '/' + widget_row.get('name') + '/post_js\n' +
                    '}).apply(this, this.context_vals);' +
                '}).apply(this, this.dep_values);'
            ).bind({ context_vals: context_vals, dep_values: dep_values });
        }
        catch(e) {
            error(e, widget_row.get('name'), 'Creating post_js function');
        }

        //console.log('my js code', post_js);
        return post_js;

    };



    AQ.Widget.swap = function( $element, id ) {

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



    AQ.Widget.purge_cache = function( widget_name ) {
        return retrieve(widget_name).then(function(resources) {
            delete retrieve_promises[widget_name];
        });
    };



    function error( err, widget_name, step_name ) {
        console.error("widget('" + widget_name + "', ...) " + step_name + " failed!");
        throw err;
    }



    function uuid() {
        var d = new Date().getTime();
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = (d + Math.random()*16)%16 | 0;
            d = Math.floor(d/16);
            return (c=='x' ? r : (r&0x7|0x8)).toString(16);
        });
    }



    /********************************************************************
    COPIED OVER
    ********************************************************************/
    AQ.Widget.load.sync = function(rowlist_promise, container, widget_maker, handlers) {

        console.log('calling widget sync');

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

    window.widget = AQ.Widget.load;
    return AQ.Widget.load;

//}(this, jQuery, doT, AQ || {}, uuid));

});

