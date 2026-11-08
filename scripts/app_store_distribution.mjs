// App-specific, dependency-injected App Store distribution preparation. No auth,
// credentials, release, submission, or deletion operations live in this module.
export const CARCAR_APP_ID = '6829616379';
const bundleId = 'com.kang88.carcar';
const relation = (type, id) => ({data: {type, id}});
const requireValue = (ok, message) => { if (!ok) throw new Error(message); };
const resource = (value, type) => {
  requireValue(value?.type === type && typeof value.id === 'string'
    && value.id !== '.' && value.id !== '..'
    && /^[A-Za-z0-9._~=-]{1,512}$/.test(value.id), 'Invalid distribution resource.');
  return value;
};
const linked = (item, name, type) => {
  const value = item.relationships?.[name]?.data;
  return value == null ? null : resource(value, type).id;
};

// Closed, invited-family parking records are not content for broad distribution.
// This is not a Kids Category declaration; there is no chat, advertising, or
// unrestricted browser. Do not reuse this questionnaire for another product.
export const CARCAR_AGE_ATTRIBUTES = Object.freeze({
  advertising: false, parentalControls: false, ageAssurance: false,
  unrestrictedWebAccess: false, userGeneratedContent: false, socialMedia: false,
  socialMediaAgeRestricted: false, messagingAndChat: false,
  healthOrWellnessTopics: false, gambling: false, lootBox: false,
  alcoholTobaccoOrDrugUseOrReferences: 'NONE', contests: 'NONE',
  gamblingSimulated: 'NONE', gunsOrOtherWeapons: 'NONE',
  medicalOrTreatmentInformation: 'NONE', profanityOrCrudeHumor: 'NONE',
  sexualContentGraphicAndNudity: 'NONE', sexualContentOrNudity: 'NONE',
  horrorOrFearThemes: 'NONE', matureOrSuggestiveThemes: 'NONE',
  violenceCartoonOrFantasy: 'NONE', violenceRealisticProlongedGraphicOrSadistic: 'NONE',
  violenceRealistic: 'NONE', ageRatingOverrideV2: 'NONE', koreaAgeRatingOverride: 'NONE',
});

export function freeKoreaPricePayload(pricePointId) {
  resource({type: 'appPricePoints', id: pricePointId}, 'appPricePoints');
  return {data: {type: 'appPriceSchedules', relationships: {
    app: relation('apps', CARCAR_APP_ID), baseTerritory: relation('territories', 'KOR'),
    manualPrices: {data: [{type: 'appPrices', id: '${carcar-free-kor}'}]},
  }}, included: [{type: 'appPrices', id: '${carcar-free-kor}',
    attributes: {startDate: null, endDate: null},
    relationships: {appPricePoint: relation('appPricePoints', pricePointId)},
  }]};
}

export function koreaAvailabilityPayload(territoryIds) {
  requireValue(Array.isArray(territoryIds) && territoryIds.length > 0 && territoryIds.length <= 4000
    && territoryIds.every(id => typeof id === 'string' && /^[A-Z]{3}$/.test(id))
    && new Set(territoryIds).size === territoryIds.length && territoryIds.includes('KOR'),
  'Invalid or incomplete territory catalog.');
  const included = [...territoryIds].sort().map(territory => ({
    type: 'territoryAvailabilities', id: '${carcar-' + territory.toLowerCase() + '}',
    attributes: {available: territory === 'KOR', ...(territory === 'KOR' ? {preOrderEnabled: false} : {})},
    relationships: {territory: relation('territories', territory)},
  }));
  return {data: {type: 'appAvailabilities', attributes: {availableInNewTerritories: false},
    relationships: {app: relation('apps', CARCAR_APP_ID),
      territoryAvailabilities: {data: included.map(({type, id}) => ({type, id}))},
    }}, included};
}

/** request returns a JSON:API document; list(path,type) must follow same-origin
 * pagination with a finite page bound. Only this app's inspected relations are
 * used. The parent transport remains responsible for URL/auth/error redaction.
 */
