/*******************************************************************************
 * Widget.js
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/
define(['/doT.min.js', '/jQuery.min.js', '/datum.js'], function(doT, $, AQ, undefined) {

    'use strict';

    doT.templateSettings.strip = false;

    var widget_promises = {};
    var containers = {};
    var namespaces = {};


    AQ.Widget = {};


    AQ.Widget.widget = function ( selector, input, extra ) {

        if (!selector || typeof selector != 'string') {
            throw "Widget - Selector argument is invalid or missing";
        }

        // Same namespace as calling widget, instead of global '' namespace
        var default_namespace = (typeof this != 'undefined' && typeof this.namespace != 'undefined') ? this.namespace : '';

        var is_semantic_dsl_lookup = selector.indexOf('/') != -1;

        // For semantic lookup
        // * selector is 'semantics/purpose/default_bundle'
        // * input is AQ.* object
        // * extra is {} to send to widget
        if (is_semantic_dsl_lookup) {

            if (!input) {
                throw "Semantics requires an AQ.* to be passed in";
            }

            var context = extra || {};
            var semantics = selector.split('/');
            var args_object = {};

            // If input is a promise (that will resolve as a Rowset or a Row), resolve it first
            if (input instanceof Promise) {

                var url_id;
                var widget_getter = input.then(function(input) {

                    context.datum = input;

                    // These are the same for both Rowset and Row
                    var endpoint = input.relation.schema.database;
                    var fn = 'relation_widget';
                    var type = 'meta.relation_id';
                    args_object.relation_id = input.relation.id;

                    if (input instanceof AQ.Rowset) {
                        context.rows = input;
                        url_id = input.relation.to_url(true);
                    }
                    else if (input instanceof AQ.Row) {
                        context.row = input;
                        url_id = input.to_url(true);
                    }
                    args_object.widget_purpose = semantics[1];
                    args_object.default_bundle = semantics.length >= 3 ? semantics[2] : 'org.aquameta.core.semantics';
                    
                    return endpoint.schema('semantics').function({
                        name: fn,
                        parameters: [type,'text','text']
                    }, args_object, { use_cache: true, meta_data: false });

                });

            }
            // Else, check which type it is
            else {

                context.datum = input;

                if (input instanceof AQ.Relation || input instanceof AQ.Table || input instanceof AQ.View) {
                    var endpoint = input.schema.database;
                    var fn = 'relation_widget';
                    var type = 'meta.relation_id';
                    args_object.relation_id = input.id;
                    var url_id = input.to_url(true);
                    context.relation = input;
                }
                else if (input instanceof AQ.Row) {
                    var endpoint = input.relation.schema.database;
                    var fn = 'relation_widget';
                    var type = 'meta.relation_id';
                    args_object.relation_id = input.relation.id;
                    var url_id = input.to_url(true);
                    context.row = input;
                }
                else if (input instanceof AQ.Rowset) {
                    var endpoint = input.relation.schema.database;
                    var fn = 'relation_widget';
                    var type = 'meta.relation_id';
                    args_object.relation_id = input.relation.id;
                    var url_id = input.relation.to_url(true);
                    context.rows = input;
                }
                else if (input instanceof AQ.Column) {
                    var endpoint = input.relation.schema.database;
                    var fn = 'column_widget';
                    var type = 'meta.column_id';
                    args_object.column_id = input.id;
                    var url_id = input.relation.to_url(true);
                    context.column = input;
                }
                else if (input instanceof AQ.Field) {
                    var endpoint = input.row.relation.schema.database;
                    var fn = 'column_widget';
                    var type = 'meta.column_id';
                    args_object.column_id = input.column.id;
                    var url_id = input.to_url(true);
                    context.field = input;
                }
                
                args_object.widget_purpose = semantics[1];
                args_object.default_bundle = semantics.length >= 3 ? semantics[2] : 'org.aquameta.core.semantics';
                
                var widget_getter = endpoint.schema('semantics').function({
                    name: fn,
                    parameters: [type,'text','text']
                }, args_object, { use_cache: true, meta_data: false });
            }

            // Go get this widget - retrieve_promises don't change for calls to the same widget - they are cached by the widget name
            var widget_retrieve_promise = retrieve(widget_getter, {
                semantic_selector: selector,
                url_id: url_id
            });

        }

        // For regular widget lookup
        // * selector is '[namespace:]widget_name'
        // * input is {} to send to widget
        // * extra is ignored
        else {

            //var context = typeof input != 'undefined' ? Object.assign({}, input) : {};
            var context = input || {};

            var name_parts = selector.split(':');

            if (name_parts.length == 1) {
                // Default namespace lookup
                context.namespace = default_namespace;
                context.name = name_parts[0];
            }
            else {
                // Namespaced lookup
                context.namespace = name_parts[0];
                context.name = name_parts[1];
                context.bundle_name = namespaces[context.namespace].bundle_name;
            }

            // Namespace not found
            if (!(context.namespace in namespaces)) {
                throw 'Widget namespace "'+context.namespace+'" has not been imported - Call AQ.Widget.import( bundle_name, namespace, endpoint ) to import bundled widgets to a namespace';
            }
    
            var widget_getter = namespaces[context.namespace].endpoint.schema('widget').function('bundled_widget',
                [ namespaces[context.namespace].bundle_name, context.name ], {
                    use_cache: true,
                    meta_data: false
                });

            // Go get this widget - retrieve_promises don't change for calls to the same widget - they are cached by the widget name
            var widget_retrieve_promise = retrieve(widget_getter, {
                namespace: context.namespace,
                name: context.name
            });

        }

        context.id = AQ.uuid();

        // Setup default namespace for child widget
        context.widget = AQ.Widget.widget.bind({ namespace: context.namespace });
        context.widget.sync = AQ.Widget.widget.sync;

        // Prepare and render the widget - each prepare_promise is unique because inputs are different - they are cached by the unique uuid created for the context
        widget_promises[context.id] = prepare(widget_retrieve_promise, context);

        // Return script that calls swap
        return '<script id="widget-stub_' + context.id  + '" data-widget_id="' + context.id + '">' +
                  'AQ.Widget.swap($("#widget-stub_' +  context.id  + '"), "' + context.id + '");'  + 
               '</script>';

    }



    /* Import a bundle name to a local namespace */
    AQ.Widget.import = function( bundle_name, namespace, endpoint ) {

        namespaces[namespace] = {
            endpoint: endpoint,
            bundle_name: bundle_name
        };

    };


    /* Return an array bundle of imported bundle names */
    AQ.Widget.bundles = function() {
        return Object.keys(namespaces).map(function(key) {
            return namespaces[key].bundle_name;
        });
    };



    /* Find the bundle that was imported to this namespace */
    AQ.Widget.bundle = function( namespace ) {
        return namespaces[namespace].bundle_name;
    };



    /* Find the namespace that uses this bundle */
    AQ.Widget.namespace = function( bundle_name ) {
        return Object.keys(namespaces).find(function(namespace) {
            return namespaces[namespace].bundle_name == bundle_name;
        });
    };



    function retrieve( widget_getter, selector ) {

        if ('semantic_selector' in selector) {
            var semantic_lookup = true;
        }

        return widget_getter.then(function(row) {

            // Get all related widget data
            return Promise.all([
                row,
                row.related_rows('id', 'widget.input', 'widget_id', { use_cache: true, meta_data: true }).catch(function(){ return; }),
                row.related_rows('id', 'widget.widget_view', 'widget_id', { use_cache: true, meta_data: true })
                    .then(function(widget_views) {

                        var db = row.schema.database;
                        return widget_views.map(function(widget_view) {
                            var view_id = widget_view.get('view_id');
                            return db.schema(view_id.schema_id.name).view(view_id.name);
                        });

                    }).catch(function(err) { return; }),
                row.related_rows('id', 'widget.widget_dependency_js', 'widget_id', { use_cache: true, meta_data: true })
                    .then(function(deps_js) {

                        if (!deps_js.length) { return; }
                        return deps_js.related_rows('dependency_js_id', 'widget.dependency_js', 'id', { use_cache: true, meta_data: true });

                    }).then(function(deps) {

                        return Promise.all(

                            deps.map(function(dep) {
                                return System.import(dep.field('content').to_url()).then(function(dep_module) {
                                    //console.log('my module', dep_module);
                                    
                                    return {
                                        url: dep.field('content').to_url(),
                                        name: dep.get('variable') || 'non_amd_module',
                                        /* TODO: This value thing is a hack. For some reason, jwerty doesn't load properly here */
                                        value: typeof dep_module == 'object' ? dep_module[Object.keys(dep_module)[0]] : dep_module
                                        //value: dep_module
                                    };
                                });
                            })
                        );

                    }).catch(function() { return; })
            ]);
        }).catch(function(err) {
            if (semantic_lookup) {
                throw 'Widget not found from semantic lookup with ' + selector.semantic_selector + ' on ' + selector.url_id;
            }
            else {
                throw 'Widget does not exist, ' + selector.namespace + ':' + selector.name;
            }
        });
    };



    function prepare( retrieve_promise, context ) {

        return retrieve_promise.then(function( widget_data ) {

            //console.log('retrieve_promise resolved', widget_data);
            var [ widget_row, inputs, views, deps_js ] = widget_data;

            context.name = widget_row.get('name');

            var xinput = context;
            context = Object.assign({
                    db: widget_row.schema.database,
                    endpoint: widget_row.schema.database,
                    input: {},
                    xinput: xinput
                }, context);

            delete context.xinput.id;
            delete context.xinput.name;
            delete context.xinput.namespace;
            delete context.xinput.widget;

            // Process inputs
            if (typeof inputs != 'undefined') {

                inputs.forEach(function(input) {
                    var input_name = input.get('name');

                    if (typeof context[input_name] == 'undefined') {
                        if (input.get('optional')) {
                            var default_code = input.get('default_value');
                            try {

                                if (default_code) {
                                    context[input_name] = eval('(' + default_code + ')');
                                }
                                else {
                                    context[input_name] =  undefined;
                                }

                            }
                            catch (e) {
                                error(e, context.name, "Widget default eval failure: " + default_code);
                                /*
                                console.error("Widget default eval failure", default_code);
                                throw e;
                                */
                            }

                        }
                        else {
                            error('Missing required input ' + input_name, context.name, 'Inputs');
                        }
                    }
                    context.input[input_name] = context[input_name];
                    delete context.xinput[input_name];
                });
            }

            // Load views into context
            if (typeof views != 'undefined') {
                views.forEach(function(view) {
                    context[view.schema.name + '_' + view.name] = view;
                });
            }

            var rendered_widget = render(widget_row, context);
            var post_js_function = create_post_js_function(widget_row, context, deps_js);

            // Return rendered widget and post_js function
            return {
                html: rendered_widget,
                widget_id: context.id,
                widget_name: context.name,
                post_js: post_js_function
            };

        });
    };



    function render( widget_row, context ) {

        // Create html template
        var html_template = doT.template(widget_row.get('html') || '');

        // Compile html template
        try {
            var html = html_template(context);
        } catch(e) {
            error(e, context.name, 'HTML');
        }

        // Render html
        try {
            var rendered = $(html).attr('data-widget', context.name)
                .attr('data-widget_id', context.id)
                .attr('data-bundle_alias', context.namespace)
                .attr('data-bundle_name', context.bundle_name)
                .attr('data-widget_row_id', widget_row.get('id'))
                .data('help', widget_row.get('help'));
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
        var context_vals = context_keys.map(function(key) {
            return context[key];
        });

        // Dependency names and values
        var dep_names = [],
            dep_values = [];
        if (deps_js != null) {
            deps_js.forEach(function(dep_js) {
                dep_names.push(dep_js.name);
                dep_values.push(dep_js.value);
            });
        }

        try {
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

        return post_js;

    };


    // detect svg widgets by tag name.  might be better to check the dom to see if we're inside an svg tag?
    AQ.Widget.is_svg = function( e ) {
        var svg_tags = ['circle','rect','polygon','g']; // TODO: add more, or change approach?
        for (var i=0;i<svg_tags.length;i++) {
            if (e.tagName.toUpperCase() == svg_tags[i].toUpperCase()) {
                // console.log('svg  widget: ' + svg_tags[i]);
                return true;
            }
        }
        return false;
    }



    AQ.Widget.swap = function( $element, id ) {
        widget_promises[id].then(function(rendered_widget) {

            // Replace stub
            // special case for svg elements - http://stackoverflow.com/questions/3642035/jquerys-append-not-working-with-svg-element
            if (AQ.Widget.is_svg(rendered_widget.html[0])) { // TODO: is there ever a case where there is more than one element in this array?
                var div = document.createElementNS('http://www.w3.org/1999/xhtml', 'div');
                div.innerHTML= '<svg xmlns="http://www.w3.org/2000/svg">'+rendered_widget.html[0].outerHTML+'</svg>';

                var frag= document.createDocumentFragment();
                while (div.firstChild.firstChild)
                    frag.appendChild(div.firstChild.firstChild);

                $element.replaceWith(frag);
            }
            else $element.replaceWith(rendered_widget.html);

            // Run post_js - or this may have to be done with a script tag appended to the widget
            try {
                rendered_widget.post_js();
            }
            catch(e) {
                error(e, rendered_widget.widget_name, 'Running post_js function');
            }

            var w = $('#' + rendered_widget.widget_id);

            // notify the world that a widget has loaded.  debugger uses this to detect widget tree changes
            w.trigger('widget_loaded', { widget: w });

            // Delete prepeared_promise
            delete widget_promises[id];

        }).catch(function(error) {
            //console.error('Widget swap failed - ', error);
            console.error(error);
            // Remove stub
            $element.remove();
            // Delete promise
            delete widget_promises[id];
        });
    };



    function error( err, widget_name, step_name ) {
        console.error("widget('" + widget_name + "', ...) " + step_name + " failed!");
        //window.setTimeout(function() { throw err; }, 100);
        throw err;
    }



    AQ.Widget.sync = function(rowset_promise, container, widget_maker, handlers) {

        if(handlers === undefined) {
            handlers = {};
        }

        if (widget_maker === undefined) {
            throw 'widget.sync missing widget_maker argument';
        }

        if (container.length < 1) {
            throw 'widget.sync failed: The specified container is empty or not found';
            return;
        }

        if (container.length > 1) {
            throw 'widget.sync failed: The specified container contains multiple elements';
            return;
        }

        if (!container instanceof jQuery) {
            throw 'widget.sync failed: The specified container is not a jQuery object';
            return;
        }

        if (typeof rowset_promise == 'undefined' ||
            (!(rowset_promise instanceof Promise) && !(rowset_promise instanceof AQ.Rowset) && !(rowset_promise instanceof AQ.FunctionResultSet))) {
            throw 'widget.sync failed: rowset_promise must be a "thenable" promise or a resolved AQ.Rowset or a resolved AQ.FunctionResultSet';
        }

        if (!(rowset_promise instanceof Promise)) {
            rowset_promise = Promise.resolve(rowset_promise);
        }

        rowset_promise.then(function(rowset) {

            if (typeof rowset == 'undefined' || typeof rowset.forEach == 'undefined') {
                throw 'Rowset is not defined. First argument to widget.sync must return a Rowset';
            }

            var container_id = AQ.uuid();

            container.attr('data-container_id', container_id)
            containers[container_id] = {
                container: container,
                widget_maker: widget_maker,
                handlers: handlers
            };

            rowset.forEach(function(row) {
                container.append(widget_maker(row));
            });

        }).catch(function(error) {
            console.error('widget.sync failed: ', error);
        });

    }

    // duplicate name for backwards compatibility
    AQ.Widget.widget.sync = AQ.Widget.sync;

    return AQ.Widget.widget;

});

