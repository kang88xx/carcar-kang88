import test from 'node:test';
import assert from 'node:assert/strict';
import {CARCAR_AGE_ATTRIBUTES, CARCAR_APP_ID, freeKoreaPricePayload,
  koreaAvailabilityPayload, prepareDistribution} from './app_store_distribution.mjs';

const rel = (type, id) => ({data: {type, id}});
const app = {type: 'apps', id: CARCAR_APP_ID, attributes: {bundleId: 'com.kang88.carcar'}};
function fixture({ready = false, missing = false, autoTerritories = false} = {}) {
  const calls = [];
  let age = {type: 'ageRatingDeclarations', id: 'age1', attributes: ready ? {...CARCAR_AGE_ATTRIBUTES} : {}};
  let schedule = missing ? null : {type: 'appPriceSchedules', id: 'schedule1', relationships: {
    app: rel('apps', CARCAR_APP_ID), baseTerritory: rel('territories', ready ? 'KOR' : 'USA'),
  }};
  const point = {type: 'appPricePoints', id: 'free1', attributes: {customerPrice: '0.00'}, relationships: {
    app: rel('apps', CARCAR_APP_ID), territory: rel('territories', 'KOR'),
  }};
  let prices = ready ? [{type: 'appPrices', id: 'price1', attributes: {startDate: '2020-01-01', endDate: null},
    relationships: {territory: rel('territories', 'KOR'), appPricePoint: rel('appPricePoints', 'free1')}}] : [];
  let availability = missing ? null : {type: 'appAvailabilities', id: 'availability1',
    attributes: {availableInNewTerritories: autoTerritories}};
  let territories = missing ? [] : [
    {type: 'territoryAvailabilities', id: 'kor1', attributes: {available: ready, preOrderEnabled: false}, relationships: {territory: rel('territories', 'KOR')}},
    {type: 'territoryAvailabilities', id: 'usa1', attributes: {available: !ready, preOrderEnabled: false}, relationships: {territory: rel('territories', 'USA')}},
  ];
  const client = {
    app, appInfoId: 'info1',
    async list(path, type) {
      calls.push({path, method: 'GET', type});
      if (path === `/v1/apps/${CARCAR_APP_ID}/appInfos?limit=200`) return [{type: 'appInfos', id: 'info1', attributes: {state: 'PREPARE_FOR_SUBMISSION'}}];
      if (path === '/v1/territories?limit=200') return ['KOR', 'USA', 'CAN'].map(id => ({type: 'territories', id}));
      if (path.startsWith(`/v1/apps/${CARCAR_APP_ID}/appPricePoints?`)) return [point];
      if (path.startsWith('/v1/appPriceSchedules/schedule1/manualPrices?')) return prices;
      if (path.startsWith('/v2/appAvailabilities/availability1/territoryAvailabilities?')) return territories;
      throw new Error('Unexpected list path ' + path);
    },
    async request(path, method = 'GET', body) {
      calls.push({path, method, body});
      if (method === 'GET') {
        if (path === '/v1/appInfos/info1/ageRatingDeclaration') return {data: structuredClone(age)};
        if (path.startsWith(`/v1/apps/${CARCAR_APP_ID}/appPriceSchedule?`)) return {data: structuredClone(schedule)};
        if (path === `/v1/apps/${CARCAR_APP_ID}/appAvailabilityV2`) return {data: structuredClone(availability)};
      }
      if (path === '/v1/ageRatingDeclarations/age1' && method === 'PATCH') {
        Object.assign(age.attributes, body.data.attributes);
        return {data: structuredClone(age)};
      }
      if (path === '/v1/appPriceSchedules' && method === 'POST') {
        assert.deepEqual(body, freeKoreaPricePayload('free1'));
        schedule = {type: 'appPriceSchedules', id: 'schedule1', relationships: body.data.relationships};
        prices = [{type: 'appPrices', id: 'price1', attributes: {startDate: null, endDate: null}, relationships: {
          territory: rel('territories', 'KOR'), appPricePoint: rel('appPricePoints', 'free1'),
        }}];
        return {data: structuredClone(schedule)};
      }
      if (path === '/v2/appAvailabilities' && method === 'POST') {
        assert.equal(availability, null, 'Never overwrite an existing availability using create.');
        assert.deepEqual(body, koreaAvailabilityPayload(['KOR', 'USA', 'CAN']));
        availability = {type: 'appAvailabilities', id: 'availability1', attributes: body.data.attributes};
        territories = body.included.map((item, index) => ({...item, id: 'territory-' + index}));
        return {data: structuredClone(availability)};
      }
      if (path.startsWith('/v1/territoryAvailabilities/') && method === 'PATCH') {
        const item = territories.find(value => value.id === body.data.id);
        assert.ok(item);
        Object.assign(item.attributes, body.data.attributes);
        return {data: structuredClone(item)};
      }
      throw new Error('Unexpected request path ' + path);
    },
  };
  return {client, calls, point};
}

