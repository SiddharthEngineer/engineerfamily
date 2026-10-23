#!/usr/bin/env node
// Checks the signed-in site header bar, <ef-site-header> (services/shared/site-header.js), on every page that uses it.
//   node scripts/check-header-layout.mjs <base-url> [--netrc FILE]
// /auth/me is routed to a signed-in answer and /strelitzia/dashboard/api/auth/me to the Strelitzia owner, so no real
// session is needed. For each page at 1280 and 390 px it checks that <ef-site-header> starts at y = 0, is as wide as the
// viewport and as tall as on the other pages (±1 px), <ef-home> and <ef-profile> share a top (±4 px), nothing scrolls
// sideways, the avatar ends inside the viewport, and the avatar menu has Users and Sign out with no other Sign out on
// the page. One line per page/width; exit 1 on any failure, 2 if Playwright can't run.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const PAGES = ['/', '/games/', '/privacy', '/strelitzia/', '/strelitzia/privacy'];
const WIDTHS = [1280, 390];
const ME = { enabled: true, signed_in: true, email: 'layout.check@example.com', name: 'Layout Check' };
const STRELITZIA_ME = { enabled: true, user: { role: 'owner' } };

function usage(message) {
  console.error(`${message}\nusage: node scripts/check-header-layout.mjs <base-url> [--netrc FILE]`);
  process.exit(2);
}

const args = process.argv.slice(2);
let baseUrl = null;
let netrcFile = null;
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--netrc') netrcFile = args[++i] ?? usage('--netrc needs a file');
  else if (!baseUrl) baseUrl = args[i];
  else usage(`unexpected argument: ${args[i]}`);
}
if (!baseUrl) usage('missing <base-url>');
baseUrl = baseUrl.replace(/\/+$/, '');

// Basic auth for the host from a netrc file (machine/login/password tokens); never printed.
function netrcCredentials(file, host) {
  const tokens = readFileSync(file, 'utf8').split(/\s+/).filter(Boolean);
  let current = null;
  const found = {};
  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === 'machine') current = tokens[++i];
    else if (token === 'default') current = '';
    else if ((token === 'login' || token === 'password') && current !== null) {
      found[current] ??= {};
      found[current][token] = tokens[++i];
    }
  }
  const entry = found[host] ?? found[''];
  if (!entry?.login) usage(`no netrc entry for ${host} in ${file}`);
  return { username: entry.login, password: entry.password ?? '' };
}