export async function prepareDistribution({request, list, app, appInfoId, mode = 'inspect'}) {
  requireValue(['inspect', 'prepare'].includes(mode), 'Invalid distribution mode.');
  resource(app, 'apps');
  requireValue(app.id === CARCAR_APP_ID && app.attributes?.bundleId === bundleId,
    'Distribution is restricted to the carcar app.');
  requireValue(app.attributes.isOrEverWasMadeForKids !== true, 'Unexpected Kids Category app.');
  resource({type: 'appInfos', id: appInfoId}, 'appInfos');
  const writes = [], blockers = [];
  async function items(path, type) {
    const values = await list(path, type);
    requireValue(Array.isArray(values) && values.length <= 4000, 'Invalid or excessive distribution list.');
    const seen = new Set();
    for (const value of values) {
      resource(value, type);
      requireValue(!seen.has(value.id), 'Duplicate distribution resource.');
      seen.add(value.id);
    }
    return values;
  }
  async function optional(path, type) {
    try {
      const result = (await request(path)).data;
      return result == null ? null : resource(result, type);
    } catch (error) {
      if ((error.status ?? error.diagnostic?.status) === 404) return null;
      throw error;
    }
  }
  async function write(path, method, body) {
    requireValue(mode === 'prepare', 'Distribution writes are disabled.');
    const result = await request(path, method, body);
    writes.push({method, path});
    return result;
  }
  const infos = await items(`/v1/apps/${CARCAR_APP_ID}/appInfos?limit=200`, 'appInfos');
  const info = infos.find(value => value.id === appInfoId);
  const allowedInfoStates = mode === 'inspect' ? ['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'] : ['PREPARE_FOR_SUBMISSION'];
  requireValue(info && allowedInfoStates.includes(info.attributes?.state ?? info.attributes?.appStoreState),
    'App information does not belong to this editable app.');
  const agePath = `/v1/appInfos/${appInfoId}/ageRatingDeclaration`;
  const schedulePath = `/v1/apps/${CARCAR_APP_ID}/appPriceSchedule?include=baseTerritory`;
  const availabilityPath = `/v1/apps/${CARCAR_APP_ID}/appAvailabilityV2`;
  let age = await optional(agePath, 'ageRatingDeclarations');
  requireValue(age?.attributes?.kidsAgeBand == null, 'Unexpected Kids Category age band.');
  let schedule = await optional(schedulePath, 'appPriceSchedules');
  if (schedule && linked(schedule, 'app', 'apps') != null) {
    requireValue(linked(schedule, 'app', 'apps') === CARCAR_APP_ID, 'Wrong app price schedule.');
  }
  const points = await items(`/v1/apps/${CARCAR_APP_ID}/appPricePoints?filter[territory]=KOR&include=app,territory&limit=200`, 'appPricePoints');
  for (const point of points) {
    requireValue(linked(point, 'app', 'apps') === CARCAR_APP_ID
      && linked(point, 'territory', 'territories') === 'KOR', 'Wrong app or territory price point.');
  }
  const freePoints = points.filter(value => typeof value.attributes?.customerPrice === 'string'
    && /^0(?:\.0+)?$/.test(value.attributes.customerPrice));
  requireValue(freePoints.length === 1, 'Expected exactly one free Korean price point.');
  const freePoint = freePoints[0];
  async function readManualPrices(value) {
    if (!value) return [];
    let values;
    try {
      values = await items(`/v1/appPriceSchedules/${value.id}/manualPrices?filter[territory]=KOR&include=appPricePoint,territory&limit=200`, 'appPrices');
    } catch (error) {
      // Apple returns an app-id placeholder schedule before its first price.
      // The child manualPrices relation then returns 404, not an empty list.
      if ((error.status ?? error.diagnostic?.status) === 404) return [];
      throw error;
    }
    requireValue(values.every(price => linked(price, 'territory', 'territories') === 'KOR'), 'Unexpected manual price territory.');
    return values;
  }
  let prices = await readManualPrices(schedule);
  function freePricing() {
    return schedule && linked(schedule, 'baseTerritory', 'territories') === 'KOR'
      && prices.length === 1 && linked(prices[0], 'territory', 'territories') === 'KOR'
      && linked(prices[0], 'appPricePoint', 'appPricePoints') === freePoint.id
      && (prices[0].attributes?.startDate == null
        || (/^\d{4}-\d{2}-\d{2}$/.test(prices[0].attributes.startDate)
          && prices[0].attributes.startDate <= new Date().toISOString().slice(0, 10)))
      && prices[0].attributes?.endDate == null;
  }
  let availability = await optional(availabilityPath, 'appAvailabilities');
  async function readTerritories(value) {
    const values = value ? await items(`/v2/appAvailabilities/${value.id}/territoryAvailabilities?include=territory&limit=200`, 'territoryAvailabilities') : [];
    const seen = new Set();
    for (const item of values) {
      const territory = linked(item, 'territory', 'territories');
      requireValue(typeof territory === 'string' && /^[A-Z]{3}$/.test(territory)
        && !seen.has(territory) && typeof item.attributes?.available === 'boolean', 'Invalid territory availability.');
      seen.add(territory);
    }
    return values;
  }
  let territories = await readTerritories(availability);
  // Initial availability requires every current territory, including unavailable
  // ones. Read Apple's paginated catalog instead of omitting other countries.
  // Primary implementation evidence: App-Store-Connect-CLI
  // internal/cli/pricing/availability_create.go (initialTerritoryAvailabilities).
  const initialAvailability = !availability && mode === 'prepare'
    ? koreaAvailabilityPayload((await items('/v1/territories?limit=200', 'territories')).map(item => item.id)) : null;
  // All app/identity/schema checks above finish before any changes.
  if (mode === 'prepare') {
    if (age) {
      const changes = Object.fromEntries(Object.entries(CARCAR_AGE_ATTRIBUTES)
        .filter(([key, value]) => age.attributes?.[key] !== value));
      if (Object.keys(changes).length) {
        await write(`/v1/ageRatingDeclarations/${age.id}`, 'PATCH', {data: {
          type: 'ageRatingDeclarations', id: age.id, attributes: changes,
        }});
        age = await optional(agePath, 'ageRatingDeclarations');
      }
    }
    if (!freePricing()) {
      await write('/v1/appPriceSchedules', 'POST', freeKoreaPricePayload(freePoint.id));
      schedule = await optional(schedulePath, 'appPriceSchedules');
      prices = await readManualPrices(schedule);
    }
    if (!availability) {
      await write('/v2/appAvailabilities', 'POST', initialAvailability);
      availability = await optional(availabilityPath, 'appAvailabilities');
      territories = await readTerritories(availability);
    }
    for (const territory of territories) {
      const available = linked(territory, 'territory', 'territories') === 'KOR';
      const changes = {};
      if (territory.attributes.available !== available) changes.available = available;
      if (available && territory.attributes.preOrderEnabled === true) changes.preOrderEnabled = false;
      if (Object.keys(changes).length) await write(`/v1/territoryAvailabilities/${territory.id}`, 'PATCH', {
        data: {type: 'territoryAvailabilities', id: territory.id, attributes: changes},
      });
    }
    if (writes.some(item => item.path.startsWith('/v1/territoryAvailabilities/'))) {
      territories = await readTerritories(availability);
    }
  }
  const ageReady = Boolean(age && Object.entries(CARCAR_AGE_ATTRIBUTES).every(([key, value]) => age.attributes?.[key] === value));
  const pricingReady = Boolean(freePricing());
  const korea = territories.find(item => linked(item, 'territory', 'territories') === 'KOR');
  const availabilityReady = Boolean(availability?.attributes?.availableInNewTerritories === false
    && korea?.attributes?.available === true && korea.attributes.preOrderEnabled !== true
    && territories.every(item => linked(item, 'territory', 'territories') === 'KOR' || item.attributes.available === false));
  if (!ageReady) blockers.push('AGE_RATING_NOT_CONFIRMED');
  if (!pricingReady) blockers.push('KOREA_FREE_PRICE_NOT_CONFIRMED');
  if (!availabilityReady) blockers.push('KOREA_ONLY_AVAILABILITY_NOT_CONFIRMED');
  if (availability?.attributes?.availableInNewTerritories !== false) {
    blockers.push('AUTOMATIC_NEW_TERRITORIES_REQUIRES_UI_OR_DOCUMENTED_UPDATE');
  }
  return {mode, appId: CARCAR_APP_ID, ageRating: {ready: ageReady, id: age?.id ?? null},
    pricing: {ready: pricingReady, baseTerritory: schedule ? linked(schedule, 'baseTerritory', 'territories') : null, price: pricingReady ? 0 : null},
    availability: {ready: availabilityReady,
      availableInNewTerritories: availability?.attributes?.availableInNewTerritories ?? null,
      territories: territories.filter(item => item.attributes.available).map(item => linked(item, 'territory', 'territories'))},
    writes, blockers, ready: ageReady && pricingReady && availabilityReady};
}
