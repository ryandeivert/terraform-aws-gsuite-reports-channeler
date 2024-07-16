# pylint: disable=missing-module-docstring,missing-class-docstring,missing-function-docstring,line-too-long
from datetime import datetime, timezone
import json
import logging
import os
from unittest import mock

from aws_lambda_powertools import Metrics
from aws_lambda_powertools.metrics import MetricUnit
import boto3
from moto import mock_aws
import pytest

from .. import TEST_TOKEN

# 'Wed, 27 Jul 2022 07:00:00 GMT' aka '2022-07-27T07:00:00+00:00'
MOCK_RECEIVED_TIME = datetime(2022, 7, 27, 7, 0, 0, tzinfo=timezone.utc)
TOPIC_NAME = 'foo-topic'
ENV = {
    'PREFIX': 'foo',
    'CHANNEL_TOKEN': TEST_TOKEN,
    'SNS_TOPIC_ARN': f'arn:aws:sns:us-east-1:123456789012:{TOPIC_NAME}',
    'AWS_DEFAULT_REGION': 'us-east-1',
    'POWERTOOLS_METRICS_NAMESPACE': 'gsuite-logs-channeler',
}

with mock.patch.dict(os.environ, ENV):
    from endpoint import main


@pytest.fixture(name='env_vars')
def fixture_env_vars():
    with mock.patch.dict(os.environ, ENV):
        yield


@pytest.fixture(name='sns')
def fixture_sns(env_vars):  # pylint: disable=unused-argument
    with mock_aws():
        resource = boto3.resource('sns')
        resource.create_topic(Name=TOPIC_NAME)
        main.SNS_TOPIC = resource.Topic(os.environ['SNS_TOPIC_ARN'])
        yield resource


class TestEndpoint:

    def test_missing_token(self):
        with pytest.raises(RuntimeError) as excinfo:
            main.handler({'headers': {}}, None)
        assert 'Invalid event' in str(excinfo.value)

    def test_skip_sync(self, caplog):
        caplog.set_level(logging.DEBUG, logger=main.LOGGER.name)
        with caplog.at_level(logging.DEBUG):
            main.handler(
                {
                    'headers': {
                        main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                        main.HEADER_RESOURCE_STATE: 'sync',
                    }
                },
                None
            )

        assert 'Skipping sync event' in caplog.text

    def test_missing_body(self):
        with pytest.raises(RuntimeError):
            main.handler(
                {
                    'headers': {
                        main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    }
                },
                None
            )

    def test_invalid_size(self, caplog, sns):  # pylint: disable=unused-argument
        main.handler(
            {
                'headers': {
                    main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    main.HEADER_CONTENT_LENGTH: 10,  # wrong length
                },
                'body': '{"id": {"applicationName": "admin"}, "actor": {"email": "foo@bar.com"}}'
            },
            None
        )

        assert 'Found mismatched content-length (10) and body size (71)' in caplog.text

    def test_invalid_body(self):
        with pytest.raises(json.JSONDecodeError):
            main.handler(
                {
                    'headers': {
                        main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    },
                    'body': 'bad json'
                },
                None
            )

    def test_main_valid(self, caplog, sns, static_time_now):  # pylint: disable=unused-argument
        caplog.set_level(logging.DEBUG, logger=main.LOGGER.name)
        with caplog.at_level(logging.DEBUG):
            main.handler(
                {
                    'headers': {
                        main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                        main.HEADER_CONTENT_LENGTH: 14,
                        main.HEADER_CHANNEL_EXPIRATION: 'Wed, 27 Jul 2022 10:00:00 GMT',
                    },
                    'body': '{"id": {"applicationName": "admin"}, "actor": {"email": "foo@bar.com"}}'
                },
                None
            )

        assert 'Published message to sns' in caplog.text


@pytest.mark.parametrize('body, headers, app_name', [
    (
        {
            'id': {
                'applicationName': None
            }
        },
        {
            'x-goog-resource-uri': 'https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/chrome?alt=json&orgUnitID',
        },
        'chrome',
    ),
    (
        {
            'id': {
                'applicationName': 'admin'
            }
        },
        {},
        'admin',
    ),
    (
        {
            'id': {
                'applicationName': None
            }
        },
        {},
        'unknown',
    ),
])
def test_app_from_event(body, headers, app_name):
    assert main.app_from_event(body, headers) == app_name


@pytest.fixture(name='static_time_now')
def fixture_static_time_now():
    with mock.patch.object(main, 'time_now') as time_mock:
        time_mock.return_value = MOCK_RECEIVED_TIME
        yield time_mock


@pytest.mark.parametrize('body, expiration, ttl, delta', [
    ({'id': {'time': '2022-07-27T06:30:00.000Z'}}, 'Wed, 27 Jul 2022 10:00:00 GMT', 10800, 1800), # 3 hours / 30 min
    ({'id': {'time': '2022-07-27T06:59:58.461Z'}}, 'Wed, 27 Jul 2022 08:30:00 GMT', 5400, 2), # 1 hour, 30 min / 2 sec (rounds up)
    ({'id': {'time': '2022-07-27T06:30:00.000Z'}}, 'Wed, 27 Jul 2022 07:15:00 GMT', 900, 1800), # 15 min / 30 min
])
def test_add_metrics(body, expiration, ttl, delta):
    with mock.patch.object(Metrics, 'add_metric') as metric_mock:
        main.add_metrics(body, MOCK_RECEIVED_TIME, expiration)
        metric_mock.assert_any_call(name='ChannelTTL', unit=MetricUnit.Seconds, value=ttl)
        metric_mock.assert_any_call(name='EventLagTime', unit=MetricUnit.Seconds, value=delta)


def test_add_metrics_no_time():
    with mock.patch.object(Metrics, 'add_metric') as metric_mock:
        main.add_metrics({}, MOCK_RECEIVED_TIME, None)
        metric_mock.assert_called_once()


def test_send_to_sns():
    with mock.patch.object(main.SNS_TOPIC, 'publish') as publish_mock, \
            mock.patch.object(Metrics, 'add_metric') as metric_mock:
        publish_mock.side_effect = main.SNS_TOPIC.meta.client.exceptions.InvalidParameterException(
            {'Error': {'Code': 'InvalidParameter', 'Message': 'Invalid parameter: Message too long'}},
            'Publish'
        )
        main.send_to_sns({})
        metric_mock.assert_called_with(name='DroppedEvents', unit=MetricUnit.Count, value=1)
