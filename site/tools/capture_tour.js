// Records the README "auto-tour" of the solar system: each planet is featured in turn (it parks and
// spins, the others slow down, its GitHub description card fades in). Frames are captured with fixed
// time steps from site/system/index.html?capture and later encoded to an animated WebP.
//
//   node site/tools/capture_tour.js OUT_DIR [--fps 10] [--three PATH] [--facts PATH] [--fonts DIR]
//
// --three / --facts / --fonts serve local copies instead of the CDN, raw.githubusercontent and
// Google Fonts (for sandboxes without those hosts). Requires Playwright with Chromium.
const { chromium } = require("playwright");
const http = require("http"), fs = require("fs"), path = require("path");

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const out = args[0], fps = Number(opt("--fps", 10));
const root = path.resolve(__dirname, "..");

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const server = http.createServer((q, r) => {
    const f = path.join(root, decodeURIComponent(q.url.split("?")[0]).replace(/\/$/, "/index.html"));
    fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); r.end(); } else { r.writeHead(200, { "content-type": "text/html" }); r.end(b); } });
  }).listen(0);
  const port = server.address().port;
  const browser = await chromium.launch({ args: ["--use-gl=swiftshader", "--enable-unsafe-swiftshader"] });
  const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 1 });
  if (opt("--three")) await page.route("**/three.module.js", (r) => r.fulfill({ path: opt("--three"), contentType: "text/javascript" }));
  if (opt("--facts")) await page.route("**/repos.json", (r) => r.fulfill({ path: opt("--facts"), contentType: "application/json" }));
  if (opt("--fonts")) {
    const dir = opt("--fonts");
    const face = (fam, w, file) => `@font-face{font-family:'${fam}';font-weight:${w};src:url(https://fonts.local/${file}) format('truetype')}`;
    const css = [face("Space Grotesk", 500, "space-grotesk-500.ttf"), face("Space Grotesk", 700, "space-grotesk-700.ttf"),
      face("JetBrains Mono", 500, "jetbrains-mono-500.ttf"), face("Syne", 800, "syne-800.ttf")].join("\n");
    await page.route("https://fonts.googleapis.com/**", (r) => r.fulfill({ body: css, contentType: "text/css" }));
    await page.route("https://fonts.local/**", (r) => r.fulfill({ path: path.join(dir, r.request().url().split("/").pop()), contentType: "font/ttf" }));
  }
  await page.route("https://api.github.com/**", (r) => r.fulfill({ status: 404, body: "{}" }));
  await page.goto(`http://localhost:${port}/system/?capture`);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
  await page.evaluate(() => document.fonts.ready);
  const n = await page.evaluate((f) => window.__tour.prepare(f), fps);
  for (let i = 0; i < n; i++) {
    await page.evaluate(() => window.__tour.step());
    await page.screenshot({ path: path.join(out, `f${String(i + 1).padStart(4, "0")}.png`) });
    if (i % 50 === 0) console.log(`[tour] ${i + 1}/${n}`);
  }
  await browser.close(); server.close();
  console.log(`[tour] ${n} frames at ${fps} fps -> ${out}`);
})();
