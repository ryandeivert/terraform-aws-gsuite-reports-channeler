from datetime import datetime, timedelta, timezone
import json
import logging
import os

import boto3
from googleapiclient import channel, discovery, errors
from google.oauth2 import service_account
from google.auth.exceptions import GoogleAuthError

logging.basicConfig()

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))
EXPECTED_CHANNEL_TOKEN = os.environ['CHANNEL_TOKEN']


def _get_secrets(secret_name):
    client = boto3.client('secretsmanager')
    secret = client.get_secret_value(SecretId=secret_name)
    return json.loads(secret['SecretString'])


class Channeler:

    def __init__(self, keydata, email):
        self._service = self._create_service(keydata, email)

    @staticmethod
    def _create_service(keydata, email):
        """Create the google api service, which signs requests with the private key data"""
        LOGGER.debug('Creating activities service')

        try:
            creds = service_account.Credentials.from_service_account_info(
                keydata,
                scopes=['https://www.googleapis.com/auth/admin.reports.audit.readonly'],
            )
        except (ValueError, KeyError) as err:
            raise RuntimeError('Could not generate credentials from key data') from err

        try:
            return discovery.build(
                'admin',
                'reports_v1',
                credentials=creds.with_subject(email)
            )
        except (errors.Error, GoogleAuthError) as err:
            raise RuntimeError('Failed to build discovery service') from err

    def stop_channel(self, resource_id, channel_id):
        LOGGER.info('Stopping channel %s for resource %s', channel_id, resource_id)
        body = {
            'resourceId': resource_id,
            'id': channel_id
        }

        self._service.channels().stop(body=body).execute()  # pylint: disable=no-member

    def create_channel(self, app_name, url, token):
        """Create a new channel for activities for this app

        Example result for call to watch():
        {
            'kind': 'api#channel',
            'id': 'f4743e41-35cb-4c6f-b304-8861ca184f85',
            'resourceId': 'piBZLTsMqOx__X3LeO3ilYzUBpU',
            'resourceUri': 'https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/drive?alt=json&orgUnitID',
            'token': '<token>',
            'expiration': '1658320774000'
        }
        """
        chan = channel.new_webhook_channel(url, token=token)

        action = self._service.activities().watch(  # pylint: disable=no-member
            userKey='all',
            applicationName=app_name,
            body=chan.body(),
        )

        LOGGER.debug('Creating channel: %s', action.to_json())
        result = action.execute()

        # Convert expiration from ms to seconds
        exp = datetime.fromtimestamp(int(result['expiration']) / 1000, tz=timezone.utc)
        LOGGER.info(
            'Created channel %s for resource %s with expiration %s [%s] (uri: %s)',
            result['id'],
            result['resourceId'],
            exp.isoformat(),
            result['expiration'],
            result['resourceUri'],
        )

        delta = exp - timedelta(minutes=int(os.environ.get('REFRESH_THRESHOLD_MIN', 15)))
        return {
            'application': app_name,
            'expiration': delta.isoformat(),
            'true_deadline': exp.isoformat(),
            'resource_id': result['resourceId'],
            'channel_id': result['id'],
        }


def _init_step_function(channel_info):
    """Start the step function manually for the first time

    When the step function is started for the very first time, a brief
    expiration is used before continuing on.

    The last state in the step function executes the step function again,
    and inherits details the previous execution, created a chain effect
    """
    LOGGER.info('Starting step function: %s', channel_info)

    response = boto3.client('stepfunctions').start_execution(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        input=json.dumps(channel_info),
        name=f'{channel_info["application"]}_{channel_info["channel_id"]}',
    )

    LOGGER.info('Started step function: %s', response)


def handler(event, _):
    """
    This lambda is typically invoked after a "wait" state in a step function

    When invoked from the step function, the event will contain a number of
    necessary values needed to handle channel start/stopping. The existence
    of "resource_id" and "channel_id" values indicates an old channel that should
    be stopped after a new one is created.

    Example event:
        {
            "application": "<app-name>",
            "resource_id": "<resource-id>",
            "channel_id": "<channel-id>",
            "expiration": "<expiration>"
        }

    """
    LOGGER.debug('Received event: %s', event)

    keydata = _get_secrets(os.environ['SECRET_NAME'])
    LOGGER.debug('Loaded secret data with keys: %s', list(keydata.keys()))

    client = Channeler(keydata, os.environ['DELEGATION_EMAIL'])

    # Create a new channel. This should occur before any old channels are stopped
    channel_info = client.create_channel(
        event['application'],
        os.environ['LAMBDA_URL'],
        os.environ['CHANNEL_TOKEN']
    )

    if 'channel_id' not in event:
        # This is the first channel opened, so begin the step function execution
        _init_step_function(channel_info)
    else:
        # Stop the old channel only after a new one is created above
        client.stop_channel(event['resource_id'], event['channel_id'])

    return channel_info  # passed on to next step function invocation
