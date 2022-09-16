import base64
import json
import os
from unittest import mock

import pytest

ENV = {
    'PREFIX': 'foo',
    'POWERTOOLS_METRICS_NAMESPACE': 'gsuite-logs-channeler',
}

with mock.patch.dict(os.environ, ENV):
    from deduplication.main import _dedupe


@pytest.mark.parametrize('t_records, t_results', [
    (
        [
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567890'}},
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567890'}},
        ],
        (
            [
                'Ok',
                'Dropped',
            ],
            1
        )
    ),
    (
        [
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567890'}},
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567891'}},
        ],
        (
            [
                'Ok',
                'Ok',
            ],
            0
        )
    ),
    (
        [
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567890'}},
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567891'}},
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567890'}},
            {'id': {'time': '2022-07-27T06:30:00.000Z', 'uniqueQualifier': '1234567891'}},
        ],
        (
            [
                'Ok',
                'Ok',
                'Dropped',
                'Dropped',
            ],
            2
        )
    ),
])
def test_dedupe(t_records, t_results):

    expected_results, expected_duplicates = t_results

    records = []
    for item in t_records:
        records.append({
            'data': base64.b64encode(json.dumps(item).encode()),
            'recordId': 'foobar',
        })

    result, duplicates = _dedupe(records)
    results = [res['result'] for res in result]

    assert all(res['data'] for res in result)
    assert duplicates == expected_duplicates
    assert results == expected_results
