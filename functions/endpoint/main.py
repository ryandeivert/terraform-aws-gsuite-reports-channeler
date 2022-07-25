import json
import logging
import os

import boto3

logging.basicConfig()

HEADER_CHANNEL_TOKEN = 'x-goog-channel-token'   # custom token, should match above
HEADER_RESOURCE_STATE = 'x-goog-resource-state' # "sync", "download", etc
HEADER_CONTENT_LENGTH = 'content-length'        # integer for body size

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

EXPECTED_CHANNEL_TOKEN = os.environ['CHANNEL_TOKEN']
SNS_TOPIC = boto3.resource('sns').Topic(os.environ['SNS_TOPIC_ARN'])


def handler(event, _):
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

    response = SNS_TOPIC.publish(
        Message=json.dumps(body, separators=(',', ':')),
        # Add some message attributes to support SNS subscription filtering
        MessageAttributes={
            'application': {
                'DataType': 'String',
                'StringValue': body['id']['applicationName']
            },
            'actor_email': {
                'DataType': 'String',
                'StringValue': body['actor']['email']
            },
        }
    )

    LOGGER.info('Published message to sns: %s', response)
