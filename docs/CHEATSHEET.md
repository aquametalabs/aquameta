# Aquameta 0.1 - Cheat Sheet

## Widgets
A widget is a DOM element made up of HTML, CSS and Javascript.  They are rendered on the screen as follow:
1. Render HTML and CSS
2. Put HTML and CSS on the page
3. Run the Javascript

### Available Variables
The following variables are available by default in every widget's HTML, CSS and Javascript:

- `$`, [jQuery](http://jquery.com/)
- `name`, the name of the widget
- `id`, the DOM id of the widget
- `endpoint`, the AQ.Database object that can be used to access the REST interface
- Any arguments passed into the widget

### HTML and CSS
Aquameta uses the [doT.js](http://olado.github.io/doT/index.html) template language.  You can do a lot with doT.js, but mostly we just use it to print variables:
```html
<p>Hello my name is {{= name }}
```

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

## `datum.js`
API for reading and writing data from the database.
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
