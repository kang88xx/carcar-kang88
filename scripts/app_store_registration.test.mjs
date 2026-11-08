import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, createHash} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, readFile, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {registerApp, validateTarget, safeApiUrl, safeUploadUrl, uploadParts, loadMedia, APP_ID, parseReviewContact, apiDiagnostics, redactProviderDiagnostic, RegistrationError} from './app_store_registration.mjs';

const {privateKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const env = {APP_STORE_CONNECT_KEY_ID: 'ABCDEFGHIJ', APP_STORE_CONNECT_ISSUER_ID: '00000000-0000-0000-0000-000000000001',
  APP_STORE_CONNECT_API_KEY_P8_BASE64: Buffer.from(privateKey.export({type: 'pkcs8', format: 'pem'})).toString('base64')};
const obj = (type, id, attributes = {}, relationships = {}) => ({type, id, attributes, relationships});
const app = obj('apps', APP_ID, {bundleId: 'com.kang88.carcar', name: '차자리 - 가족 주차 기록', primaryLocale: 'ko'});
const parent = {app: {data: {type: 'apps', id: APP_ID}}};
const version = obj('appStoreVersions', 'version', {platform: 'IOS', versionString: '1.0', appVersionState: 'PREPARE_FOR_SUBMISSION', releaseType: 'MANUAL'}, parent);
const build = obj('builds', 'build', {version: '13', processingState: 'VALID', expired: false});
const prerelease = obj('preReleaseVersions', 'pre', {version: '1.0.0', platform: 'IOS'});
function fixture(overrides = {}) {
  const calls = [];
  const routes = {
    ['/v1/apps/' + APP_ID]: app,
    ['/v1/apps/' + APP_ID + '/appInfos']: [obj('appInfos', 'info', {state: 'PREPARE_FOR_SUBMISSION'}, parent)],
    ['/v1/apps/' + APP_ID + '/appStoreVersions']: [version],
    '/v1/builds': [build], '/v1/builds/build/app': app, '/v1/builds/build/preReleaseVersion': prerelease,
    '/v1/appInfos/info/appInfoLocalizations': [obj('appInfoLocalizations', 'il', {locale: 'ko', name: app.attributes.name})],
    '/v1/appStoreVersions/version/appStoreVersionLocalizations': [obj('appStoreVersionLocalizations', 'vl', {locale: 'ko'})],
    '/v1/appInfos/info/ageRatingDeclaration': obj('ageRatingDeclarations', 'age', {}),
    '/v1/appStoreVersions/version/appStoreReviewDetail': obj('appStoreReviewDetails', 'review', {contactFirstName: 'PRIVATE-FIRST', contactEmail: 'private@example.invalid', demoAccountPassword: 'DO-NOT-LOG'}),
    ['/v1/apps/' + APP_ID + '/betaAppReviewDetail']: obj('betaAppReviewDetails', 'beta', {contactPhone: 'PRIVATE-PHONE', demoAccountPassword: 'DO-NOT-LOG'}),
    ['/v1/apps/' + APP_ID + '/appPriceSchedule']: null,
    ['/v1/apps/' + APP_ID + '/appAvailabilityV2']: null,
    '/v1/appStoreVersionLocalizations/vl/appScreenshotSets': [], ...overrides,
  };
  return {calls, fetch: async (url, options) => {
    calls.push({url: String(url), ...options});
    const path = new URL(url).pathname;
    assert.ok(path in routes, 'Unexpected fixture request: ' + path);
    return new Response(JSON.stringify({data: routes[path]}), {status: routes[path] === null ? 404 : 200});
  }};
}
test('default inspect performs only GET and never emits contacts or credentials', async () => {
  const f = fixture(); const result = await registerApp(env, f.fetch);
  assert.equal(result.mode, 'inspect'); assert.equal(result.submitted, false); assert.deepEqual(result.writes, []);
  assert.ok(f.calls.length > 10 && f.calls.every(c => c.method === 'GET'));
  assert.ok(!/PRIVATE|DO-NOT-LOG|private@example/.test(JSON.stringify(result)));
  assert.ok(f.calls.every(c => c.redirect === 'error' && c.headers.Authorization.startsWith('Bearer ')));
});
test('private contact report is permission-restricted and excludes demo credentials', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'asc-private-'));
  try {
    const path = join(dir, 'private.json'); const f = fixture();
    await registerApp({...env, APP_STORE_REGISTRATION_PRIVATE_PATH: path}, f.fetch);
    const content = await readFile(path, 'utf8');
    assert.ok(content.includes('PRIVATE-FIRST')); assert.ok(!content.includes('DO-NOT-LOG'));
    assert.equal((await stat(path)).mode & 0o777, 0o600);
  } finally { await rm(dir, {recursive: true, force: true}); }
});
test('wrong app rejected before any related query or write', async () => {
  const f = fixture({['/v1/apps/' + APP_ID]: obj('apps', APP_ID, {bundleId: 'wrong.app'})});
  await assert.rejects(registerApp({...env, APP_STORE_REGISTRATION_MODE: 'prepare'}, f.fetch), /Unexpected app identity/);
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].method, 'GET');
});
test('invalid build and wrong association fail before any write', async () => {
  for (const changed of [{...build, attributes: {...build.attributes, processingState: 'INVALID'}}, {...build, attributes: {...build.attributes, expired: true}}]) {
    const f = fixture({'/v1/builds': [changed]});
    await assert.rejects(registerApp({...env, APP_STORE_REGISTRATION_MODE: 'prepare'}, f.fetch), /Only valid/);
    assert.ok(f.calls.every(c => c.method === 'GET'));
  }
  assert.throws(() => validateTarget(app, {...version, relationships: {app: {data: {type: 'apps', id: 'other'}}}}, build, app, prerelease), /unexpected parent/);
  assert.throws(() => validateTarget(app, version, build, obj('apps', 'other', app.attributes), prerelease), /identity/);
});
test('unrecognized mode cannot submit or write', async () => {
  await assert.rejects(registerApp({...env, APP_STORE_REGISTRATION_MODE: 'submit'}, () => assert.fail('network called')), /Mode must/);
});
test('API and upload destinations reject credential leaks and host lookalikes', () => {
  for (const url of ['https://evil.invalid/v1/apps/x', 'https://api.appstoreconnect.apple.com.evil.invalid/v1/apps/x', 'https://user@api.appstoreconnect.apple.com/v1/apps/x']) assert.throws(() => safeApiUrl(url));
  for (const url of ['http://store-030.blobstore.apple.com/a', 'https://store-030.blobstore.apple.com.evil.invalid/a', 'https://api.appstoreconnect.apple.com/a', 'https://store-030.blobstore.apple.com:444/a']) assert.throws(() => safeUploadUrl(url));
});
test('binary upload sends exact ranges with no JWT or inherited API headers', async () => {
  const bytes = Buffer.from('screenshot-bytes'); const calls = [];
  const operations = [{method: 'PUT', url: 'https://store-030.blobstore.apple.com/asset?signature=private', offset: 0, length: 4, requestHeaders: [{name: 'Content-Type', value: 'image/jpeg'}]},
    {method: 'PUT', url: 'https://store-030.blobstore.apple.com/asset?signature=private2', offset: 4, length: bytes.length - 4}];
  await uploadParts(operations, bytes, async (url, options) => {calls.push(options); return new Response('', {status: 200});});
  assert.deepEqual(Buffer.concat(calls.map(c => c.body)), bytes);
  assert.ok(calls.every(c => !Object.keys(c.headers).some(k => /authorization|cookie/i.test(k)) && c.redirect === 'error'));
  await assert.rejects(uploadParts([{...operations[0], length: bytes.length, requestHeaders: [{name: 'Authorization', value: 'Bearer secret'}]}], bytes, () => assert.fail('network called')), /header/);
});
test('upload plan validates all hosts and byte coverage before sending any bytes', async () => {
  const bytes = Buffer.from('1234');
  for (const operations of [
    [{method: 'PUT', url: 'https://store-030.blobstore.apple.com/a', offset: 0, length: 3}],
    [{method: 'PUT', url: 'https://store-030.blobstore.apple.com/a', offset: 0, length: 2}, {method: 'PUT', url: 'https://evil.invalid/a', offset: 2, length: 2}],
  ]) await assert.rejects(uploadParts(operations, bytes, () => assert.fail('network called')));
});
test('local screenshot bytes must match the approved manifest and device dimensions', async () => {
  const root = await mkdtemp(join(tmpdir(), 'asc-media-'));
  try {
    const manifest = {sourceCommit: '069dd4ccb49add356706f909335f938994c2076b', productSourceMatchesTestFlight13: true, testFlightBuild: '1.0.0 (13)', dataSource: 'built-in local demo', devices: []};
    for (const [family, width, height] of [['iphone',1320,2868], ['ipad',2064,2752]]) {
      await mkdir(join(root, family)); const screenshots = [];
      for (const name of ['01-home.jpg','02-parking-entry.jpg','03-family.jpg','04-history.jpg']) {
        const data = Buffer.from([255,216,255,192,0,11,8,height>>8,height&255,width>>8,width&255,1,1,17,0,255,217]);
        await writeFile(join(root, family, name), data);
        screenshots.push({file:name,width,height,hasAlpha:false,sha256:createHash('sha256').update(data).digest('hex')});
      }
      manifest.devices.push({deviceFamily:family,screenshots});
    }
    await writeFile(join(root,'manifest.json'),JSON.stringify(manifest));
    assert.equal((await loadMedia(root)).length,8);
    await writeFile(join(root,'iphone','01-home.jpg'),Buffer.from('tampered'));
    await assert.rejects(loadMedia(root), /integrity/);
  } finally { await rm(root,{recursive:true,force:true}); }
});

