import json
import logging
import os
import pathlib
from urllib.parse import urlparse

import boto3

logging.basicConfig()

HEADER_CHANNEL_TOKEN = 'x-goog-channel-token'    # custom token, must match expected token
HEADER_RESOURCE_STATE = 'x-goog-resource-state'  # "sync", "download", etc
HEADER_RESOURCE_URI = 'x-goog-resource-uri'      # path of resource (eg: applicationName)
HEADER_CONTENT_LENGTH = 'content-length'         # integer for body size

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

EXPECTED_CHANNEL_TOKEN = os.environ['CHANNEL_TOKEN']
SNS_TOPIC = boto3.resource('sns').Topic(os.environ['SNS_TOPIC_ARN'])


def extract_attributes(body: dict, headers: dict) -> dict:
    """Extract various attributes for sns, like applicationName, actor email, and event name

    These are used as MessageAttributes on the published message.

    Note: attributes cannot contain empty values
    """
    attributes = {}
    try:
        app_name = body['id']['applicationName']
    except KeyError:
        # There is a bug with the chrome application, and the "watch" api does not
        # return the id.applicationName in the payload. In this case, we extract it
        # from the resource URI header + inject it into the body
        app_name = None
        LOGGER.error(
            'id.applicationName not found in body; falling back on uri resource header: %s',
            headers[HEADER_RESOURCE_URI]
        )

    if not app_name:
        uri = urlparse(headers[HEADER_RESOURCE_URI])
        app_name = pathlib.Path(uri.path).name
        LOGGER.debug('Extracted application %s from uri %s', app_name, uri)
        # insert the app name into the body
        body['id']['applicationName'] = app_name

    if app_name:
        attributes['application'] = {
            'DataType': 'String',
            'StringValue': app_name
        }

    if headers.get(HEADER_RESOURCE_STATE):
        attributes['event'] = {
            'DataType': 'String',
            'StringValue': headers.get(HEADER_RESOURCE_STATE)
        }

    try:
        if body['actor']['email']:
            attributes['actor_email'] = {
                'DataType': 'String',
                'StringValue': body['actor']['email']
            }
    except KeyError:
        pass

    return attributes


def handler(event: dict, _):
    headers = event['headers']

    if headers.get(HEADER_CHANNEL_TOKEN) != EXPECTED_CHANNEL_TOKEN:
        raise RuntimeError('Invalid event', event)

    if headers.get(HEADER_RESOURCE_STATE) == 'sync':
        LOGGER.debug('Skipping sync event: %s', event)
        return  # not an error

    if 'body' not in event:
        raise RuntimeError('body not found in event', event)

    LOGGER.debug('Received valid message: %s', {header: value for header, value in headers.items() if header.startswith('x-goog-')})

    expected_size = int(headers.get(HEADER_CONTENT_LENGTH, 0))
    actual_size = len(event['body'])
    if expected_size != actual_size:
        LOGGER.warning(
            'Found mismatched content-length (%d) and body size (%d)',
            expected_size,
            actual_size
        )

    body = json.loads(event['body'])

    # Do this here, as it can modify the body to inject the applicationName
    attributes = extract_attributes(body, headers)

    response = SNS_TOPIC.publish(
        Message=json.dumps(body, separators=(',', ':')),
        # Add some message attributes to support SNS subscription filtering
        MessageAttributes=attributes
    )

    LOGGER.debug('Published message to sns: %s', response)
