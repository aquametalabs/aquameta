# Aquameta 0.2 - Cheat Sheet

Summary of Aquameta APIs and patterns.

- command-line access to the database
- bundles
- resources
- widgets
- database API
- combining widgets and data
- local event handling
- communicating between widgets 

This document assumes you know basic HTML, CSS, Javascript, jQuery.  Some familiarity with PostgreSQL and Docker will be helpful as well.



## 1. Accessing the Database
Underneath the hood is a stock [PostgreSQL](http://postgresql.org/) database, which you can access via the command line (and someday a fancy user interface) to create schemas, tables, etc. for use in your application.

### open database shell
```sh
$ psql aquameta -U yourusername
psql (9.6.0)
Type "help" for help.

aquameta=# 
```

### show schemas
```sql
aquameta=# \dn
    List of schemas
    Name     |  Owner   
-------------+----------
 bundle      | root
 endpoint    | root
 event       | root
 filesystem  | root
 http_client | root
 ide         | root
 meta        | root
 public      | postgres
 semantics   | root
 widget      | root
(10 rows)
```

### `create schema`
```sql
aquameta=# create schema 'beehive';
CREATE SCHEMA
aquameta=#
```

### `set search_path`
```sql
aquameta=# set search_path=beehive;
SET
aquameta=#
```

### `create table`
```sql
aquameta=# create table some_table (
aquameta(# id serial primary key,
aquameta(# message text,
aquameta(# color text,
aquameta(# number integer);
CREATE TABLE
aquameta=#
```

You can do a lot with PostgreSQL.  Consult the [documentation](https://www.postgresql.org/docs/current/static/index.html) for more information.



## 2. Bundles
A bundle is a version-controlled collection of rows in the database, similar in function to a [git]() repository.  The bundle management interface can be accessed via the browser at `/dev`, to manage bundles and create new ones, as well as stage and commit changes, and checkout previous versions of a repository.



## 3. Resources

A resource is a static base page that is served up at the specified `path`.  You can put any HTML you want in a resource, but typically they look like this:

```html
<html>
    <head>
        <title>My Cool Project</title>
        <script src='/system.js'></script>
        <script>
            System.import( '/widget.js' ).then( function( widget ) {
                window.endpoint = new AQ.Database( '/endpoint/0.1', { evented: 'no' } );

                // some commonly used bundles
                AQ.Widget.import( 'org.aquameta.core.ide', 'ide', endpoint );
    
                // import your project's bundle, and specify a namespace alias
                // CUSTOMIZE THIS:
                AQ.Widget.import( 'org.flyingmonkeys.myproject', 'myproj', endpoint );

                // append a base widget to the page, usually called "main".
                // syntax is {bundle_alias}:{widget_name}.
                // CUSTOMIZE THIS:
                $('body').append( widget( 'myproj:main' ) );

                // add the on-screen debugger
                $('body').append( widget( 'ide:debugger3_manager' ) );

            }).catch( function( e ) {
                console.log( 'System.js error:', e );
            });
         </script>
    </head>
    <body></body>
</html>
```



## 4. Widgets
Aquameta user interfaces are made up of widgets.  A widget is a row in the database which contains fields of HTML, CSS and Javascript.

### Available Variables
The following variables are available by default, in a widget's HTML, CSS and Javascript:

- `$`, the [jQuery](http://jquery.com/) library
- `name`, the name of the widget
- `id`, the DOM id of the widget
- `endpoint`, the AQ.Database object that can be used to access the REST interface
- Any arguments passed into the widget

### HTML and CSS
Aquameta uses the [doT.js](http://olado.github.io/doT/index.html) template language.  You can do a lot with doT.js, but mostly we just use it to print variables:

In the widget's HTML:
```html
<div id="{{= id }}" class="{{= name }}">
    <p>Hello, I am a widget who was passed a variable called "color" whose value is  {{= color }}</p>
</div>
```

In the widget's CSS, we use `{{= name }}` to reference the name of the widget and apply CSS rules to it:
```css
/* apply css to the base element of the widget */
.{{= name }} {
    background-color: white;
    color: black;
}

/* apply css to all p children under this widget */
.{{= name }} p {
    text-decoration: underline;
}
```

### Javascript

A widget's Javascript is executed after the widget's HTML and CSS are inserted into the page.  From the Javascript, you can insert data into the widget's HTML, bind DOM events to handler functions, access the database, and more.

Typically the fist line of a widget sets up the `w` variable, a jQuery object that references this widget:

```javascript
var w = $("#"+id);

// my widget code here
```

#### Simple button click handler

html:
```html
<div id="{{= id }}" class="{{= name }}">
    <button>click me</button>
</div>
```

javascript:
```javascript
var w = $("#"+id);

w.find('button').click(function() {
    alert ('You clicked the button');
});
```

#### Set contents of an element

html:
```html
<div id="{{= id }}" class="{{= name }}">
    <h3 class='person_name'></h3>
</div>
```

javascript:
```javascript
var w = $("#"+id);

w.find('div.person_name').html("John Smith");
```

### Calling other widgets via `widget(name, args)`
Widgets are loaded with a call to the widget() function, which returns an HTML fragment suitable for inserting into the page.  In the call to widget, the `name` argument expects a string with syntax `{bundle_alias}:{widget_name}`; the `args` argument is a Javascript object containing any arguments passed into the widget.

For example, if we have a widget named "colorpicker" in a bundle imported with `AQ.Widget.import( 'org.fancypants.myproject', 'mp', endpoint )`, which expects an argument called `start_color`, the widget would be put on the screen as follows:

```javascript
w.append(widget('mp:colorpicker', { start_color: '#ff0000' }));
```




## 5. Database API

### `AQ.Database(url)`
Every widget has a variable called `endpoint` that can be used to access the database.  The database object is instantiated in the [Base HTML](#4-Resources) page, via the call to:

```javascript
window.endpoint = new AQ.Database( '/endpoint/0.1', { evented: 'no' } );
```

### Requesting a `AQ.Rowset` via `.rows()`

Here's a simple call to request all rows in the table `beehive.customers`.  It returns a Promise for a `AQ.Rowset` as described in the [`fetch`](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/) API.

```javascript
// get a promise for all rows in the beehive.customer table
var customers = endpoint.schema('beehive').table('customer').rows();
```

This code immediately assigns `customers` to a Rowset Promise, and then asynchronously fires a request to the server to retrieve the actual customers data.

### Requesting a Single `AQ.Row` via `AQ.Relation.row(pk_name, pk_value)`

```javascript
var customers = endpoint.schema('beehive').table('customer').row('id', 12345);
```

### Requesting Related Rows via `AQ.Row.related_rows()`

Often times we have a row, and need to jump across a foreign-key to get related rows that foreign-key to or from the first row.  The `Row.related_rows()` method makes this possible:

```
AQ.Row.related_rows(local_key_column, related_table, related_key_column [, modifiers ])
```

For example, let's say we have two tables, `beehive.customer` and `beehive.order`.  Every `beehive.order` row foreign-keys to the the customer table's `id` field via the `order.customer_id` field.

Once we have a customer object, we can retrieve all orders that foreign-key to it via:

```javascript
var orders = customer.related_rows('id','beehive.order','customer_id');
```

Now, `orders` is assigned a Promise to an `AQ.Rowset` containing all orders that foreign-key to this customer.


### Filtering Results Using `.rows(Modifiers)`

Modifiers provide a simple mechanisms for filtering result data via `where`, `order`, `limit`, and `offset`.

Modifiers never change the *structure* of results, they just sort and filter the results.  For more advanced server-side data manipulation, create a [view](https://www.postgresql.org/docs/current/static/sql-createview.html).

```javascript
var customers = endpoint.schema('beehive').table('customer').rows({
    // filter out results that do not match the supplied where-clause(s)
    where: [{
        // the name of the column to filter on
        name: 'name',
        // the operation to use
        op: 'like'
        // the value to check against
        value: '%john%'
        // this results in a SQL statement "WHERE name like '%john%'"
    }],
    // sort the results
    order_by: {
        // column to sort on
        column: 'name',
        // direction to sort, either 'asc' or 'desc'
        direction: 'desc'
        // result: ORDER BY name desc
    },
    // only return a max of 20 results
    limit: 20,
    // skip the first 10 results
    offset: 10
});
```

### Handling Promise Resolution via `.then()`

When the server returns the customer rows, we can attach an event handler via `Promise.then()`:

```javascript
customers.then(function( customers ){
    console.log('We got customers: ', customer);
}).catch(function( e ){
    console.error("Error loading customers: ", e);
});
```


### Iterating Through an `AQ.Rowset` via `.forEach()`

We can iterate through a customers Rowset, and call a function on each row in the Rowset.  The function will be passed an `AQ.Row` object:

```javascript
// iterate through customers
customers.forEach(function( customer ) {
    // customer is a AQ.Row object
    console.log(customer);
})
```

### Accessing Row data via `AQ.Row.get()`, `AQ.Row.set()` and `AQ.Row.update()`

Each `AQ.Row` object has functions for getting, setting and saving data:

```javascript
customers.forEach(function( customer ) {
    // get the customer address
    var address = customer.get('address');

    // set the customer name
    customer.set('name', 'Sally Smith');

    // save the customer to the database
    customer.update().then(function(customer) {
        console.log('Customer saved');
    }).catch(function(e) {
        console.log('Customer update failed: ', e);
    });
})
```



## 6. Combining Widgets and Data via `widget.sync()`

Often times when we have a `AQ.Rowset`, we want to put a widget on the screen for each row in the rowset.  We can of course iterate through the rowset with a `.forEach()` call, but `widget.sync` is a lot cooler.

`widget.sync` takes a Rowset, iterates through each row, calls the specified widget_function, passing it the row, and appends what the function returns to the supplied container.  

Syntax: `widget.sync(Rowset, $container, widget_function)`


html:
```html
<div id="{{= id }}" class="{{= name }}">

    <h3>All Customers</h3>

    <div class='customers_container'>
         <!-- customer widgets will go here -->
    </div>
</div>
```

javascript:
```javascript
var customers = endpoint.schema('beehive').table('customer').rows();

widget.sync(customers, w.find('.customers_container'), function(customer) {
    return widget('bh:customer_summary', { customer: customer });
});
```



## 7. Communication Between Widgets

Widgets communicate with each other using DOM events via jQuery's [trigger()](http://api.jquery.com/trigger/) and [bind()](http://api.jquery.com/bind/).  Trigger fires a named event that bubbles up the DOM tree, just like typical DOM events.  Bind listens on a particular DOM element for events matching a particular name.  When it receives one, it fires the specified function, passing it any arguments that the trigger was called with.

For example, let's say we want to create a app-wide general-purpose widget that flashes a message on the screen to the user.  With it, any other widget can trigger an event to alert the user of whatever message.

### Define the Event Name and Args 
First let's give the event a name and expected arguments.  We will name the event `alert_message`, and say that it expects an argument object like `{ message: "Hi Mom!" }`.

### Event Listener Widget
Let's first create the widget that listens for `alert_message` events and shows them to the user.

Bind only receives events that are fired on its descendent elements.  As such, we typically want to bind to some parent widget, a widget that is a parent to all widgets that will be calling this listener.  Often times the root widget of the app works great, since all widgets in the app are its descendents.

```javascript
var w = $('#'+id);

// find the ancestor widget .main, and bind the alert_handler to it
w.closest('.main').bind('alert_message', function(e,o) {
    // o is whatever is passed into the second argument of .trigger()
    var message = o.message;

    // do the alert
    alert(message);
});
```

Now, anywhere in our app, we can trigger an event with this name and arguments, and the listener will receive and handle it.  Whenever .main receives a `alert_message` event, the handler will fire and show the message passed in.  

### Widget that Triggers an Event for the Listener

Let's give it a spin:

html:
```html
<div id="{{= id }}" class="{{= name }}">
    <button class='compliment'>Compliment user</button>
</div>
```

javascript:
```javascript
var w = $("#"+id);

w.find('button.compliment').click(function() {
    w.trigger('alert_message', {
        message: 'My, you look very lovely today!'
    });
});
```

Clicking the "Compliment user" button calls the click handler function, which triggers the event, and presto.


## Conclusion

These are the basics of how to build apps with Aquameta.  Thank you.  The end.
