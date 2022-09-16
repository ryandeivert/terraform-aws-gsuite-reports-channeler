import base64
import json
import logging
import os

from aws_lambda_powertools import Metrics
from aws_lambda_powertools.metrics import MetricUnit

metrics = Metrics()
metrics.set_default_dimensions(environment=os.environ['PREFIX'])

logging.basicConfig()

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

RESULT_OK = 'Ok'
RESULT_DROPPED = 'Dropped'


@metrics.log_metrics
def handler(event: dict, _) -> dict:
    """Analyze a batch of records and mark any duplicates as Dropped"""
    LOGGER.debug('Received %d records in event: %s', len(event['records']), event)

    records, dropped = _dedupe(event['records'])

    metrics.add_metric(name='DroppedDuplicates', unit=MetricUnit.Count, value=dropped)

    return {'records': records}


def _dedupe(records: list[dict]) -> tuple[list[dict], int]:
    ids = set()
    results = []
    dropped = 0
    for record in records:
        LOGGER.debug('Processing record with ID: %s', record['recordId'])
        payload = base64.b64decode(record['data'])

        output_record = {
            'recordId': record['recordId'],
            'result': RESULT_OK,
            'data': record['data'],
        }
        data = json.loads(payload)
        try:
            uniq_key = f"{data['id']['time']}:{data['id']['uniqueQualifier']}"
        except KeyError as err:
            LOGGER.warning('Unique key could not be contstructed: %s (id: %s)', err, data.get('id'))
        else:
            if uniq_key not in ids:
                ids.add(uniq_key)
            else:
                output_record['result'] = RESULT_DROPPED
                dropped += 1
        finally:
            results.append(output_record)
    
    return results, dropped
