# Aquameta 0.2 - Quick Start

This document guides you through the minimal steps to install Aquameta and create a new bundle and application.

## Install with Docker
```bash
docker pull aquametalabs/aquameta:0.1.0-rc1

# run on standard ports
docker run -dit -p 80:80 -p 5432:5432 aquametalabs/aquameta:0.1.0-rc1

# run on alternate ports: Webserver on port 8080, PostgreSQL on port 5433
docker run -dit -p 8080:80 -p 5433:5432 aquametalabs/aquameta:0.1.0-rc1
```

Your Aquameta instance is now installed.  Access the IDE by browsing to whatever hostname and port you installed it on, at `http://{hostname}:{port}/dev`, for example:

http://localhost:80/dev

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

## Commit Changes
Click the "commit" button, which brings up a list of staged and unstaged changes.  Click "stage" for each row to stage for the next commit.  Click "commit" to commit the changes, and supply a commit summary.

## Conclusion
Congrats!  You've completed the quickstart.  Next, browse over to the [cheatsheet](cheatsheet.md) to see more of what you can do with Aquameta.

