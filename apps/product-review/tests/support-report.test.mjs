import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, readdir, access, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { main, validateReport } from '../src/support-report.mjs';

const report = '# Lỗi Product Review\n## Tóm tắt\nsecret-test\n## Nguyên nhân\nCó log lỗi.\n## Cách sửa cho người dùng\nKiểm tra.\n## Đánh giá đã Bỏ\nrun__item\n## Cần sửa trong app\nKhông.';
test('reject incomplete AI output and redact configured secrets', () => {
  assert.throws(() => validateReport('AI failed'), /tiêu đề/);
  assert.throws(() => validateReport('# Lỗi Product Review'), /thiếu mục/);
  assert.ok(!validateReport(report, ['secret-test']).includes('secret-test'));
});
for (const mode of ['ok', 'upload-failed', 'ai-failed', 'invalid', 'omitted-sample']) {
  test(`report lifecycle: ${mode}`, async () => {
    const base = resolve('workspace/tests'); await mkdir(base, { recursive: true });
    const root = await mkdtemp(join(base, 'support-node-'));
    try {
      await mkdir(join(root, 'docs'), { recursive: true });
      await mkdir(join(root, 'workspace/rejected/run__item'), { recursive: true });
      await writeFile(join(root, 'docs/error-report.md'), 'Read only local logs.');
      await writeFile(join(root, 'workspace/drive.json'), JSON.stringify({ apiUrl: 'https://example.test', adminKey: 'secret-test' }));
      await writeFile(join(root, 'workspace/rejected/run__item/sample.json'), '{}');
      let calls = 0;
      const options = { projectRoot: root,
        generateReport: async (prompt, file) => {
          assert.match(prompt, /run__item/);
          if (mode === 'ai-failed') throw Error('AI stopped');
          await writeFile(file, mode === 'invalid' ? 'bad output' : mode === 'omitted-sample' ? report.replace('run__item', 'Không') : report);
        },
        request: async (url, init) => {
          calls++; assert.equal(init.headers['x-admin-key'], 'secret-test');
          assert.ok(!init.body.includes('secret-test'));
          return { ok: mode !== 'upload-failed', status: mode === 'upload-failed' ? 503 : 201 };
        },
      };
      if (['ai-failed', 'invalid'].includes(mode)) await assert.rejects(main(options));
      else await main(options);
      assert.equal(calls, ['ai-failed', 'invalid'].includes(mode) ? 0 : 1);
      const sent = () => access(join(root, 'workspace/rejected/run__item/.sent'));
      if (mode === 'ok') await sent(); else await assert.rejects(sent());
      if (['ok', 'omitted-sample'].includes(mode)) await access(join(root, 'workspace/support-sent.txt'));
      else await assert.rejects(access(join(root, 'workspace/support-sent.txt')));
      if (mode === 'upload-failed') {
        const file = (await readdir(join(root, 'workspace/temp'))).find(n => n.endsWith('.md'));
        assert.match(await readFile(join(root, 'workspace/temp', file), 'utf8'), /## Tóm tắt/);
      }
    } finally { await rm(root, { recursive: true, force: true }); }
  });
}
