aquameta-endpoint
-----------------

`aquameta-endpoint` is a uWSGI service responsible for receiving HTTP requests
and passing them off to the Aquameta Endpoint extension.  It is a thin
middleware layer that handles authentication, and passes REST and resource
requests to the Aquameta `request` procedure in PostgreSQL.

INSTALL
-------
pip install .
