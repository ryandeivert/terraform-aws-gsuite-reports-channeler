import json
import logging
import os
from unittest import mock

import boto3
from moto import mock_sns
import pytest

from .. import TEST_TOKEN

TOPIC_NAME = 'foo-topic'
ENV = {
    'CHANNEL_TOKEN': TEST_TOKEN,
    'SNS_TOPIC_ARN': f'arn:aws:sns:us-east-1:123456789012:{TOPIC_NAME}',
    'AWS_DEFAULT_REGION': 'us-east-1',
}

with mock.patch.dict(os.environ, ENV):
    from endpoint import main


@pytest.fixture(name='env_vars')
def fixture_env_vars():
    with mock.patch.dict(os.environ, ENV):
        yield


@pytest.fixture(name='sns')
def fixture_sns(env_vars):  # pylint: disable=unused-argument
    with mock_sns():
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
        with pytest.raises(RuntimeError) as excinfo:
            main.handler(
                {
                    'headers': {
                        main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    }
                },
                None
            )
        assert 'body not found in event' in str(excinfo.value)

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

    def test_main_valid(self, caplog, sns):  # pylint: disable=unused-argument
        caplog.set_level(logging.DEBUG, logger=main.LOGGER.name)
        with caplog.at_level(logging.DEBUG):
            main.handler(
                {
                    'headers': {
                        main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                        main.HEADER_CONTENT_LENGTH: 14,
                    },
                    'body': '{"id": {"applicationName": "admin"}, "actor": {"email": "foo@bar.com"}}'
                },
                None
            )

        assert 'Published message to sns' in caplog.text


EXPECTED_ATTRIBUTE_APPLICATION_ADMIN = {
    'application': {
        'DataType': 'String',
        'StringValue': 'admin',
    },
}

EXPECTED_ATTRIBUTE_APPLICATION_CHROME = {
    'application': {
        'DataType': 'String',
        'StringValue': 'chrome',
    },
}

EXPECTED_ATTRIBUTE_ACTOR_EMAIL = {
    'actor_email': {
        'DataType': 'String',
        'StringValue': 'foo@bar.com'
    },
}

ATTRIBUTE_TESTS = [
    # test-00
    (
        {
            'id': {
                'applicationName': 'admin'
            },
            'actor': {
                'email': 'foo@bar.com'
            },
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_ADMIN,
            **EXPECTED_ATTRIBUTE_ACTOR_EMAIL,
        },
    ),
    # test-01
    (
        {
            'id': {
                'applicationName': 'admin'
            },
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_ADMIN,
        },
    ),
    # test-02
    (
        {
            'id': {},
            'actor': {
                'email': 'foo@bar.com'
            },
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_CHROME,
            **EXPECTED_ATTRIBUTE_ACTOR_EMAIL,
        },
    ),
    # test-03
    (
        {
            'id': {
                'applicationName': None
            },
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_CHROME,
        },
    ),
    # test-04
    (
        {
            'id': {
                'applicationName': None
            },
            'actor': {
                'email': 'foo@bar.com'
            },
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_CHROME,
            **EXPECTED_ATTRIBUTE_ACTOR_EMAIL,
        },
    ),
    # test-05
    (
        {
            'id': {},
            'actor': {
                'email': ''
            },
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_CHROME,
        },
    ),
    # test-06
    (
        {
            'id': {},
        },
        {
            **EXPECTED_ATTRIBUTE_APPLICATION_CHROME,
        },
    ),
]

TEST_HEADERS = {
    'x-goog-resource-uri': 'https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/chrome?alt=json&orgUnitID',
}

@pytest.mark.parametrize('t_input, t_output', ATTRIBUTE_TESTS)
def test_extract_attributes(t_input, t_output):
    assert main.extract_attributes(t_input, TEST_HEADERS) == t_output
