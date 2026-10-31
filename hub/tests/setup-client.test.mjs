import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('../assets/hub.js',import.meta.url),'utf8');
const client=source.slice(source.indexOf('  let setupRequest;'),source.indexOf('  async function refreshStatus'))+'\nglobalThis.read=requestSetup;';
const report={Steps:['drive','node','codex','login','quota'].map(Id=>({Id,State:'ok'}))};
function setup(fetch, extra={}){
  const context=vm.createContext({fetch,AbortController,setTimeout,clearTimeout,STEP_NAMES:{drive:'',node:'',codex:'',login:''},...extra});
  vm.runInContext(client,context);return context;
}
test('menu and open dialog share a request; a later check is fresh',async()=>{
  let calls=0;
  const app=setup(async()=>{calls++;await new Promise(r=>setTimeout(r,5));return {ok:true,json:async()=>report};});
  const [a,b]=await Promise.all([app.read(),app.read()]);
  assert.equal(calls,1);assert.equal(a.Steps.length,5);assert.deepEqual(a,b);
  await app.read();assert.equal(calls,2);
});
test('HTTP failure, dropped connection and incomplete reports always resolve to errors',async()=>{
  for(const fetch of [async()=>({ok:false,json:async()=>({error:'server failed'})}),async()=>{throw new Error('offline');},async()=>({ok:true,json:async()=>({Steps:report.Steps.slice(0,4)})})]){
    assert.ok((await setup(fetch).read()).error);
  }
});
test('a stalled request is aborted and a subsequent retry succeeds',async()=>{
  let fire,calls=0;
  const app=setup((url,{signal})=>{
    if(++calls>1)return Promise.resolve({ok:true,json:async()=>report});
    return new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(Object.assign(new Error('timeout'),{name:'AbortError'}))));
  },{setTimeout:callback=>{fire=callback;return 1;},clearTimeout:()=>{}});
  const pending=app.read();fire();assert.ok((await pending).error);
  assert.equal((await app.read()).Steps.length,5);
});