async function mediaFixture(root) {
  const manifest = {sourceCommit: '069dd4ccb49add356706f909335f938994c2076b', productSourceMatchesTestFlight13: true,
    testFlightBuild: '1.0.0 (13)', dataSource: 'built-in local demo', devices: []};
  for (const [family, width, height] of [['iphone',1320,2868], ['ipad',2064,2752]]) {
    await mkdir(join(root, family)); const screenshots = [];
    for (const name of ['01-home.jpg','02-parking-entry.jpg','03-family.jpg','04-history.jpg']) {
      const bytes = Buffer.from([255,216,255,192,0,11,8,height>>8,height&255,width>>8,width&255,1,1,17,0,255,217]);
      await writeFile(join(root, family, name), bytes);
      screenshots.push({file: name, width, height, hasAlpha: false, sha256: createHash('sha256').update(bytes).digest('hex')});
    }
    manifest.devices.push({deviceFamily: family, screenshots});
  }
  await writeFile(join(root, 'manifest.json'), JSON.stringify(manifest));
}
function mutableFixture() {
  const initial = fixture(); const records = new Map(), calls = [], uploadBytes = new Map(); let sequence = 0;
  // Clone fixtures so this test cannot mutate other tests' constants.
  for (const r of [app,version,build,obj('appInfos','info',{state:'PREPARE_FOR_SUBMISSION'},parent),
    obj('appStoreReviewDetails','review',{contactFirstName:'OLD-FIRST',demoAccountPassword:'UNCHANGED-PASSWORD'}, {appStoreVersion:{data:{type:'appStoreVersions',id:'version'}}}),
    obj('appInfoLocalizations','il',{locale:'ko',name:app.attributes.name}), obj('appStoreVersionLocalizations','vl',{locale:'ko'})])
    records.set('/v1/' + r.type + '/' + r.id, structuredClone(r));
  return {calls, records, fetch: async (url, options) => {
    calls.push({url: String(url), ...options}); const u = new URL(url), path = u.pathname;
    const response = data => new Response(JSON.stringify({data}),{status:200});
    if (u.hostname === 'store-030.blobstore.apple.com') {
      assert.equal(options.headers.Authorization, undefined); uploadBytes.set(path.slice(1), Buffer.from(options.body));
      return new Response('',{status:200});
    }
    if (options.method === 'DELETE') {assert.ok(/^\/v1\/appScreenshots\/[^/]+$/.test(path));records.delete(path);return new Response(null,{status:204});}
    if (options.method === 'POST') {
      const data = JSON.parse(options.body).data, id = 'new-' + (++sequence), r = {...data,id};
      if (r.type === 'appScreenshots') {r.attributes.assetDeliveryState={state:'AWAITING_UPLOAD'};r.attributes.sourceFileChecksum=null;}
      if (r.type === 'appScreenshots') r.attributes.uploadOperations = [{method:'PUT',url:'https://store-030.blobstore.apple.com/'+id,offset:0,length:r.attributes.fileSize}];
      records.set('/v1/'+r.type+'/'+id,r); return response(r);
    }
    if (options.method === 'PATCH') {
      const r = records.get(path); assert.ok(r); const data=JSON.parse(options.body).data;
      Object.assign(r.attributes,data.attributes); Object.assign(r.relationships,data.relationships);
      if (r.type === 'appScreenshots') {
        assert.equal(createHash('md5').update(uploadBytes.get(r.id)).digest('hex'),r.attributes.sourceFileChecksum);
        r.attributes.assetDeliveryState={state:'COMPLETE'};
      }
      return response(r);
    }
    if (path.includes('/relationships/')) {
      assert.ok(['/v1/appInfos/info/relationships/primaryCategory','/v1/appStoreVersions/version/relationships/build'].includes(path), 'Undocumented relationship endpoint');
      const [base,relationship]=path.split('/relationships/'); return response(records.get(base).relationships[relationship].data);
    }
    if (path === '/v1/appStoreVersionLocalizations/vl/appScreenshotSets') return response([...records.values()].filter(r=>r.type==='appScreenshotSets'));
    if (/^\/v1\/appScreenshotSets\/[^/]+\/appScreenshots$/.test(path)) return response([...records.values()].filter(r=>r.type==='appScreenshots' && r.relationships.appScreenshotSet.data.id===path.split('/')[3]));
    if (path === '/v1/appStoreVersions/version/appStoreReviewDetail') {
      const detail=[...records.values()].find(r=>r.type==='appStoreReviewDetails');
      return detail ? response(detail) : new Response(JSON.stringify({data:null}),{status:404});
    }
    if (records.has(path)) return response(records.get(path));
    if (path === '/v1/apps/'+APP_ID+'/appStoreVersions') return response([records.get('/v1/appStoreVersions/version')]);
    if (path === '/v1/apps/'+APP_ID+'/appInfos') return response([records.get('/v1/appInfos/info')]);
    if (path === '/v1/appInfos/info/appInfoLocalizations') return response([records.get('/v1/appInfoLocalizations/il')]);
    if (path === '/v1/appStoreVersions/version/appStoreVersionLocalizations') return response([records.get('/v1/appStoreVersionLocalizations/vl')]);
    return initial.fetch(url,options);
  }};
}
test('prepare writes only bounded metadata, build and eight exact screenshots; second run reuses complete media', async () => {
  const root = await mkdtemp(join(tmpdir(),'asc-prepare-'));
  try {
    await mediaFixture(root); const f=mutableFixture();
    const config={...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_RELEASE_TYPE:'KEEP',APP_STORE_MEDIA_ROOT:root};
    const result=await registerApp(config,f.fetch,{sleep:async()=>{},distribution:async ({mode,appInfoId})=>{assert.equal(mode,'prepare');assert.equal(appInfoId,'info');return {ready:true,ageRating:{ready:true},pricing:{ready:true},availability:{ready:true},blockers:[]};}});
    assert.equal(result.prepared,true); assert.equal(result.preparedScreenshots.length,8);
    assert.equal(f.records.get('/v1/appStoreVersions/version').attributes.releaseType,'MANUAL');
    assert.equal(f.records.get('/v1/appStoreVersions/version').relationships.build.data.id,'build');
    assert.ok(f.calls.filter(c=>c.method!=='GET').every(c=>! /submission|reviewSubmission|DELETE/.test(c.url)));
    const count=f.calls.length;
    const repeat=await registerApp(config,f.fetch,{sleep:async()=>{},distribution:async ({mode,appInfoId})=>{assert.equal(mode,'prepare');assert.equal(appInfoId,'info');return {ready:true,ageRating:{ready:true},pricing:{ready:true},availability:{ready:true},blockers:[]};}});
    assert.equal(repeat.preparedScreenshots.filter(s=>s.reused).length,8);
    assert.ok(f.calls.slice(count).every(c=>c.method==='GET'),'idempotent repeat should not write');
  } finally {await rm(root,{recursive:true,force:true});}
});
test('unknown existing screenshot blocks preparation before metadata writes', async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-unknown-'));
  try {
    await mediaFixture(root);const f=mutableFixture();
    f.records.set('/v1/appScreenshotSets/unknown',obj('appScreenshotSets','unknown',{screenshotDisplayType:'APP_IPHONE_67'},{appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:'vl'}}}));
    f.records.set('/v1/appScreenshots/unknown',obj('appScreenshots','unknown',{fileName:'unrelated.jpg'},{appScreenshotSet:{data:{type:'appScreenshotSets',id:'unknown'}}}));
    await assert.rejects(registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root},f.fetch),/order|unknown/);
    assert.ok(f.calls.every(c=>c.method==='GET'));
  }finally{await rm(root,{recursive:true,force:true});}
});
test('placeholder price schedule with 404 manualPrices preserves core inspection facts',async()=>{
  const f=fixture({['/v1/apps/'+APP_ID+'/appPriceSchedule']:obj('appPriceSchedules',APP_ID),
    ['/v1/appPriceSchedules/'+APP_ID+'/manualPrices']:null});
  const summary=await registerApp(env,f.fetch);
  assert.equal(summary.version.id,'version');assert.equal(summary.build.id,'build');
  assert.equal(summary.infoLocalizations[0].locale,'ko');assert.deepEqual(summary.price.manualPrices,[]);
  assert.ok(summary.blockers.some(b=>b.includes('HTTP 404')));
  assert.ok(f.calls.every(c=>c.method==='GET'));
});
test('opaque Apple resource IDs remain valid safe segments without widening hosts',async()=>{
  const id='opaque_price.point~=';
  const f=fixture({['/v1/apps/'+APP_ID+'/appPriceSchedule']:obj('appPriceSchedules',id),
    ['/v1/appPriceSchedules/'+id+'/manualPrices']:[]});
  const summary=await registerApp(env,f.fetch);
  assert.equal(summary.price.present,true);
  assert.ok(f.calls.some(c=>new URL(c.url).pathname.includes(id)));
  assert.throws(()=>validateTarget(app,{...version,id:'..'},build,app,prerelease),/identity/);
});
const contact = {contactFirstName:'Review',contactLastName:'Tester',contactPhone:'+82 10 0000 0000',contactEmail:'review@example.invalid'};
const distributionReady = async()=>({ready:true,ageRating:{ready:true},pricing:{ready:true},availability:{ready:true},blockers:[]});
test('contact input is validated before any network call and rejects credential fields',async()=>{
  for(const value of ['{bad',JSON.stringify({...contact,demoAccountPassword:'SECRET'}),JSON.stringify({...contact,contactEmail:'bad'}),JSON.stringify({...contact,contactPhone:'bad'})]) {
    await assert.rejects(registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_REVIEW_CONTACT_JSON:value},()=>assert.fail('network called')),/contact/);
  }
  assert.deepEqual(parseReviewContact(JSON.stringify(contact)),contact);
});
test('review contact create and patch are bound to the existing version and never expose or clear credentials',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-contact-'));
  try {
    await mediaFixture(root);
    for(const create of [false,true]) {
      const f=mutableFixture();if(create)f.records.delete('/v1/appStoreReviewDetails/review');
      const result=await registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root,
        APP_STORE_REVIEW_CONTACT_JSON:JSON.stringify(contact),APP_STORE_RELEASE_TYPE:'AFTER_APPROVAL'},f.fetch,{sleep:async()=>{},distribution:distributionReady});
      const detail=[...f.records.values()].find(r=>r.type==='appStoreReviewDetails');
      for(const [k,v] of Object.entries(contact))assert.equal(detail.attributes[k],v);
      assert.equal(detail.attributes.demoAccountRequired,false);
      assert.ok(detail.attributes.notes.includes('Apple'));
      if(!create)assert.equal(detail.attributes.demoAccountPassword,'UNCHANGED-PASSWORD');
      assert.equal(result.review.suppliedContactVerified,true);
      assert.equal(f.records.get('/v1/appStoreVersions/version').attributes.releaseType,'AFTER_APPROVAL');
      assert.ok(!JSON.stringify(result).includes(contact.contactEmail));
      assert.ok(!JSON.stringify(result).includes('UNCHANGED-PASSWORD'));
      const reviewWrites=f.calls.filter(c=>c.method!=='GET'&&new URL(c.url).pathname.startsWith('/v1/appStoreReviewDetails'));
      assert.equal(reviewWrites.length,1);
      const payload=JSON.parse(reviewWrites[0].body);
      assert.ok(!('demoAccountPassword' in payload.data.attributes)&&!('demoAccountName' in payload.data.attributes));
      if(create)assert.equal(payload.data.relationships.appStoreVersion.data.id,'version');
    }
  }finally{await rm(root,{recursive:true,force:true});}
});
test('API diagnostics keep known codes and field pointers but discard private provider text',async()=>{
  const result=await apiDiagnostics(new Response(JSON.stringify({errors:[
    {code:'ENTITY_ERROR.ATTRIBUTE.INVALID',detail:'SECRET-CONTACT',title:'SECRET-TITLE',source:{pointer:'/data/attributes/contactEmail'}},
    {code:'SECRET-TOKEN',source:{pointer:'/data/attributes/SECRET-NAME'}},
  ]}),{status:409}));
  assert.deepEqual(result,{status:409,codes:['ENTITY_ERROR.ATTRIBUTE.INVALID'],pointers:['/data/attributes/contactEmail']});
  assert.ok(!JSON.stringify(result).includes('SECRET'));
});
test('bounded content-rights readback mismatch remains explicit while independent preparation continues',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-readback-'));
  try{
    await mediaFixture(root);const f=mutableFixture();let readsAfterWrite=0,rightsWritten=false;
    const transport=async(url,options)=>{
      const path=new URL(url).pathname;
      if(path==='/v1/apps/'+APP_ID && options.method==='PATCH')rightsWritten=true;
      const response=await f.fetch(url,options);
      if(path==='/v1/apps/'+APP_ID && options.method==='GET' && rightsWritten){readsAfterWrite++;const doc=await response.json();doc.data.attributes.contentRightsDeclaration=null;return new Response(JSON.stringify(doc));}
      return response;
    };
    const result=await registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root},transport,{sleep:async()=>{},distribution:distributionReady});
    assert.equal(readsAfterWrite,3);assert.equal(result.preparedScreenshots.length,8);
    assert.ok(result.blockers.some(b=>b.includes('contentRightsDeclaration')));
    assert.equal(result.app.contentRightsDeclaration,null);
    assert.ok(result.updates.some(u=>u.type==='appStoreVersionLocalizations'&&u.verified));
  }finally{await rm(root,{recursive:true,force:true});}
});
test('unsupported upload preserves safe pending progress and resumes the same empty reservation',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-resume-'));
  try{
    await mediaFixture(root);const f=mutableFixture();let rejectHost=true,distributionCalls=0;
    const report=join(root,'private-report.json');
    const transport=async(url,options)=>{
      const response=await f.fetch(url,options);
      if(rejectHost && ((options.method==='GET' && /^\/v1\/appScreenshots\/[^/]+$/.test(new URL(url).pathname)) || (options.method==='POST' && new URL(url).pathname==='/v1/appScreenshots'))){
        const doc=await response.json();doc.data.attributes.uploadOperations[0].url='https://unverified.example.invalid/PRIVATE-PATH?secret=DO-NOT-LOG';
        return new Response(JSON.stringify(doc));
      }
      return response;
    };
    const config={...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root,APP_STORE_REGISTRATION_SUMMARY_PATH:report};
    const options={sleep:async()=>{},distribution:async()=>{distributionCalls++;return distributionReady();}};
    await assert.rejects(registerApp(config,transport,options),error=>error.message.includes('unverified.example.invalid')&&!/PRIVATE-PATH|DO-NOT-LOG/.test(error.message));
    assert.equal(distributionCalls,1);
    const saved=JSON.parse(await readFile(report,'utf8'));
    assert.equal(saved.pendingScreenshots.length,1);
    assert.deepEqual(saved.pendingScreenshots[0].uploadHosts,['unverified.example.invalid']);
    assert.ok(!/PRIVATE-PATH|DO-NOT-LOG/.test(JSON.stringify(saved)));
    const pendingId=saved.pendingScreenshots[0].id;
    rejectHost=false;
    const result=await registerApp(config,transport,options);
    assert.equal(result.preparedScreenshots.length,8);
    assert.equal(result.preparedScreenshots[0].id,pendingId);
    assert.equal(result.preparedScreenshots[0].resumed,true);
    assert.equal(f.calls.filter(c=>c.method==='POST'&&new URL(c.url).pathname==='/v1/appScreenshots').length,8);
  }finally{await rm(root,{recursive:true,force:true});}
});
test('COMPLETE checksum mismatch cannot be resumed or replaced',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-complete-mismatch-'));
  try{
    await mediaFixture(root);const f=mutableFixture();
    const config={...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root};
    await registerApp(config,f.fetch,{sleep:async()=>{},distribution:distributionReady});
    const screenshot=[...f.records.values()].find(r=>r.type==='appScreenshots');screenshot.attributes.sourceFileChecksum='wrong';
    const count=f.calls.length;
    await assert.rejects(registerApp(config,f.fetch,{sleep:async()=>{},distribution:distributionReady}),/mismatched/);
    assert.ok(f.calls.slice(count).every(c=>c.method==='GET'));
  }finally{await rm(root,{recursive:true,force:true});}
});
test('distribution HTTP failure preserves private redacted diagnostics and continues screenshots without claiming ready',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-partial-'));
  try {
    await mediaFixture(root);const f=mutableFixture();const privatePath=join(root,'private','contact.json');
    const transport=async(url,options)=>new URL(url).pathname==='/v2/appAvailabilities'
      ? new Response(JSON.stringify({errors:[{code:'ENTITY_ERROR.RELATIONSHIP.INVALID',title:'Invalid relation',
        detail:'Existing availability invalid. email@example.invalid +82 10 1234 5678 Bearer SECRET https://host.invalid/path?token=SECRET'}]}),{status:409})
      : f.fetch(url,options);
    const result=await registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root,
      APP_STORE_REGISTRATION_PRIVATE_PATH:privatePath},transport,{sleep:async()=>{},distribution:async({request})=>{
        await request('/v2/appAvailabilities','POST',{data:{type:'appAvailabilities'}});
      }});
    assert.equal(result.prepared,false);assert.equal(result.distribution.ready,false);
    assert.equal(result.screenshotsPrepared,true);assert.equal(result.preparedScreenshots.length,8);
    assert.equal(result.distribution.diagnostic.status,409);
    const text=await readFile(privatePath+'.diagnostics.json','utf8');
    assert.ok(text.includes('Existing availability invalid'));
    assert.ok(!/email@example|1234|SECRET|host.invalid/.test(text));
    assert.ok(!JSON.stringify(result).includes('Existing availability invalid'));
    assert.equal((await stat(privatePath+'.diagnostics.json')).mode&0o777,0o600);
  } finally {await rm(root,{recursive:true,force:true});}
});
test('diagnostic redaction removes supplied contacts and JWT values',()=>{
  const jwt='eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ4In0.signature';
  const text=redactProviderDiagnostic(`Review Tester review@example.invalid ${jwt}`,{APP_STORE_REVIEW_CONTACT_JSON:JSON.stringify(contact)});
  assert.ok(!/Review|Tester|review@example|eyJ/.test(text));
});

