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
}


@pytest.fixture(autouse=True)
def env_vars():
    with mock.patch.dict(os.environ, ENV):
        yield


class TestEndpoint:

    def setup_method(self):
        from endpoint import main  # pylint: disable=import-outside-toplevel
        self._main = main

    @pytest.fixture(scope='class', autouse=True)
    def sns(self, aws_credentials):  # pylint: disable=unused-argument
        with mock_sns():
            resource = boto3.resource('sns')
            resource.create_topic(Name=TOPIC_NAME)
            yield resource

    def test_missing_token(self):
        with pytest.raises(RuntimeError) as excinfo:
            self._main.handler({'headers': {}}, None)
        assert 'Invalid event' in str(excinfo.value)

    def test_skip_sync(self, caplog):
        caplog.set_level(logging.DEBUG, logger=self._main.LOGGER.name)
        with caplog.at_level(logging.DEBUG):
            self._main.handler(
                {
                    'headers': {
                        self._main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                        self._main.HEADER_RESOURCE_STATE: 'sync',
                    }
                },
                None
            )

        assert 'Skipping sync event' in caplog.text

    def test_missing_body(self):
        with pytest.raises(RuntimeError) as excinfo:
            self._main.handler(
                {
                    'headers': {
                        self._main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    }
                },
                None
            )
        assert 'body not found in event' in str(excinfo.value)

    def test_invalid_size(self, caplog):
        self._main.handler(
            {
                'headers': {
                    self._main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    self._main.HEADER_CONTENT_LENGTH: 10,  # wrong length
                },
                'body': '{"id": {"applicationName": "admin"}, "actor": {"email": "foo@bar.com"}}'
            },
            None
        )

        assert 'Found mismatched content-length (10) and body size (71)' in caplog.text

    def test_invalid_body(self):
        with pytest.raises(json.JSONDecodeError):
            self._main.handler(
                {
                    'headers': {
                        self._main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    },
                    'body': 'bad json'
                },
                None
            )

    def test_main_valid(self, caplog):
        self._main.handler(
            {
                'headers': {
                    self._main.HEADER_CHANNEL_TOKEN: TEST_TOKEN,
                    self._main.HEADER_CONTENT_LENGTH: 14,
                },
                'body': '{"id": {"applicationName": "admin"}, "actor": {"email": "foo@bar.com"}}'
            },
            None
        )

        assert 'Published message to sns' in caplog.text
