// Renders the README illustrations (Marketing/readme/*.html) into Marketing/readme/assets with Playwright + local Chrome.
// Usage: node render.mjs [name]   (see render.sh, which installs Playwright into a temp dir)
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const pwDir = process.env.SNIP_PW_DIR || '/tmp/snip-pw';
const { chromium } = createRequire(path.join(pwDir, 'package.json'))('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const only = process.argv[2];
const pages = fs.readdirSync(here).filter((f) => f.endsWith('.html') && f !== 'motion.html' && (!only || f.startsWith(only)));

const browser = await chromium.launch({ channel: 'chrome' });
for (const f of pages) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1.5 });
  await page.goto(pathToFileURL(path.join(here, f)).href, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));
  const file = path.join(here, 'assets', f.replace('.html', '.png'));
  await page.screenshot({ path: file });
  await page.close();
  console.log('wrote', path.relative(process.cwd(), file));
}
await browser.close();
