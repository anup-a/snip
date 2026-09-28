// Renders the v2 App Store screenshots (and the v2 demo scenes) with Playwright + local Chrome.
// Usage: node render.mjs [scenes|shots|all]   (see render.sh, which installs Playwright into a temp dir)
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const pwDir = process.env.SNIP_PW_DIR || '/tmp/snip-pw';
const { chromium } = createRequire(path.join(pwDir, 'package.json'))('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../appstore-v2');
const mode = process.argv[2] || 'shots';
const only = process.argv[3]; // optional: render just one shot, e.g. `node render.mjs shots 1-snap`

const jobs = [];
if (mode === 'scenes' || mode === 'all') {
  for (const s of ['dash', 'chat']) {
    jobs.push({ url: pathToFileURL(path.join(here, 'scenes/scene.html')).href + `?s=${s}`, file: path.join(here, `scenes/${s}.png`) });
  }
}
if (mode === 'shots' || mode === 'all') {
  const shots = fs.readdirSync(here).filter((f) => /^\d-.*\.html$/.test(f) && (!only || f.startsWith(only))).sort();
  for (const f of shots) jobs.push({ url: pathToFileURL(path.join(here, f)).href, file: path.join(out, f.replace('.html', '.png')) });
  if (!only) jobs.push({ url: pathToFileURL(path.join(here, 'contact-sheet.html')).href, file: path.join(out, 'contact-sheet.png'), contact: true });
}

fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome' });
for (const job of jobs) {
  const w = job.contact ? 1800 : 1440;
  const h = job.contact ? 1 : 900;
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: job.contact ? 1 : 2 });
  await page.goto(job.url, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));
  await page.screenshot({ path: job.file, fullPage: !!job.contact });
  await page.close();
  console.log('wrote', path.relative(process.cwd(), job.file));
}
await browser.close();
