import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {updateSubtitle} from './app_store_subtitle.mjs';
const key=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).privateKey.export({type:'pkcs8',format:'pem'});
const env={APP_STORE_CONNECT_KEY_ID:'ABCDEFGHIJ',APP_STORE_CONNECT_ISSUER_ID:'11111111-1111-1111-1111-111111111111',APP_STORE_CONNECT_API_KEY_P8_BASE64:Buffer.from(key).toString('base64'),APP_STORE_SUBTITLE_MODE:'apply'};
function fixture(change={}){
 const rel=(type,id)=>({data:{type,id}});let subtitle='old';const writes=[];
 const version={type:'appStoreVersions',id:'v2',attributes:{platform:'IOS',versionString:'1.0.2',appVersionState:change.versionState??'PREPARE_FOR_SUBMISSION'},relationships:{app:rel('apps',change.owner??'6829616379')}};
 const info={type:'appInfos',id:'i2',attributes:{state:change.infoState??'PREPARE_FOR_SUBMISSION'},relationships:{app:rel('apps','6829616379')}};
 const requests=[];const fetch=async(url,opt)=>{requests.push(String(url));const p=new URL(url).pathname;let data;
 if(opt.method==='PATCH'){writes.push(JSON.parse(opt.body));if(!change.ignoreWrite)subtitle=writes.at(-1).data.attributes.subtitle;data={};}
 else if(p==='/v1/apps/6829616379')data={type:'apps',id:'6829616379',attributes:{bundleId:'com.kang88.carcar'}};
 else if(p.endsWith('/appStoreVersions'))data=[version];
 else if(p.endsWith('/appInfos'))data=change.duplicate?[info,{...info,id:'i3'}]:[info];
 else if(p.endsWith('/appInfoLocalizations'))data=[{type:'appInfoLocalizations',id:'l2',attributes:{locale:change.locale??'ko',subtitle},...(change.localeParent?{relationships:{appInfo:rel('appInfos',change.localeParent)}}:{})}];
 else throw Error('Unexpected URL');
 return {ok:true,status:200,json:async()=>({data,...(p.endsWith('/appInfoLocalizations')&&change.next?{links:{next:change.next}}:{})})};};
 return {fetch,writes,requests};
}
test('patches only approved Korean subtitle and verifies readback',async()=>{const f=fixture();const r=await updateSubtitle(env,f.fetch);assert.equal(r.matches,true);assert.deepEqual(f.writes,[{data:{type:'appInfoLocalizations',id:'l2',attributes:{subtitle:'아파트 주차 위치, 혼자도 가족과도'}}}]);});
test('inspect never writes',async()=>{const f=fixture();assert.equal((await updateSubtitle({...env,APP_STORE_SUBTITLE_MODE:'inspect'},f.fetch)).matches,false);assert.equal(f.writes.length,0);});
for(const [name,change] of Object.entries({foreign:{owner:'other'},liveVersion:{versionState:'READY_FOR_DISTRIBUTION'},liveInfo:{infoState:'READY_FOR_DISTRIBUTION'},ambiguous:{duplicate:true},locale:{locale:'en-US'}}))test('rejects '+name+' before writing',async()=>{const f=fixture(change);await assert.rejects(updateSubtitle(env,f.fetch));assert.equal(f.writes.length,0);});
test('readback mismatch is not success',async()=>{const f=fixture({ignoreWrite:true});await assert.rejects(updateSubtitle(env,f.fetch),/readback mismatch/);});
test('unapproved draft is rejected before requests',async()=>{let requests=0;await assert.rejects(updateSubtitle({...env,APP_STORE_SUBTITLE_DRAFT_PATH:'docs/app-store/update-1.0.1.json'},async()=>{requests++;}),/Unapproved/);assert.equal(requests,0);});

test('pagination cannot leave the verified appInfo localization endpoint',async()=>{const f=fixture({next:'/v1/appInfos/foreign/appInfoLocalizations?cursor=2'});await assert.rejects(updateSubtitle(env,f.fetch),/Pagination left scoped endpoint/);assert.equal(f.writes.length,0);assert.ok(f.requests.every(p=>!p.includes('/foreign/')));});
test('pagination cannot send authorization to another origin',async()=>{const f=fixture({next:'https://evil.example/v1/appInfos/i2/appInfoLocalizations?cursor=2'});await assert.rejects(updateSubtitle(env,f.fetch),/Unexpected Apple API destination/);assert.equal(f.writes.length,0);assert.ok(f.requests.every(p=>!p.includes('evil.example')));});
test('explicit foreign localization parent is rejected',async()=>{const f=fixture({localeParent:'foreign'});await assert.rejects(updateSubtitle(env,f.fetch),/Unexpected resource owner/);assert.equal(f.writes.length,0);});
