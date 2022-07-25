import os
from unittest import mock

from .. import TEST_TOKEN

TEST_APP_NAME = 'foo_app'
TEST_URL = 'https://foo.lambda.url'

with mock.patch.dict(os.environ, {'CHANNEL_TOKEN': TEST_TOKEN}):
    from channel_renewer import main


class TestChanneler:

    def setup_method(self):
        with mock.patch.object(main.Channeler, '_create_service'):
            self._channeler = main.Channeler(None, None)

    def test_stop_channel(self):
        self._channeler.stop_channel('resource-id', 'chan-id')
        self._channeler._service.channels.return_value.stop.assert_called_with(  # pylint: disable=no-member
            body={'resourceId': 'resource-id', 'id': 'chan-id'}
        )

    def test_create_channel(self):
        # ref: https://developers.google.com/admin-sdk/reports/v1/guides/push#watch-response
        watch_response = {
          'kind': 'api#channel',
          'id': '26706b83-ab7a-49a9-a0cd-8c9b723df9a2', # ID you specified for this channel (random if not specified)
          'resourceId': 'o3hgv1538sdjfh', # ID of the watched resource.
          'resourceUri': 'https://admin.googleapis.com/admin/reports/v1/activity/userKey/applications/applicationName', # Version-specific ID of the watched resource.
          'token': 'custom-token', # Present only if one was provided.
          'expiration': 1658320774000, # Actual expiration time as Unix timestamp (in ms), if applicable.
        }
        self._channeler._service.activities.return_value.watch.return_value.execute.return_value = watch_response  # pylint: disable=no-member


        result = self._channeler.create_channel(TEST_APP_NAME, TEST_URL, TEST_TOKEN)
        self._channeler._service.activities.return_value.watch.assert_called_with(  # pylint: disable=no-member
            userKey='all',
            applicationName=TEST_APP_NAME,
            body={
                'id': mock.ANY,
                'token': TEST_TOKEN,
                'type': 'web_hook',
                'address': TEST_URL,
            }
        )

        assert result == {
            'application': TEST_APP_NAME,
            'expiration': '2022-07-20T12:24:34+00:00',
            'true_deadline': '2022-07-20T12:39:34+00:00',
            'resource_id': 'o3hgv1538sdjfh',
            'channel_id': '26706b83-ab7a-49a9-a0cd-8c9b723df9a2',
        }
