// Print a Paged.js-paginated HTML document to PDF with headless Chrome.
// Usage: node render.js <input.html> <output.pdf>
// Requires puppeteer-core and a Chrome binary (CHROME_PATH overrides the default).
//
// The settle-wait below is required, not an optimization: Paged.js repaginates
// the document asynchronously after load, and printing before the page count
// stabilizes captures a partially paginated document. A plain
// `chrome --headless --print-to-pdf --virtual-time-budget` race has truncated
// a 28-page document to 7 pages. Wait until the .pagedjs_page count has been
// stable for 2 seconds before printing.
const puppeteer = require('puppeteer-core');
(async () => {
  const [,, input, output] = process.argv;
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
    args: ['--no-sandbox', '--disable-gpu', '--force-device-scale-factor=1']});
  const page = await browser.newPage();
  page.on('pageerror', e => console.error('PAGEERROR:', e.message));
  await page.goto('file://' + require('path').resolve(input), {waitUntil: 'load', timeout: 120000});
  // wait until the pagedjs page count is stable for 2s
  let last = -1, stableSince = Date.now();
  const t0 = Date.now();
  while (Date.now() - t0 < 180000) {
    const n = await page.evaluate(() => document.querySelectorAll('.pagedjs_page').length);
    if (n !== last || n === 0) { last = n; stableSince = Date.now(); }
    if (n > 0 && Date.now() - stableSince > 2000) break;
    await new Promise(r => setTimeout(r, 300));
  }
  console.log('paged pages:', last);
  await page.pdf({path: output, preferCSSPageSize: true, printBackground: true, displayHeaderFooter: false});
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
