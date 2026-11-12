// Only the Korean subtitle of one verified, editable carcar app-info record.
import {createPrivateKey, sign} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {safeApiUrl} from './app_store_registration.mjs';
const APP='6829616379', VERSION='1.0.2', SUBTITLE='아파트 주차 위치, 혼자도 가족과도';
const check=(ok,msg)=>{if(!ok)throw Error(msg);};
const state=x=>x.attributes?.appVersionState??x.attributes?.state??x.attributes?.appStoreState;
const item=(x,type)=>{check(x?.type===type&&/^[A-Za-z0-9-]+$/.test(x.id??''),'Unexpected resource identity');return x;};
const owner=(x,name,type,id)=>{const p=x.relationships?.[name]?.data;check(p?.type===type&&p.id===id,'Unexpected resource owner');};
function signer(env){
 check(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID??'')&&/^[a-f0-9-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID??''),'Invalid signing identifiers');
 let key;try{key=createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64??'','base64'));}catch{throw Error('Invalid signing key');}
 check(key.asymmetricKeyType==='ec'&&key.asymmetricKeyDetails?.namedCurve==='prime256v1','ES256 key required');
 return ()=>{const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url'),now=Math.floor(Date.now()/1000);const data=enc({alg:'ES256',typ:'JWT',kid:env.APP_STORE_CONNECT_KEY_ID})+'.'+enc({iss:env.APP_STORE_CONNECT_ISSUER_ID,iat:now,exp:now+300,aud:'appstoreconnect-v1'});return data+'.'+sign('sha256',Buffer.from(data),{key,dsaEncoding:'ieee-p1363'}).toString('base64url');};
}
export async function updateSubtitle(env,fetchImpl=fetch){
 const mode=env.APP_STORE_SUBTITLE_MODE??'inspect';check(['inspect','apply'].includes(mode),'Invalid mode');
 const draft=JSON.parse(await readFile(env.APP_STORE_SUBTITLE_DRAFT_PATH??'docs/app-store/public-listing-ko.json','utf8'));
 check(draft.appId===APP&&draft.locale==='ko'&&draft.listing?.subtitle===SUBTITLE,'Unapproved subtitle draft');
 const token=signer(env);
 async function request(path,body){
  let response;try{response=await fetchImpl(safeApiUrl(path),{method:body?'PATCH':'GET',headers:{Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(30000)});}catch{throw Error(body?'Subtitle write outcome unknown; inspect before retry':'Apple request failed');}
  check(response.ok,'Apple HTTP '+response.status);return response.json();
 }
 async function list(path,type){const initial=safeApiUrl(path);let rows=[],seen=new Set();while(path){const next=safeApiUrl(path);check(next.origin===initial.origin&&next.pathname===initial.pathname,'Pagination left scoped endpoint');const u=next.href;check(!seen.has(u),'Pagination loop');seen.add(u);const doc=await request(u);check(Array.isArray(doc.data),'Invalid list');rows.push(...doc.data.map(x=>item(x,type)));path=doc.links?.next;}return rows;}
 async function snapshot(){
  const app=item((await request('/v1/apps/'+APP)).data,'apps');check(app.id===APP&&app.attributes?.bundleId==='com.kang88.carcar','Wrong app');
  const versions=await list('/v1/apps/'+APP+'/appStoreVersions?include=app&limit=200','appStoreVersions');versions.forEach(v=>owner(v,'app','apps',APP));
  const ios=versions.filter(v=>v.attributes?.platform==='IOS');
  const targets=ios.filter(v=>v.attributes.versionString===VERSION);check(targets.length===1&&state(targets[0])==='PREPARE_FOR_SUBMISSION','Target version must be editable');
  const terminal=['READY_FOR_DISTRIBUTION','READY_FOR_SALE','REPLACED_WITH_NEW_VERSION','REMOVED_FROM_SALE','DEVELOPER_REMOVED_FROM_SALE'];
  check(ios.every(v=>v.id===targets[0].id||terminal.includes(state(v))),'Another open iOS version');
  const infos=await list('/v1/apps/'+APP+'/appInfos?include=app&limit=200','appInfos');infos.forEach(i=>owner(i,'app','apps',APP));
  const editable=infos.filter(i=>state(i)==='PREPARE_FOR_SUBMISSION');check(editable.length===1,'Exactly one editable app info required');
  const info=editable[0];const locales=await list('/v1/appInfos/'+info.id+'/appInfoLocalizations?limit=200','appInfoLocalizations');
  const ko=locales.filter(l=>l.attributes?.locale==='ko');check(ko.length===1,'Exactly one Korean localization required');
  // The scoped relationship endpoint supplies parent ownership; validate any explicit linkage too.
  if(ko[0].relationships?.appInfo)owner(ko[0],'appInfo','appInfos',info.id);
  return {version:targets[0].id,info:info.id,locale:ko[0].id,subtitle:ko[0].attributes.subtitle};
 }
 const before=await snapshot();let wrote=false;
 if(mode==='apply'&&before.subtitle!==SUBTITLE){
  const fresh=await snapshot();check(['version','info','locale'].every(k=>fresh[k]===before[k]),'Target changed before write');
  await request('/v1/appInfoLocalizations/'+fresh.locale,{data:{type:'appInfoLocalizations',id:fresh.locale,attributes:{subtitle:SUBTITLE}}});wrote=true;
 }
 const after=await snapshot();check(['version','info','locale'].every(k=>after[k]===before[k]),'Target changed during verification');
 if(mode==='apply')check(after.subtitle===SUBTITLE,'Subtitle readback mismatch');
 const result={tool:'app_store_subtitle',mode,appId:APP,targetVersion:VERSION,...after,expectedSubtitle:SUBTITLE,matches:after.subtitle===SUBTITLE,wrote};
 if(env.APP_STORE_SUBTITLE_SUMMARY_PATH)await writeFile(env.APP_STORE_SUBTITLE_SUMMARY_PATH,JSON.stringify(result,null,2)+'\n',{mode:0o600});
 return result;
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url)updateSubtitle(process.env).then(x=>console.log(JSON.stringify(x,null,2))).catch(e=>{console.error(e.message);process.exitCode=1;});
