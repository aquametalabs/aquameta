# Aquameta 0.2 - Cheat Sheet

Summary of Aquameta APIs and patterns.

- shell access via docker
- command-line access to the database
- bundles
- resources
- widgets
- database API
- combining widgets and data
- local event handling
- communicating between widgets 

## 1. Shell Access via Docker

Aquameta is installed via Docker.  See the [quickstart](quickstart.md) for info on how to install Aquameta.

Once installed, note the Docker container id for use in all command-line arguments.  Replace the `0f84133a577e` below with your docker container id:

### bash shell
```sh
$ docker exec -it 0f84133a577e bash
root@0f84133a577e:/s/aquameta#
```

## 2. Database
Underneath the hood is a full-blown [PostgreSQL]() database, which you can access via the command line (and someday a fancy user interface) to create schemas, tables, etc. for use in your application.

### open database shell
```sh
$ docker exec -it 0f84133a577e psql aquameta
psql (9.6.0)
Type "help" for help.

aquameta=# 
```

### show schemas
```sh
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
```sh
aquameta=# create schema 'my_project';
CREATE SCHEMA
```

### `set search_path`
```sh
aquameta=# set search_path=my_project;
```

### `create table`
```sh
aquameta=# create table some_table (
id serial primary key,
message text,
color text,
number integer);
CREATE TABLE
```

You can do a lot with PostgreSQL.  Consult the [documentation](https://www.postgresql.org/docs/current/static/index.html) for more information.


## 3. Bundles
A bundle is a version-controlled collection of rows in the database, similar in function to a [git]() repository.  The bundle management interface can be accessed via the browser at `/dev`, to manage bundles and create new ones, as well as stage and commit changes, and checkout previous versions of a repository.

## 4. Resources

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

## 5. Widgets
Aquameta applications are made up of widgets.  A widget is a row in the database which contains fields of html, css and javascript.

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
});
```


## Calling other widgets via `widget(name, args)`
Widgets are loaded with a call to the widget() function, which returns an HTML fragment suitable for inserting into the page.  In the call to widget, the `name` argument expects a string with syntax `{bundle_alias}:{widget_name}`; the `args` argument is a Javascript object containing any arguments passed into the widget.

For example, if we have a widget named "colorpicker" in a bundle imported with `AQ.Widget.import( 'org.fancypants.myproject', 'mp', endpoint )`, which expects an argument called `start_color`, the widget would be put on the screen as follows:

```javascript
w.append(widget('mp:colorpicker', { start_color: '#ff0000' }));
```

## 6. Database API
### `AQ.Database(url)`
Every widget has a variable called `endpoint` that can be used to access the database.  The database object is instantiated in the [Base HTML](#4-Resources) page, via the call to:

```javascript
window.endpoint = new AQ.Database( '/endpoint/0.1', { evented: 'no' } );
```

### Requesting Rows

Here's a simple call to request all rows in the table `my_project.customers`:

Simple example:
```javascript
// get a promise for some rows
var customers = endpoint.schema('beehive').table('customer').rows();

// when the promise is resolved, iterate through the results
customers.then(function( customer ){
}).catch(function( e ){
    console.error("Error loading customers: ", e);
});

// iterate through customers
customers.each(function( customer ) {
    console.log(customer.get('name'));
})
```

### `RowSet.related_rows(local_key_column, related_table, related_key_column [, modifiers ])`
```javascript
customers.related_rows('id','beehive.order','customer_id').then(function(orders) {
    // now ya have a orders RowSet, but only orders that reference the customers
    orders.forEach(function(order) {
        // now we have a Row object 'order' 

        // get fields
        var customer_name = order.get( 'name' );
        var customer_id = order.get( 'id' );

        // set a field
        order.set( 'name', 'Some New Name' );

        // save the change
        order.update().then(function() {
            alert("We updated a customer");
        };
    }
});
```


### Using `.rows(Modifiers)`

Modifiers provide a simple mechanisms for filtering result data via `where`, `order`, `limit`, and `offset`.

Modifiers do not change the *structure* of data.  For more advanced server-side manipulation, create a [view](https://www.postgresql.org/docs/current/static/sql-createview.html).

```javascript
var customers = endpoint.schema('beehive').table('customer').rows({
    where: [{
        // the name of the column to filter on
        name: 'name',
        // the operation to use
        op: 'like'
        // the value to check against
        value: '%john%'
        // this results in a SQL statement "WHERE name like '%john%'"
    }],
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


## 7. Combining Widgets and Data

### `widget.sync(RowSet, $container, widget_function)`
For each row in RowSet, append the specified widget to the container.

```javascript
var users = endpoint.schema('myproj').table('users').rows();
widget.sync(users, w.find('.user_container'), function(user) {
    return widget('mp:user_list_item', { user: user });
});
```


## 8. Communication Between Widgets

Widgets communicate with each other using DOM events via jQuery's [trigger()]() and [bind()]().  Trigger fires events that bubble up the DOM tree.  Bind listens for events with the same name, and fires the specified function, passing in any arguments from the trigger call.

For example, let's say we want to create a widget that flashes a message on the screen to the user, and then any other widget can trigger an event to show send that wiget a message.  We will name the event `alert_message`.

First, let's make a widget that triggers the `alert_message` event when a button is clicked.

html:
```html
<div id="{{= id }}" class="{{= name }}">
    <button class='message_sender'>Click me to alert a message!</button>
</div>
```

javascript:
```javascript
var w = $("#"+id);

w.find('button.message_sender').click(function() {
    w.trigger('alert_message', {
        message: 'Hey you clicked a button!'
    });
});
```

Next lets setup the message reciever.

The message reciever should bind to some parent widget, often times the root widget of the app, so it recieves events from any child widget of .main, which should be all the widgets in the app.

```javascript
w.closest('.main').bind('alert_message', function(e,o) {
    // o is whatever is passed into the second argument of .trigger()
    var message = o.message;

    // do the alert
    alert(message);
});
```

Now, whenever .main recieves a `alert_message` event, this handler will fire and show the message passed in.


## Conclusion

The end.
