# Aquameta 0.2 - Cheat Sheet

Quick summary of Aquameta APIs and patterns.

## Widgets
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
Widgets can call other widgets, via the `widget()` function.  The `name` argument expects a string containing the bundle alias plus widget name.  For example, if we have a widget named "colorpicker" in a bundle imported with `AQ.Widget.import( 'org.fancypants.myproject', 'mp', endpoint )`, then the widget is called as follows:

```javascript
w.append(widget('mp:colorpicker', { start_color: '#ff0000' }));
```

## `datum.js`
API for reading and writing data from the database.

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
});
```


## `widget.sync(RowSet, $container, widget_function)`
For each row in RowSet, append the specified widget to the container.

```javascript
var users = endpoint.schema('myproj').table('users').rows()
widget.sync(users, w.find('.user_container'), function(user) {
    return widget('mp:user_list_item', { user: user });
});
```