test('Apple blobstore DNS domain allows documented subdomains but rejects lookalikes and unsafe URLs',()=>{
  for(const host of ['blobstore.apple.com','upload-east.blobstore.apple.com','region.upload.blobstore.apple.com'])
    assert.equal(safeUploadUrl('https://'+host+'/signed?secret=private').hostname,host);
  for(const url of ['https://blobstore.apple.com.evil.invalid/a','https://evilblobstore.apple.com/a',
    'https://-invalid.blobstore.apple.com/a','https://invalid-.blobstore.apple.com/a',
    'http://upload.blobstore.apple.com/a','https://upload.blobstore.apple.com:444/a',
    'https://user:password@upload.blobstore.apple.com/a'])assert.throws(()=>safeUploadUrl(url));
});
test('initial app information includes primary category for idempotent preparation',async()=>{
  const f=fixture();await registerApp(env,f.fetch);
  const infoCall=f.calls.find(c=>new URL(c.url).pathname==='/v1/apps/'+APP_ID+'/appInfos');
  assert.equal(new URL(infoCall.url).searchParams.get('include'),'app,primaryCategory');
});
test('new reservations use POST operations when GET omits them; only known empty reservation can be recreated',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-post-operations-'));
  try {
    await mediaFixture(root);
    for(const preexisting of [false,true]) {
      const f=mutableFixture();
      if(preexisting){
        const bytes=await readFile(join(root,'iphone','01-home.jpg'));
        f.records.set('/v1/appScreenshotSets/old-set',obj('appScreenshotSets','old-set',{screenshotDisplayType:'APP_IPHONE_67'},{appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:'vl'}}}));
        f.records.set('/v1/appScreenshots/34000019-713a-8cfb-8037-5f8c33da22ed',obj('appScreenshots','34000019-713a-8cfb-8037-5f8c33da22ed',{fileName:'01-home.jpg',fileSize:bytes.length,sourceFileChecksum:null,assetDeliveryState:{state:'AWAITING_UPLOAD'}},{appScreenshotSet:{data:{type:'appScreenshotSets',id:'old-set'}}}));
      }
      const transport=async(url,options)=>{
        const response=await f.fetch(url,options);
        if(options.method==='GET'&&/^\/v1\/appScreenshots\/[^/]+$/.test(new URL(url).pathname)){
          const doc=await response.json();delete doc.data.attributes.uploadOperations;return new Response(JSON.stringify(doc));
        }
        return response;
      };
      const result=await registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root},transport,{sleep:async()=>{},distribution:distributionReady});
      assert.equal(result.preparedScreenshots.length,8);
      const deletes=f.calls.filter(c=>c.method==='DELETE');
      assert.equal(deletes.length,preexisting?1:0);
      if(preexisting){assert.equal(new URL(deletes[0].url).pathname,'/v1/appScreenshots/34000019-713a-8cfb-8037-5f8c33da22ed');assert.equal(result.recreatedEmptyReservations[0].id,'34000019-713a-8cfb-8037-5f8c33da22ed');}
      assert.ok(result.reservations.every(r=>r.uploadHosts[0]==='store-030.blobstore.apple.com'));
    }
  }finally{await rm(root,{recursive:true,force:true});}
});
test('failed or foreign empty reservation cannot enter the DELETE gate',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-no-delete-'));
  try{
    await mediaFixture(root);
    for(const variant of ['FAILED','foreign','unapproved-empty']){
      const f=mutableFixture();const bytes=await readFile(join(root,'iphone','01-home.jpg'));
      f.records.set('/v1/appScreenshotSets/set',obj('appScreenshotSets','set',{screenshotDisplayType:'APP_IPHONE_67'},{appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:'vl'}}}));
      f.records.set('/v1/appScreenshots/image',obj('appScreenshots','image',{fileName:'01-home.jpg',fileSize:bytes.length,sourceFileChecksum:null,assetDeliveryState:{state:variant==='FAILED'?'FAILED':'AWAITING_UPLOAD'}},{appScreenshotSet:{data:{type:'appScreenshotSets',id:'set'}}}));
      const transport=async(url,options)=>{
        const response=await f.fetch(url,options);
        if(variant==='foreign'&&new URL(url).pathname==='/v1/appScreenshots/image'){
          const doc=await response.json();doc.data.relationships.appScreenshotSet.data.id='another-set';return new Response(JSON.stringify(doc));
        }return response;
      };
      await assert.rejects(registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root},transport,{sleep:async()=>{},distribution:distributionReady}));
      assert.ok(f.calls.every(c=>c.method!=='DELETE'));
    }
  }finally{await rm(root,{recursive:true,force:true});}
});

