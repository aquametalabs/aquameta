from endpoint.auth import AuthMiddleware
from endpoint.data import application as old_data_app
from endpoint.new_data import application as new_data_app
from endpoint.events import application as events_app
from endpoint.page import application as page_app
from os import environ
from sys import exit
from werkzeug.wsgi import DispatcherMiddleware

import logging

logging.basicConfig(level=logging.INFO)


try:
    base_url = environ['BASE_URL']

except KeyError as err:
    logging.error("You'll need to specify a %s environment variable." % str(err))
    exit(2)

else:
    application = AuthMiddleware(DispatcherMiddleware(page_app, {
        'new_%s' % base_url: new_data_app,
        '%s' % base_url: old_data_app,
        '%s/event' % base_url: events_app
    }))
