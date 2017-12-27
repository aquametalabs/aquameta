# Aquameta 0.1 - Quick Start

This document guides you through the minimal steps to install Aquameta and create a new bundle and application.

## Install
```bash
docker pull aquametalabs/aquameta:0.1.0-rc1

# run on standard ports
docker run -dit -p 80:80 -p 5432:5432 aquametalabs/aquameta:0.1.0-rc1

# run on alternate ports: Webserver on port 8080, PostgreSQL on port 5433
docker run -dit -p 8080:80 -p 5433:5432 aquametalabs/aquameta:0.1.0-rc1
```

Then browse to the developer IDE:

http://my.host.net/dev

## Create a Bundle
From the `/dev` interface, click "new bundle" and give it a name.  Use [Reverse domain name notation](https://en.wikipedia.org/wiki/Reverse_domain_name_notation) to give your bundle a unique name, like `org.flyingmonkeys.myproject`.

## Create a Base Page
Applications have a base HTML page, a static resource that bootstraps the app.  To create the page, click 'new row', then choose 'Resource', and give the resource a path that starts with a /, like `/myproj`.

Here is the minimal base page template:  

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
    
                // import your project bundle's bundle, and specify a namespace alias
                // CUSTOMIZE THIS:
                AQ.Widget.import( 'org.flyingmonkeys.myproject', 'myproj', endpoint );

                // add your project's base widget, usually called "main"
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
Paste this into the code section of the resource, customize the variables, and hit save (or CTRL-S).


## Create a Main Widget

In our base HTML page, we added to the page the `'myproj:main'` widget.  We need to make that widget.

Click "New Row" and then "Widget", enter "main" for the name.  This will bring up a widget editor.  Under the HTML tab, set the HTML to:

```html
<div id="{{= id }}" class="{{= name }}">
    <h1>Hello World!</h1>
</div>
```


## View Your App

Finally, browse to the page that you created, whatever path you supplied for the Base Page, and you should see your Hello World widget.


## Open the Debugger

In the bottom right of your app, you should see the debugger.  Check the checkbox, to bring up the list of widgets on the screen.  Click into any widget to edit it.

## Gotchas

This is a 0.1 release and lots of things don't work well, or at all.  Here are things you should know:

- Bundle row list doesn't refresh
- No edit collision detection between widget edit IDEs.  If you make changes in the debugger, and different changes in the IDE, they'll overwrite each other.
- Events don't work at all


# Cheat Sheet

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