test('default inspect never writes, even with incomplete registration', async () => {
  const {client, calls} = fixture();
  const result = await prepareDistribution(client);
  assert.equal(result.ready, false);
  assert.ok(calls.every(item => item.method === 'GET'));
  assert.deepEqual(result.writes, []);
});

test('wrong app and foreign app information fail before writes', async () => {
  const {client, calls} = fixture();
  await assert.rejects(prepareDistribution({...client, mode: 'prepare', app: {...app, id: 'other'}}), /restricted/);
  assert.equal(calls.length, 0);
  await assert.rejects(prepareDistribution({...client, mode: 'prepare', appInfoId: 'other'}), /does not belong/);
  assert.ok(calls.every(item => item.method === 'GET'));
});

test('URL dot-segment resource IDs are rejected before requests', async () => {
  const {client, calls} = fixture();
  for (const appInfoId of ['.', '..']) {
    await assert.rejects(prepareDistribution({...client, appInfoId}), /Invalid distribution resource/);
  }
  assert.equal(calls.length, 0);
});

test('ready-for-review information can be inspected but never mutated', async () => {
  const {client, calls} = fixture({ready: true});
  const original = client.list;
  client.list = async (path, type) => {
    const result = await original(path, type);
    if (type === 'appInfos') result[0].attributes.state = 'READY_FOR_REVIEW';
    return result;
  };
  assert.equal((await prepareDistribution(client)).ready, true);
  await assert.rejects(prepareDistribution({...client, mode: 'prepare'}), /editable app/);
  assert.ok(calls.every(call => call.method === 'GET'));
});

test('wrong price point app or territory prevents all writes', async () => {
  const {client, calls, point} = fixture();
  point.relationships.app = rel('apps', 'other');
  await assert.rejects(prepareDistribution({...client, mode: 'prepare'}), /Wrong app/);
  assert.ok(calls.every(item => item.method === 'GET'));
});

test('already correct registration including historical free start date makes no writes', async () => {
  const {client, calls} = fixture({ready: true});
  const result = await prepareDistribution({...client, mode: 'prepare'});
  assert.equal(result.ready, true);
  assert.deepEqual(result.blockers, []);
  assert.ok(calls.every(item => item.method === 'GET'));
});

test('prepare makes narrow changes and readback verifies Korea free and exclusive', async () => {
  const {client, calls} = fixture();
  const result = await prepareDistribution({...client, mode: 'prepare'});
  assert.equal(result.ready, true);
  assert.deepEqual(result.availability.territories, ['KOR']);
  const writes = calls.filter(item => item.method !== 'GET');
  assert.equal(writes.length, 4);
  assert.deepEqual(writes.filter(item => item.path.startsWith('/v1/territoryAvailabilities/')).map(item => item.body.data.attributes),
    [{available: true}, {available: false}]);
  const again = await prepareDistribution({...client, mode: 'prepare'});
  assert.equal(again.ready, true);
  assert.deepEqual(again.writes, []);
});

