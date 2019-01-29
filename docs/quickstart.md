# Aquameta 0.2 - Quick Start

This document guides you through the minimal steps to get started with Aquameta.  It contains the following steps:

- create a new bundle
- create a base HTML resource that imports the bundle and calls a widget
- create a simple widget
- view the resource and widget
- open the on-screen debugger 
- commit the changes to the bundle



## 1. Create a Bundle
From the `/dev` interface, click "new bundle" and give it a name.  Use [Reverse domain name notation](https://en.wikipedia.org/wiki/Reverse_domain_name_notation) to give your bundle a unique name, like `org.flyingmonkeys.myproject`.

## 2. Create a Base Page
Applications have a base HTML page, a static resource that bootstraps the app.  To create the page, click 'new row', then choose 'Resource', and give the resource a path that starts with a /, like `/myproj`.

Here is the minimal base page template:  

```html
<html>
    <head>
        <title>My Cool Project</title>
        <script src='/system.js'></script>
        <script>
            System.import( '/widget.js' ).then( function( widget ) {
                var db = new AQ.Database( '/endpoint/0.1', { evented: 'no' } );
                window.endpoint = db;

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
Paste this into the code section of the resource, customize the variables, and hit save (or CTRL-S).

## 3. Create a Main Widget
In our base HTML page, we added to the page the `'myproj:main'` widget.  We need to make that widget.

Click "New Row" and then "Widget", enter "main" for the name.  This will bring up a widget editor.  Under the HTML tab, set the HTML to:

```html
<div id="{{= id }}" class="{{= name }}">
    <h1>Hello World!</h1>
</div>
```

## 4. View Your App
Browse to the page that you created, whatever path you supplied for the Base Page, and you should see your Hello World widget.

## 5. Open the Debugger
In the bottom right of your app, you should see the debugger.  Check the checkbox, to bring up the list of widgets on the screen.  Click into any widget to edit it.

## 6. Commit Changes
From the `/dev` interface, click the "commit" button, which brings up a list of staged and unstaged changes.  Click "stage" for each row to stage for the next commit.  Click "commit" to commit the changes, and supply a commit summary.

## Conclusion
Congrats!  You've completed the quickstart.  Next, check out the [cheatsheet](cheatsheet.md) for a quick tour of Aquameta features and patterns, or dive into the [API Documentation](api.md).

