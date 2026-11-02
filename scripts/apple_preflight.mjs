#!/usr/bin/env node
// Read-only App Store Connect checks. The private key never enters the repository or output.
import {readFile} from 'node:fs/promises';
import {sign, X509Certificate} from 'node:crypto';

async function main() {
  if (process.argv.length !== 3) throw new Error('Usage: node scripts/apple_preflight.mjs /secure/path/apple.json');
  let config;
  try { config = JSON.parse(await readFile(process.argv[2], 'utf8')); }
  catch { throw new Error('Cannot read the local Apple configuration.'); }
  const {keyId, issuerId, privateKeyPath, teamId} = config;
  if (!/^[A-Z0-9]{10}$/.test(keyId ?? '') || !/^[0-9a-f-]{36}$/i.test(issuerId ?? '') || !/^[A-Z0-9]{10}$/.test(teamId ?? '') || typeof privateKeyPath !== 'string') {
    throw new Error('Apple configuration is incomplete.');
  }
  let privateKey;
  try { privateKey = await readFile(privateKeyPath); }
  catch { throw new Error('Cannot read the protected API key file.'); }
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const message = encode({alg: 'ES256', kid: keyId, typ: 'JWT'}) + '.' + encode({iss: issuerId, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'});
  let jwt;
  try { jwt = message + '.' + sign('sha256', Buffer.from(message), {key: privateKey, dsaEncoding: 'ieee-p1363'}).toString('base64url'); }
  catch { throw new Error('The API key could not sign a request.'); }
  async function get(path) {
    let response;
    try { response = await fetch('https://api.appstoreconnect.apple.com' + path, {headers: {Authorization: 'Bearer ' + jwt}, redirect: 'error', signal: AbortSignal.timeout(20000)}); }
    catch { throw new Error('Apple API could not be reached.'); }
    if (!response.ok) throw new Error('Apple API read failed (HTTP ' + response.status + ').');
    return (await response.json()).data;
  }
  const bundleIds = ['com.kang88.carcar', 'com.kang88.carcar.ParkingWidget'];
  const [apps, certificates, ...bundles] = await Promise.all([
    get('/v1/apps?filter%5BbundleId%5D=' + bundleIds[0]),
    get('/v1/certificates?limit=200'),
    ...bundleIds.map(id => get('/v1/bundleIds?filter%5Bidentifier%5D=' + id)),
  ]);
  const valid = certificates.filter(item => {
    if (!['DISTRIBUTION', 'IOS_DISTRIBUTION'].includes(item.attributes.certificateType)) return false;
    const cert = new X509Certificate(Buffer.from(item.attributes.certificateContent, 'base64'));
    return cert.subject.split('\n').includes('OU=' + teamId) && Date.parse(cert.validTo) > Date.now();
  });
  console.log(JSON.stringify({checkedAt: new Date().toISOString(), readOnly: true, authenticated: true, teamId, appRecordExists: apps.length > 0, bundles: bundleIds.map((identifier, index) => ({identifier, registered: bundles[index].length > 0})), validDistributionCertificates: valid.map(item => ({id: item.id, expiresAt: item.attributes.expirationDate})), distributionPrivateKeyChecked: false, performedUpload: false}, null, 2));
}
main().catch(error => {
  // Only our fixed diagnostics are printed; never upstream response bodies or argv.
  const allowed = /^(Usage:|Cannot read|Apple configuration|The API key|Apple API)/;
  console.error(allowed.test(error.message) ? error.message : 'Apple preflight could not complete.');
  process.exitCode = 1;
});