test('create payloads contain matching inline IDs and required relationships', async () => {
  const price = freeKoreaPricePayload('free1');
  assert.equal(price.data.relationships.manualPrices.data[0].id, price.included[0].id);
  assert.equal(price.included[0].relationships.appPricePoint.data.id, 'free1');
  assert.deepEqual(price.included[0].attributes, {startDate: null, endDate: null});
  const available = koreaAvailabilityPayload(['KOR', 'USA', 'CAN']);
  assert.equal(available.data.relationships.territoryAvailabilities.data[0].id, available.included[0].id);
  assert.equal(available.included.length, 3);
  assert.deepEqual(available.included.filter(item => item.attributes.available).map(item => item.relationships.territory.data.id), ['KOR']);
  assert.equal(available.data.attributes.availableInNewTerritories, false);
  const {client} = fixture({missing: true});
  assert.equal((await prepareDistribution({...client, mode: 'prepare'})).ready, true);
});

test('initial availability includes full catalog and rejects malformed catalogs before any writes', async () => {
  for (const ids of [[], ['USA'], ['KOR', 'KOR'], ['KOR', '../USA']]) {
    const {client, calls} = fixture({missing: true});
    const original = client.list;
    client.list = async (path, type) => path === '/v1/territories?limit=200'
      ? ids.map(id => ({type: 'territories', id})) : original(path, type);
    await assert.rejects(prepareDistribution({...client, mode: 'prepare'}));
    assert.ok(calls.every(item => item.method === 'GET'));
  }
  const {client, calls} = fixture({missing: true});
  const result = await prepareDistribution({...client, mode: 'prepare'});
  assert.equal(result.ready, true);
  const payload = calls.find(item => item.method === 'POST' && item.path === '/v2/appAvailabilities').body;
  assert.deepEqual(payload.included.map(item => [item.relationships.territory.data.id, item.attributes.available]),
    [['CAN', false], ['KOR', true], ['USA', false]]);
  assert.deepEqual(payload.data.relationships.territoryAvailabilities.data, payload.included.map(({type, id}) => ({type, id})));
});

test('existing automatic new territories remains explicit UI blocker; no speculative POST', async () => {
  const {client, calls} = fixture({ready: true, autoTerritories: true});
  const result = await prepareDistribution({...client, mode: 'prepare'});
  assert.equal(result.ready, false);
  assert.ok(result.blockers.includes('AUTOMATIC_NEW_TERRITORIES_REQUIRES_UI_OR_DOCUMENTED_UPDATE'));
  assert.ok(calls.every(item => item.method === 'GET'));
});

test('readback mismatch never claims successful age setup', async () => {
  const {client} = fixture({ready: true});
  const original = client.request;
  client.request = async (path, method, body) => {
    const result = await original(path, method, body);
    if (path === '/v1/appInfos/info1/ageRatingDeclaration') result.data.attributes.advertising = null;
    return result;
  };
  const result = await prepareDistribution({...client, mode: 'prepare'});
  assert.equal(result.ageRating.ready, false);
  assert.ok(result.blockers.includes('AGE_RATING_NOT_CONFIRMED'));
});

test('placeholder schedule manualPrices 404 is empty; other HTTP failures propagate before writes', async () => {
  const {client, calls} = fixture();
  const original = client.list;
  let missing = true;
  client.list = async (path, type) => {
    if (path.includes('/manualPrices?') && missing) {
      missing = false;
      throw Object.assign(new Error('Not found'), {status: 404});
    }
    return original(path, type);
  };
  assert.equal((await prepareDistribution({...client, mode: 'prepare'})).ready, true);
  assert.equal(calls.filter(item => item.path === '/v1/appPriceSchedules' && item.method === 'POST').length, 1);
  const second = fixture();
  const secondList = second.client.list;
  second.client.list = async (path, type) => {
    if (path.includes('/manualPrices?')) throw Object.assign(new Error('Forbidden'), {status: 403});
    return secondList(path, type);
  };
  await assert.rejects(prepareDistribution({...second.client, mode: 'prepare'}), /Forbidden/);
  assert.ok(second.calls.every(item => item.method === 'GET'));
});
