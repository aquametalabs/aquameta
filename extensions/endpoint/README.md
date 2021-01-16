# endpoint - HTTP Request Handler for PostgreSQL

## Overview

Basic HTTP handling tables and functions:

- REST-like API maps `/endpoint` URLs to SELECTs, INSERTs, UPDATEs, DELETEs and
  PostgreSQL procedure calls  via the `endpoint.request()` method with a
  Javascript client (datum.js)
- Static text resources and their URL path and mimetype are stored in the
  `endpoint.resource` table
- Static binary resources and their URL path and mimetype are stored in the
  `endpoint.resource_binary` table
- PostgreSQL functions can be mapped to a URL pattern in the
  `endpoint.resource_function` table.
- Dynamic text resources (templates) and their URL pattern and mimetype are
  stored in the `endpoint.template` and `endpoint.template_route` tables
- Serves data change events via the [event](../event) extension and HTTP
  WebSocket.

## Security

This extension does not enforce any security constraints on it's own.  Rather,
it exposes the database to HTTP with the same security as the PostgreSQL role
that connects to it.  PostgreSQL has extensive support for
[privileges](https://www.postgresql.org/docs/12/ddl-priv.html) and [row
security policies](https://www.postgresql.org/docs/12/ddl-rowsecurity.html).
To enforce security constraints, use the ones built into PostgreSQL, or limit
network access to the HTTP server.

## HTTP Server

This extension does not itself open any HTTP ports or receive HTTP requests
directly.  Rather, it requires a thin HTTP server front-end that receives and
parses HTTP request, and passes them on to the appropriate handler.  Servers
have been programmed in Python, Node.js, C and Go, but the current reference
implementation is in Go.

## REST API

When an HTTP request matches the REST API's base URL (typically at
`/endpoint/{version}`) the request is passed off to the `endpoint.request()`
PostgreSQL procedure:

```sql
select endpoint.request(
    '0.3',                              -- version
	'GET',                              -- method
	'/endpoint/0.3/row/{meta.row_id}',  -- path
	'{"key": "val"}',                   -- query string as JSON
	'{"key": "val"}'                    -- post args as JSON
);
```

`endpoint.request()` parses the request URL and hands it off to the approriate
handler.  It handles the four basic HTTP methods (GET, PUT, PATCH, DELETE) and
has four basic request handlers:


- `/endpoint/0.3/relation/{meta.relation_id}` returns zero or more rows from a
  single relation as JSON
- `/endpoint/0.3/row/{meta.row_id}` returns zero or one rows from a relation as
  JSON
- `/endpoint/0.3/field/{meta.field_id}` returns a single value in a single row
  as the column's configured mimetype (via `endpoint.column_mimetype`)
- `/endpoint/0.3/function{meta.function_id}` calls a PostgreSQL function and
  returns the results as JSON

The Javascript client API is called `datum.js`, and is stored in the
[org.aquameta.core.endpoint](../../bundles/org.aquameta.core.endpoint) bundle.
It provides a simple, promise-based API to all of the above.

## Static Resources

Static resources (HTML, CSS, Javascript, images, etc.) are stored in the
`endpoint.resource` and `endpoint.resource_binary` tables.  There are two
tables because the `resource.content` is of type `text` and the
`resource_binary.content` field is of type `bytea` (PostgreSQL's binary data
type).  Otherwise, the two tables behave identically; we'll describe just
the `endpoint.resource` table below.

The `resource.path` column contains the URL path that this resource can be
requested at, for example `/favicon.ico`.  Query strings are ignored by the
server.

The `resource.mimetype_id` column is a foreign-key to the `endpoint.mimetype`
table, which contains an extensive list of available mimetypes.  The HTTP
server serves the resource with this mimetype.


## Resource Functions

PostgreSQL stored procedures can mapped to a URL pattern and called via HTTP
request.  If the procedure takes arguments, they can be mapped to a particular URL pattern.  

Work in progress, see
[here](https://github.com/aquametalabs/aquameta/blob/e0b6b40d974e6a1556be1f4d029d65ba9d28b8a0/extensions/endpoint/001-server.sql#L124).


## Templates

Dynamic text resources ("templates") can be served to any request matching a
particular URL pattern.

Work in progress, see [here](https://github.com/aquametalabs/aquameta/issues/236).
