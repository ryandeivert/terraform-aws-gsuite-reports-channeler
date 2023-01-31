from datetime import datetime, timezone
import json
import logging
import os
import pathlib
from urllib.parse import urlparse

from aws_lambda_powertools import Metrics
from aws_lambda_powertools.metrics import MetricUnit
from aws_lambda_powertools.utilities.data_classes import event_source, LambdaFunctionUrlEvent
import boto3

HEADER_CHANNEL_TOKEN = 'x-goog-channel-token'           # custom token, must match expected token
HEADER_CHANNEL_EXPIRATION = 'x-goog-channel-expiration' # "Wed, 27 Jul 2022 07:24:08 GMT"
HEADER_RESOURCE_STATE = 'x-goog-resource-state'         # "sync", "download", etc
HEADER_RESOURCE_URI = 'x-goog-resource-uri'             # path of resource (eg: applicationName)
HEADER_CONTENT_LENGTH = 'content-length'                # integer for body size
EVENT_TYPE_SYNC = 'sync'

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


def time_now() -> datetime:
    return datetime.now(tz=timezone.utc)


def add_metrics(body: dict, received_time: datetime, expiration: str):
    """Log various metrics related to this event
    
    Metrics:
      - single data point representing this event (as "ValidEvents")
      - number of seconds until expiration for this channel (as "ChannelTTL")
      - number of seconds between the time this event was received by us
        and the when the event occurred (as "EventLagTime"). Reference:
        https://support.google.com/a/answer/7061566

    These metrics can be used to create alarms. For example, the ChannelTTL
    metric can be used to detect if a channel has not been properly renewed
    """
    # Log this as a valid event
    metrics.add_metric(name='ValidEvents', unit=MetricUnit.Count, value=1)

    try:
        event_time = body['id']['time']
    except KeyError:
        LOGGER.error('id.time not found in body')
    else:
        # Strip the trailing Z for UTC that python cannot handle well
        event_time = event_time[:-1] if event_time.endswith('Z') else event_time
        parsed_time = datetime.fromisoformat(event_time).replace(tzinfo=timezone.utc)
        delta = received_time - parsed_time
        metrics.add_metric(
            name='EventLagTime',
            unit=MetricUnit.Seconds,
            value=round(delta.total_seconds())
        )

    # Log the TTL for this channel
    if not expiration: # unlikely, but can be null
        return

    exp = datetime.strptime(expiration, EXPIRATION_FORMAT).replace(tzinfo=timezone.utc)
    delta = exp - received_time
    metrics.add_metric(
        name='ChannelTTL',
        unit=MetricUnit.Seconds,
        value=round(delta.total_seconds())
    )


def send_to_sns(body: dict):
    try:
        response = SNS_TOPIC.publish(Message=json.dumps(body, separators=(',', ':')))
    except SNS_TOPIC.meta.client.exceptions.InvalidParameterException as err:
        # This message exceeds SNS limits and we cannot process it as-is
        if 'Message too long' in err.response['Error']['Message']:
            metrics.add_metric(name='DroppedEvents', unit=MetricUnit.Count, value=1)
            return
        raise err # raise any other exception of this type

    LOGGER.debug('Published message to sns: %s', response)


@metrics.log_metrics
@event_source(data_class=LambdaFunctionUrlEvent) # pylint:disable=no-value-for-parameter
def handler(event: LambdaFunctionUrlEvent, _):
    received_time = time_now()

    if event.get_header_value(HEADER_CHANNEL_TOKEN) != EXPECTED_CHANNEL_TOKEN:
        raise RuntimeError('Invalid event', event)

    if event.get_header_value(HEADER_RESOURCE_STATE) == EVENT_TYPE_SYNC:
        LOGGER.debug('Skipping sync event: %s', event)
        return  # not an error

    LOGGER.debug(
        'Received valid message with headers: %s',
        {header: value for header, value in event.headers.items() if header.startswith('x-goog-')}
    )

    # Raises KeyError if "body" is missing
    body = event.json_body

    add_metrics(body, received_time, event.get_header_value(HEADER_CHANNEL_EXPIRATION))

    app_name = app_from_event(body, event.headers)

    metrics.add_dimension(name='application', value=app_name)

    expected_size = int(event.get_header_value(HEADER_CONTENT_LENGTH, 0))
    raw_body_size = len(event.body)
    if expected_size != raw_body_size:
        metrics.add_metric(name='MismatchedContentLength', unit=MetricUnit.Count, value=1)
        LOGGER.warning(
            'Found mismatched content-length (%d) and body size (%d)',
            expected_size,
            raw_body_size
        )

    send_to_sns(body)