test('authenticated Apple object-storage host is allowed exactly without widening other regions',()=>{
  assert.equal(safeUploadUrl('https://northamerica-1.object-storage.apple.com/upload?signature=private').hostname,'northamerica-1.object-storage.apple.com');
  for(const url of ['https://northamerica-1.object-storage.apple.com.evil.invalid/a',
    'https://northamerica-2.object-storage.apple.com/a','https://object-storage.apple.com/a',
    'http://northamerica-1.object-storage.apple.com/a','https://user@northamerica-1.object-storage.apple.com/a',
    'https://northamerica-1.object-storage.apple.com:444/a'])assert.throws(()=>safeUploadUrl(url));
});
test('known committed image is polled only after remaining upload, never reuploaded or deleted; timeout stays partial',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-processing-'));
  try{
    await mediaFixture(root);
    for(const finish of [true,false]){
      const f=mutableFixture();const config={...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root};
      const options={sleep:async()=>{},distribution:distributionReady};
      await registerApp(config,f.fetch,options);
      const ipadSet=[...f.records.values()].find(r=>r.type==='appScreenshotSets'&&r.attributes.screenshotDisplayType==='APP_IPAD_PRO_3GEN_129');
      const family=[...f.records.values()].find(r=>r.type==='appScreenshots'&&r.attributes.fileName==='03-family.jpg'&&r.relationships.appScreenshotSet.data.id===ipadSet.id);
      const last=[...f.records.values()].find(r=>r.type==='appScreenshots'&&r.attributes.fileName==='04-history.jpg'&&r.relationships.appScreenshotSet.data.id===ipadSet.id);
      f.records.delete('/v1/appScreenshots/'+family.id);f.records.delete('/v1/appScreenshots/'+last.id);
      family.id='fd000019-713a-8cfb-8028-5678fc36717b';family.attributes.assetDeliveryState={state:'UPLOAD_COMPLETE'};
      const checksum=family.attributes.sourceFileChecksum;family.attributes.sourceFileChecksum=null;
      f.records.set('/v1/appScreenshots/'+family.id,family);
      const start=f.calls.length;let polls=0;
      const transport=async(url,request)=>{
        const u=new URL(url);
        if(u.pathname==='/v1/appScreenshots/'+family.id&&!u.search){
          assert.equal(request.method,'GET');polls++;
          assert.ok(f.calls.slice(start).some(c=>c.method==='PATCH'&&new URL(c.url).pathname.startsWith('/v1/appScreenshots/')),'eighth file must be committed before waiting');
          if(finish){family.attributes.assetDeliveryState={state:'COMPLETE'};family.attributes.sourceFileChecksum=checksum;}
        }
        return f.fetch(url,request);
      };
      const result=await registerApp(config,transport,options);const calls=f.calls.slice(start);
      assert.equal(calls.filter(c=>c.method==='POST'&&new URL(c.url).pathname==='/v1/appScreenshots').length,1);
      assert.equal(calls.filter(c=>c.method==='PUT').length,1);
      assert.ok(calls.every(c=>c.method!=='DELETE'));
      assert.ok(calls.filter(c=>new URL(c.url).pathname==='/v1/appScreenshots/'+family.id).every(c=>c.method==='GET'));
      assert.equal(result.prepared,finish);assert.equal(result.screenshotsPrepared,finish);
      assert.equal(result.preparedScreenshots.length,finish?8:7);
      assert.equal(polls,finish?1:90);
      if(!finish)assert.ok(result.blockers.some(b=>b.includes('bounded polling')));
    }
  }finally{await rm(root,{recursive:true,force:true});}
});
test('unknown committed pending image is still blocked before writes',async()=>{
  const root=await mkdtemp(join(tmpdir(),'asc-unknown-processing-'));
  try{
    await mediaFixture(root);const f=mutableFixture();const bytes=await readFile(join(root,'iphone','01-home.jpg'));
    f.records.set('/v1/appScreenshotSets/set',obj('appScreenshotSets','set',{screenshotDisplayType:'APP_IPHONE_67'},{appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:'vl'}}}));
    f.records.set('/v1/appScreenshots/unknown-processing',obj('appScreenshots','unknown-processing',{fileName:'01-home.jpg',fileSize:bytes.length,sourceFileChecksum:null,assetDeliveryState:{state:'UPLOAD_COMPLETE'}},{appScreenshotSet:{data:{type:'appScreenshotSets',id:'set'}}}));
    await assert.rejects(registerApp({...env,APP_STORE_REGISTRATION_MODE:'prepare',APP_STORE_MEDIA_ROOT:root},f.fetch,{sleep:async()=>{},distribution:distributionReady}),/incomplete/);
    assert.ok(f.calls.every(c=>c.method==='GET'));
  }finally{await rm(root,{recursive:true,force:true});}
});
