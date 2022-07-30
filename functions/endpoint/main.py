from datetime import datetime, timezone
import json
import logging
import os
import pathlib
from urllib.parse import urlparse

from aws_lambda_powertools import Metrics
from aws_lambda_powertools.metrics import MetricUnit
import boto3

HEADER_CHANNEL_TOKEN = 'x-goog-channel-token'           # custom token, must match expected token
HEADER_CHANNEL_EXPIRATION = 'x-goog-channel-expiration' # "Wed, 27 Jul 2022 07:24:08 GMT"
HEADER_RESOURCE_STATE = 'x-goog-resource-state'         # "sync", "download", etc
HEADER_RESOURCE_URI = 'x-goog-resource-uri'             # path of resource (eg: applicationName)
HEADER_CONTENT_LENGTH = 'content-length'                # integer for body size

EXPIRATION_FORMAT = '%a, %d %b %Y %H:%M:%S %Z' # header value: "Wed, 27 Jul 2022 07:24:08 GMT"

metrics = Metrics()
metrics.set_default_dimensions(environment=os.environ['PREFIX'])

logging.basicConfig()
LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

EXPECTED_CHANNEL_TOKEN = os.environ['CHANNEL_TOKEN']
SNS_TOPIC = boto3.resource('sns').Topic(os.environ['SNS_TOPIC_ARN'])


def app_from_event(body: dict, headers: dict) -> str:
    try:
        if body['id']['applicationName']:
            return body['id']['applicationName']
    except KeyError:
        # There is a bug with the chrome application, and the "watch" api does not
        # return the id.applicationName in the payload. In this case, we extract it
        # from the resource URI header + inject it into the body
        LOGGER.error(
            'id.applicationName not found in body; falling back on uri resource header: %s',
            headers[HEADER_RESOURCE_URI]
        )
        metrics.add_metric(name='BodyMissingApplication', unit=MetricUnit.Count, value=1)

    uri = urlparse(headers.get(HEADER_RESOURCE_URI, ''))
    app_name = pathlib.Path(uri.path).name
    LOGGER.debug('Extracted application %s from uri %s', app_name, uri)

    app_name = app_name or 'unknown' # avoid empty value for app_name

    # insert the app name into the body
    body['id']['applicationName'] = app_name

    return app_name


def extract_attributes(app_name: str, body: dict, headers: dict) -> dict:
    """Extract various attributes for sns, like applicationName, actor email, and event name

    These are used as MessageAttributes on the published message.

    Note: attributes cannot contain empty values
    """
    attributes = {
        'application': {
            'DataType': 'String',
            'StringValue': app_name
        }
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


def time_now() -> datetime:
    return datetime.now(tz=timezone.utc)


def log_expiration(received_time: datetime, expiration: str):
    """Log number of seconds until expiration for this channel

    This can be use to create an alarm if, for some reason, a channel is not properly renewed
    """
    if not expiration:
        return
    exp = datetime.strptime(expiration, EXPIRATION_FORMAT).replace(tzinfo=timezone.utc)
    delta = exp - received_time
    metrics.add_metric(
        name='ChannelTTL',
        unit=MetricUnit.Seconds,
        value=round(delta.total_seconds())
    )


@metrics.log_metrics
def handler(event: dict, _):
    headers = event['headers']

    received_time = time_now()

    if headers.get(HEADER_CHANNEL_TOKEN) != EXPECTED_CHANNEL_TOKEN:
        raise RuntimeError('Invalid event', event)

    if headers.get(HEADER_RESOURCE_STATE) == 'sync':
        LOGGER.debug('Skipping sync event: %s', event)
        return  # not an error

    if 'body' not in event:
        raise RuntimeError('body not found in event', event)

    LOGGER.debug('Received valid message: %s', {header: value for header, value in headers.items() if header.startswith('x-goog-')})
    metrics.add_metric(name='ValidEvents', unit=MetricUnit.Count, value=1)

    log_expiration(received_time, headers.get(HEADER_CHANNEL_EXPIRATION))

    body = json.loads(event['body'])
    app_name = app_from_event(body, headers)
    attributes = extract_attributes(app_name, body, headers)

    metrics.add_dimension(name='application', value=app_name)

    expected_size = int(headers.get(HEADER_CONTENT_LENGTH, 0))
    actual_size = len(event['body'])
    if expected_size != actual_size:
        metrics.add_metric(name='MismatchedContentLength', unit=MetricUnit.Count, value=1)
        LOGGER.warning(
            'Found mismatched content-length (%d) and body size (%d)',
            expected_size,
            actual_size
        )

    response = SNS_TOPIC.publish(
        Message=json.dumps(body, separators=(',', ':')),
        # Add some message attributes to support SNS subscription filtering
        MessageAttributes=attributes
    )

    LOGGER.debug('Published message to sns: %s', response)
