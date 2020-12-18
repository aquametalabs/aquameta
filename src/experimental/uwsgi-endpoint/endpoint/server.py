# werkzeug endpoint server
#
# - uses werkzeug's built-in werkzeug.serving run_simple http server
# - it does not support websockets (enabled with uwsgi) so it can't
#   serve the endpoint.events app.
#
# run this with something like:
#
#    ENDPOINT_URL="/endpoint" DB_USER=anonymous DB_NAME=aquameta DB_HOST=/var/run/postgresql python server.py

from endpoint.auth import AuthMiddleware
from endpoint.data import application as data_app
# requires uwsgi
# from endpoint.events import application as events_app
from endpoint.page import application as page_app
from os import environ
from sys import exit
from werkzeug.wsgi import DispatcherMiddleware
from werkzeug.serving import run_simple

import logging

logging.basicConfig(level=logging.INFO)


try:
    endpoint_url = environ['ENDPOINT_URL']

except KeyError as err:
    logging.error("You'll need to specify a %s environment variable." % str(err))
    exit(2)

else:
    application = AuthMiddleware(DispatcherMiddleware(page_app, {
        '%s' % endpoint_url: data_app,
#        '%s/0.2/event' % endpoint_url: events_app
    }))

run_simple('0.0.0.0', 9000, application, use_reloader=True, use_debugger=True)
