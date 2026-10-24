'use strict';
const assert = require('node:assert/strict');
const { readQuota, resolveCommand } = require('../src/infrastructure/read-quota.cjs');
const command = code => ({ file: process.execPath, args: ['-e', code] });
(async () => {
  const success = await readQuota(command([
    "const readline = require('node:readline'); let stage = 0;",
    "const send = value => process.stdout.write(JSON.stringify(value) + '\\n');",
    "readline.createInterface({ input: process.stdin }).on('line', line => {",
    " const message = JSON.parse(line);",
    " if (stage === 0 && message.method === 'initialize') { stage++; send({ id: 1, result: {} }); }",
    " else if (stage === 1 && message.method === 'initialized') { stage++; }",
    " else if (stage === 2 && message.method === 'account/rateLimits/read') {",
    "   process.stdout.write('ignored diagnostic line\\n');",
    "   send({ method: 'account/updated', params: {} });",
    "   send({ id: 2, result: { rateLimits: { primary: { usedPercent: 23, windowDurationMins: 300 } } } });",
    " } else { throw new Error('Unexpected or mutating request'); }",
    "});"
  ].join('\n')), 3000);
  assert.equal(success.available, true);
  assert.equal(success.data.rateLimits.primary.usedPercent, 23);
  const unsupported = await readQuota(command("process.stdin.once('data', () => console.log(JSON.stringify({ id: 1, error: { code: -32601 } })));"), 3000);
  assert.equal(unsupported.reason, 'unsupported');
  const denied = await readQuota(command([
    "const readline = require('node:readline');",
    "readline.createInterface({ input: process.stdin }).on('line', line => {",
    " const message = JSON.parse(line);",
    " if (message.id) console.log(JSON.stringify(message.id === 1 ? { id: 1, result: {} } : { id: 2, error: { message: 'private details' } }));",
    "});"
  ].join('\n')), 3000);
  assert.deepEqual(denied, { available: false, reason: 'unavailable' });
  const timeout = await readQuota(command("setInterval(() => {}, 1000)"), 150);
  assert.equal(timeout.reason, 'timeout');
  const missing = await readQuota({ file: 'this-command-does-not-exist-quota-test', args: [] }, 1000);
  assert.equal(missing.available, false);
  assert.equal(resolveCommand(process.execPath).file, process.execPath);
  console.log('PASS: quota initialization, read-only requests, notifications, unsupported API, private errors, bounded timeout and launch failure.');
})().catch(error => { console.error(error); process.exitCode = 1; });
