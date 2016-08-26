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
* /endpoint/0.1/row
* /endpoint/0.1/relation
* /endpoint/0.1/function
* /endpoint/0.1/field

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
