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
- return html string
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
