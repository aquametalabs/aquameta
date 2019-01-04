# A REST/JSON API for database operations

## Components
* uWSGI
* Database functions

## uWSGI
A simple server that creates a REST-like API for querying and modifying data in
the database. When making a request to the server, it parses the URL to get the
API version and resource path, then makes a query to the endpoint.request
function in the database.

### URLS
* /endpoint/0.2/row
* /endpoint/0.2/relation
* /endpoint/0.2/function
* /endpoint/0.2/field

## Database functions
The entry point is a request function that the uWSGI server uses to pass on th
HTTP verb, API version, and resource path.

### endpoint.request

Arguments
* version
* verb
* path
* query_args
* post_data

Out
* status
* message
* response
* mimetype

## How Aquameta processes a request

1. Every request is first processed by the uWSGI server.  The uWSGI server
   connects to PostgreSQL initially as the `anonymous` user, which has a
   limited set of permissions for authenticating and not much else.  If the user
   has a session cookie set, that cookie is checked to be valid and if it is, they
   can keep being that user.  If not, there is no cookie so they are anonymous.

2. Once authentication is handled, the request is routed to the appropriate
   handler based on the requested path.  If the request begins with the base
   endpoint URL (usually `/endpoint`), it is handled as a REST request.
   Otherwise, it is handled by the uWSGI server.



