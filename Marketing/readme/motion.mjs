// Renders motion.html frame by frame into assets/demo.mp4 (1920x1080, 30 fps) and assets/demo.gif (README).
// Usage: node motion.mjs              video + GIF (needs ffmpeg)
//        node motion.mjs stills 1 3.5  PNG stills at those times, into $TMPDIR/snip-motion/
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';

const pwDir = process.env.SNIP_PW_DIR || '/tmp/snip-pw';
const { chromium } = createRequire(path.join(pwDir, 'package.json'))('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const assets = path.join(here, 'assets');
const FPS = 30;

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1.2 });
await page.goto(pathToFileURL(path.join(here, 'motion.html')).href, { waitUntil: 'load' });
await page.evaluate(() => document.fonts.ready);
await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));

if (process.argv[2] === 'stills') {
  const dir = path.join(os.tmpdir(), 'snip-motion');
  fs.mkdirSync(dir, { recursive: true });
  for (const t of process.argv.slice(3).map(Number)) {
    await page.evaluate((t) => window.render(t), t);
    const file = path.join(dir, `t${t.toFixed(2)}.png`);
    await page.screenshot({ path: file });
    console.log(file);
  }
} else {
  const duration = await page.evaluate(() => window.DURATION);
  const mp4 = path.join(assets, 'demo.mp4');
  const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'slow', '-movflags', '+faststart', mp4], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(duration * FPS);
  for (let i = 0; i < frames; i++) {
    await page.evaluate((t) => window.render(t), i / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
    if (i % 60 === 0) console.log(`frame ${i}/${frames}`);
  }
  ff.stdin.end();
  await new Promise((r, j) => ff.on('close', (c) => (c ? j(new Error('ffmpeg ' + c)) : r())));
  console.log('wrote', path.relative(process.cwd(), mp4));
  // README GIF: 800px wide, 15 fps, one palette for the whole clip.
  const gif = path.join(assets, 'demo.gif');
  await new Promise((r, j) => spawn('ffmpeg', ['-v', 'error', '-y', '-i', mp4, '-vf',
    'fps=15,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle', gif],
    { stdio: 'inherit' }).on('close', (c) => (c ? j(new Error('gif ' + c)) : r())));
  console.log('wrote', path.relative(process.cwd(), gif));
}
await browser.close();