// Playwright from a local install, else whatever `npx -p playwright` resolves.
async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch {
    try {
      const cli = execFileSync('npx', ['--yes', '-p', 'playwright', '-c', 'realpath "$(command -v playwright)"'], {
        encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
      return await import(pathToFileURL(join(dirname(cli), 'index.mjs')).href);
    } catch {
      console.error('Playwright not found (tried a local install and npx -p playwright).');
      process.exit(2);
    }
  }
}

const { chromium } = await loadPlaywright();
let browser;
try {
  browser = await chromium.launch();
} catch (err) {
  console.error(`No Playwright browser installed (run: npx playwright install chromium).\n${err.message.split('\n')[0]}`);
  process.exit(2);
}

const httpCredentials = netrcFile ? netrcCredentials(netrcFile, new URL(baseUrl).hostname) : undefined;
let failed = false;
for (const width of WIDTHS) {
  const context = await browser.newContext({ viewport: { width, height: 900 }, httpCredentials });
  await context.route('**/auth/me', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify(ME) }));
  // Registered last, so it wins over the route above for the dashboard's /auth/me.
  await context.route('**/strelitzia/dashboard/api/auth/me',
    (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify(STRELITZIA_ME) }));
  let headerHeight = null; // the first page's, at this width
  for (const path of PAGES) {
    const page = await context.newPage();
    const problems = [];
    try {
      const resp = await page.goto(baseUrl + path, { waitUntil: 'networkidle' });
      if (!resp || !resp.ok()) throw new Error(`HTTP ${resp ? resp.status() : 'no response'}`);
      await page.waitForFunction(() => document.querySelector('ef-profile')?.shadowRoot?.querySelector('.avatar'), null,
        { timeout: 10000 });
      const m = await page.evaluate(() => {
        const rect = (el) => el && el.getBoundingClientRect();
        const header = rect(document.querySelector('ef-site-header'));
        const home = rect(document.querySelector('ef-site-header ef-home'));
        const profile = rect(document.querySelector('ef-site-header ef-profile'));
        const avatar = rect(document.querySelector('ef-profile').shadowRoot.querySelector('.avatar'));
        return {
          headerTop: header?.top, headerWidth: header?.width, headerHeight: header?.height,
          homeTop: home?.top, profileTop: profile?.top, avatarRight: avatar?.right,
          scrollWidth: document.documentElement.scrollWidth, viewport: window.innerWidth,
        };
      });
      if (m.headerTop === undefined) problems.push('no ef-site-header');
      else {
        if (Math.abs(m.headerTop) > 0.5) problems.push(`header top ${m.headerTop} != 0`);
        if (Math.abs(m.headerWidth - m.viewport) > 0.5) problems.push(`header width ${m.headerWidth} != viewport ${m.viewport}`);
        headerHeight ??= m.headerHeight;
        if (Math.abs(m.headerHeight - headerHeight) > 1) {
          problems.push(`header height ${m.headerHeight} != ${headerHeight} on ${PAGES[0]}`);
        }
      }
      if (m.homeTop === undefined || m.profileTop === undefined) problems.push('ef-home or ef-profile missing');
      else if (Math.abs(m.homeTop - m.profileTop) > 4) problems.push(`profile top ${m.profileTop} != home top ${m.homeTop}`);
      if (m.scrollWidth !== m.viewport) problems.push(`scrollWidth ${m.scrollWidth} != viewport ${m.viewport}`);
      if (m.avatarRight === undefined) problems.push('no avatar');
      else if (m.avatarRight > m.viewport) problems.push(`avatar right edge ${Math.round(m.avatarRight)} > ${m.viewport}`);

      // The avatar menu: Users (added when the Strelitzia answer comes) and Sign out, and no Sign out anywhere else.
      await page.locator('ef-profile .avatar').click();
      await page.waitForFunction(() => {
        const menu = document.querySelector('ef-profile').shadowRoot.querySelector('.menu');
        return menu && !menu.hidden && [...menu.querySelectorAll('a')].some((el) => el.textContent.trim() === 'Users');
      }, null, { timeout: 5000 }).catch(() => problems.push('no Users in the avatar menu'));
      const signOuts = await page.evaluate(() => {
        const visible = (el) => el.getClientRects().length > 0;
        const isSignOut = (el) => el.textContent.trim() === 'Sign out' && visible(el);
        const menu = document.querySelector('ef-profile').shadowRoot.querySelector('.menu');
        const all = [...document.querySelectorAll('ef-profile')].flatMap((el) => [...el.shadowRoot.querySelectorAll('a, button')])
          .concat([...document.querySelectorAll('a, button')]).filter(isSignOut);
        return { inMenu: all.filter((el) => menu.contains(el)).length, elsewhere: all.filter((el) => !menu.contains(el)).length };
      });
      if (signOuts.inMenu !== 1) problems.push(`${signOuts.inMenu} Sign out in the avatar menu`);
      if (signOuts.elsewhere) problems.push(`${signOuts.elsewhere} Sign out outside the avatar menu`);
    } catch (err) {
      problems.push(err.message.split('\n')[0]);
    }
    await page.close();
    if (problems.length) failed = true;
    console.log(`${problems.length ? 'FAIL' : 'ok  '} ${String(width).padStart(4)} ${path}${problems.length ? `: ${problems.join('; ')}` : ''}`);
  }
  await context.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
