// Use exactly the same prompt data (including demo fallback) as the macOS page.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = { window: {} };
context.window = context;
vm.createContext(context);
for (const file of ['prompts.js', 'demo-prompts.js']) {
  const source = path.join(__dirname, '../data', file);
  if (fs.existsSync(source)) vm.runInContext(fs.readFileSync(source, 'utf8'), context);
}
process.stdout.write(JSON.stringify(context.PROMPTS));
