import base64
import json
import logging
import os

logging.basicConfig()

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))


def handler(event: dict, _) -> dict:
    """
    Analyze a batch of records and drop any duplicates
    """
    LOGGER.info('Received event: %s', event)

    ids = set()
    records = []

    LOGGER.info('Processing %d records', len(event['records']))

    for record in event['records']:
        LOGGER.info('Processing record with ID: %s', record['recordId'])
        LOGGER.debug('Full record contents: %s', record) # TODO: remove this
        payload = base64.b64decode(record['data'])

        output_record = {
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': record['data'],
        }
        data = json.loads(payload)
        try:
            uniq_key = f"{data['id']['time']}:{data['id']['uniqueQualifier']}"
        except KeyError as err:
            LOGGER.warning('unique key could not be contstructed: %s', err)
            record['result'] = 'ProcessingFailed'
        else:
            if uniq_key not in ids:
                ids.add(uniq_key)
            else:
                record['result'] = 'Dropped'
                LOGGER.info('Dropping duplicate record: %s', uniq_key)
        finally:
            records.append(output_record)

    return {'records': records}
