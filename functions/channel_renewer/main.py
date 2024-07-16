"""
Lambda function to renew Google Admin (reports) SDK Push Notification channels
using the "watch" api
Reference: https://developers.google.com/admin-sdk/reports/v1/guides/push
"""
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


def _get_secrets(secret_name: str):
    client = boto3.client('secretsmanager')
    secret = client.get_secret_value(SecretId=secret_name)
    return json.loads(secret['SecretString'])


class Channeler:
    """Class to perform Google Admin SDK push notification watch/stop operations"""
    def __init__(self, keydata: dict, email: str):
        self._service = self._create_service(keydata, email)

    @staticmethod
    def _create_service(keydata: dict, email: str):
        """Create the google api service, which signs requests with the private key data

        Args:
            keydata (dict): The private key data for the service account
            email (str): The delegation email address for the service account
        """
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

    def stop_channel(self, resource_id: str, channel_id: str):
        """Stop an existing channel for a resource

        Args:
            resource_id (str): The resource ID for the channel
            channel_id (str): The channel ID to stop
        """
        LOGGER.info('Stopping channel %s for resource %s', channel_id, resource_id)
        body = {
            'resourceId': resource_id,
            'id': channel_id
        }

        self._service.channels().stop(body=body).execute()  # pylint: disable=no-member

    def create_channel(self, app_name: str, url: str, token: str):
        # pylint: disable=line-too-long
        """Create a new channel for activities for this app

        Args:
            app_name (str): The application name to watch
            url (str): The URL to which notifications should be sent (endpoint Lambda)
            token (str): Unique token that Google will include in all notifications

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
        # pylint: enable=line-too-long
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


def _init_step_function(channel_info: dict):
    """Start the step function manually for the first time using channel details

    Args:
        channel_info (dict): The channel information to pass to the step function
            containing metadata such as application name, resource ID, channel ID, and
            expiration. The expiration is used in an initial wait state of the SFN.
    """
    LOGGER.info('Starting step function: %s', channel_info)

    response = boto3.client('stepfunctions').start_execution(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        input=json.dumps(channel_info),
        name=f'{channel_info["application"]}_{channel_info["channel_id"]}',
    )

    LOGGER.info('Started step function: %s', response)


def _stop_step_function(channeler: Channeler, application: str) -> tuple[str, str]:
    """Stop the step function for this application

    Uses the resource and channel ID for this channel from the context of the
    stopped step function to also stop the notification channel

    Args:
        channeler (Channeler): The channeler object used to stop the notification channel
        application (str): The application name which is being stopped
    """
    LOGGER.info('Stopping step function for application: %s', application)

    snf_client = boto3.client('stepfunctions')

    response_iterator = snf_client.get_paginator('list_executions').paginate(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        statusFilter='RUNNING',
    )

    # Filter to only executions that are for this application
    filtered_iterator = response_iterator.search(
        f'executions[?starts_with(name, `{application}`)].executionArn'
    )

    # There should only be one active execution per app, but iterate just in case (?)
    for execution_arn in filtered_iterator:

        LOGGER.info('Stopping step function: %s', execution_arn)

        response = snf_client.stop_execution(
            executionArn=execution_arn,
            error='ManualStop',
            cause='received request to stop step function'
        )

        LOGGER.info('Stopped step function: %s', response)

        # load the resource ID and channel ID from execution input
        response = snf_client.describe_execution(executionArn=execution_arn)
        execution_input = json.loads(response['input'])

        LOGGER.debug(
            'Loaded input from step function execution (%s): %s',
            execution_arn,
            execution_input
        )

        try:
            channeler.stop_channel(execution_input['resource_id'], execution_input['channel_id'])
        except errors.Error as err:
            # Log error for potentially already stopped channel
            LOGGER.error('Channel could not be stopped: %s', err)


def handler(event: dict, _) -> dict:
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
    LOGGER.info('Received event: %s', event)

    keydata = _get_secrets(os.environ['SECRET_NAME'])
    LOGGER.debug('Loaded secret data with keys: %s', list(keydata.keys()))

    client = Channeler(keydata, os.environ['DELEGATION_EMAIL'])

    action = event.get('lambda_action')
    if action == 'stop':
        _stop_step_function(client, event['application'])
        return None

    # EventBridge rule triggering a recover event
    # Swap out the event for the old input and try to restart this execution
    if action == 'recover':
        event = json.loads(event['input'])

    # Create a new channel. This should occur before any old channels are stopped
    channel_info = client.create_channel(
        event['application'],
        os.environ['LAMBDA_URL'],
        os.environ['CHANNEL_TOKEN']
    )

    if action in {'init', 'recover'}:
        # This is the first channel opened, or the pipeline is recovering
        # from a failure, so start the step function execution
        _init_step_function(channel_info)

    if action == 'init':
        return channel_info  # no old channels to handle, so return

    # Stop the old channel only after a new one is created above
    client.stop_channel(event['resource_id'], event['channel_id'])

    return channel_info  # passed on to next step function invocation
