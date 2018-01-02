# Aquameta 0.2 - Cheat Sheet

Quick summary of Aquameta APIs and patterns.

## 1. Bundles
A bundle is a version-controlled collection of rows in the database, similar in function to a [git]() repository.

## 2. Resources

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

## 3. Widgets
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
<p>Hello my name is {{= name }}</p>
```

In the widget's CSS:
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
Typically the fist line of a widget sets up the `w` variable, a jQuery object that references this widget:

```javascript
var w = $("#"+id);

// my widget code here
```

## `widget(name, args)`
Widgets are loaded with a call to the widget() function.  The `name` argument expects a string with syntax `{bundle_alias}:{widget_name}`.  The `args` argument is a Javascript object containing any arguments passed into the widget.

For example, if we have a widget named "colorpicker" in a bundle imported with `AQ.Widget.import( 'org.fancypants.myproject', 'mp', endpoint )`, then the widget is called as follows:

```javascript
w.append(widget('mp:colorpicker', { start_color: '#ff0000' }));
```

## 4. Database API
API for reading and writing data from the database.

### AQ.Database(url)
Every widget has a variable called `endpoint` that references the database it was loaded from, so you usually don't have to call this explicitly.

### AQ.Relation.rows([, modifiers ])
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


## 5. Combining Widgets and Data

### `widget.sync(RowSet, $container, widget_function)`
For each row in RowSet, append the specified widget to the container.

```javascript
var users = endpoint.schema('myproj').table('users').rows();
widget.sync(users, w.find('.user_container'), function(user) {
    return widget('mp:user_list_item', { user: user });
});
```

## 6. Local Event Handling

Handle a button click:

html:

```html
<div id="{{= id }}" class="{{= name }}">
    <button>click me</button>
</div>
```

javascript:

```javascript
w.find('button').click(function() {
    alert ('You clicked the button');
});
```


## 7. Events Between Widgets

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


