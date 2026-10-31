import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createSetupReader, parseSetupReport } from '../setup/setup-report.mjs';

const report = { Steps: ['drive','node','codex','login','quota'].map(Id => ({Id,State:'ok'})) };
const payload = JSON.stringify(report);
test('UTF-8 BOM accepted; empty, incomplete and invalid state rejected', () => {
  assert.deepEqual(parseSetupReport('\uFEFF'+payload), report);
  for (const invalid of ['', '{}', '{', JSON.stringify({Steps:report.Steps.slice(0,4)}), JSON.stringify({Steps:report.Steps.map(s=>({...s,State:'unknown'}))})]) assert.throws(()=>parseSetupReport(invalid));
});
test('concurrent checks share a child; new check reads fresh; valid exit 1 is a readiness result', async () => {
  let calls=0;
  const read=createSetupReader({execute:(exe,args,options,done)=>{calls++;setTimeout(()=>done({code:1},payload,''),5);}});
  const [a,b]=await Promise.all([read(),read()]);
  assert.equal(calls,1); assert.equal(a.status,200); assert.deepEqual(a,b);
  await read(); assert.equal(calls,2);
});
test('bad output is logged, reported as an error and does not poison retry', async () => {
  const hubRoot=mkdtempSync(join(tmpdir(),'hub-setup-'));
  let calls=0;
  try {
    const read=createSetupReader({hubRoot,execute:(exe,args,options,done)=>setImmediate(()=>done(null,++calls===1?'not json':payload,''))});
    assert.equal((await read()).report.code,'SETUP_INVALID_REPORT');
    assert.equal(readdirSync(join(hubRoot,'workspace/logs')).length,1);
    assert.equal((await read()).status,200);
  } finally {rmSync(hubRoot,{recursive:true});}
});
test('real stalled child times out, then a new check can run', async () => {
  const hubRoot=mkdtempSync(join(tmpdir(),'hub-timeout-'));
  try {
    const read=createSetupReader({hubRoot,pwsh:process.execPath,args:['-e','setInterval(()=>{},1000)'],timeout:80});
    const result=await read();
    assert.equal(result.status,504);assert.equal(result.report.code,'SETUP_TIMEOUT');
  } finally {rmSync(hubRoot,{recursive:true});}
});
