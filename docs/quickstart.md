# Aquameta 0.2 - Quick Start

This document guides you through the minimal steps to get started with Aquameta.  It contains the following steps:

- install Aquameta via Docker
- create a new bundle
- create a base HTML resource that imports the bundle and calls a widget
- create a simple widget
- view the resource and widget
- open the on-screen debugger 
- commit the changes to the bundle


## 1. Install with Docker

If you don't have Docker installed, [install it](https://docs.docker.com/engine/installation/).  Then:

```bash
$ docker pull aquametalabs/aquameta:0.2.0-rc1

# run on standard ports
$ docker run -dit -p 80:80 -p 5432:5432 aquametalabs/aquameta:0.2.0-rc1

# run on alternate ports: Webserver on port 8080, PostgreSQL on port 5433
$ docker run -dit -p 8080:80 -p 5433:5432 aquametalabs/aquameta:0.2.0-rc1
1c59e82ed50ff4463af35d2cc5435c3086f4d67f0046365b4df505dc91e95d19
```

Your Aquameta instance is now installed.  The `docker run` command prints a container-id, which you should take save for running future commands against in the running docker container.  For example, to get a bash shell in the container, run:

```bash
$ docker exec -it 1c59e82ed50ff4463af35d2cc5435c3086f4d67f0046365b4df505dc91e95d19 bash
root@0f84133a577e:/s/aquameta#
```

Now that you have a running container, you can access the IDE by browsing to whatever hostname and port you installed it on, at `http://{hostname}:{port}/dev`, for example:

http://localhost:80/dev

## 2. Create a Bundle
From the `/dev` interface, click "new bundle" and give it a name.  Use [Reverse domain name notation](https://en.wikipedia.org/wiki/Reverse_domain_name_notation) to give your bundle a unique name, like `org.flyingmonkeys.myproject`.

## 3. Create a Base Page
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

## 4. Create a Main Widget
In our base HTML page, we added to the page the `'myproj:main'` widget.  We need to make that widget.

Click "New Row" and then "Widget", enter "main" for the name.  This will bring up a widget editor.  Under the HTML tab, set the HTML to:

```html
<div id="{{= id }}" class="{{= name }}">
    <h1>Hello World!</h1>
</div>
```

## 5. View Your App
Browse to the page that you created, whatever path you supplied for the Base Page, and you should see your Hello World widget.

## 6. Open the Debugger
In the bottom right of your app, you should see the debugger.  Check the checkbox, to bring up the list of widgets on the screen.  Click into any widget to edit it.

## 7. Commit Changes
From the `/dev` interface, click the "commit" button, which brings up a list of staged and unstaged changes.  Click "stage" for each row to stage for the next commit.  Click "commit" to commit the changes, and supply a commit summary.

## Conclusion
Congrats!  You've completed the quickstart.  Next, check out the [cheatsheet](cheatsheet.md) for a quick tour of Aquameta features and patterns, or dive into the [API Documentation](api.md).

