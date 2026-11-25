import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [, , executable, expectedVersion, demoDirectory] = process.argv;
assert(executable && expectedVersion && demoDirectory, 'Pass the executable, expected version and demo directory');
const resolveDemo = createRequire(join(resolve(demoDirectory), 'package.json'));
const { chromium } = resolveDemo('playwright-core');
const { default: puppeteer } = await import(pathToFileURL(resolveDemo.resolve('puppeteer-core')).href);
const exec = promisify(execFile);
const html = '<!doctype html><title>Lightpanda Windows smoke</title>'
    + '<h1>Windows x64 smoke</h1><p id="value">before</p>'
    + '<button id="action" onclick="document.querySelector(\'#value\').textContent=\'clicked\'">Click</button>'
    + '<script>document.querySelector("#value").textContent="script executed";</script>';
const fixtures = createServer((request, response) => {
    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.end(request.url === '/second' ? '<title>Second</title><p>second page</p>' : html);
});
fixtures.listen(0, '127.0.0.1');
await once(fixtures, 'listening');
const fixtureUrl = 'http://127.0.0.1:' + fixtures.address().port;

const portProbe = createServer();
portProbe.listen(0, '127.0.0.1');
await once(portProbe, 'listening');
const port = portProbe.address().port;
portProbe.close();
await once(portProbe, 'close');

let browserServer;
let serverStderr = '';
try {
    const options = { timeout: 30000, windowsHide: true };
    const version = await exec(executable, ['version'], options);
    assert.equal(version.stdout.trim(), expectedVersion);
    for (const mode of ['html', 'markdown']) {
        const result = await exec(executable, ['fetch', '--dump', mode, fixtureUrl], options);
        assert.match(result.stdout, /Windows x64 smoke/);
        assert.match(result.stdout, /script executed/);
        console.log('PASS fetch --dump ' + mode);
    }

    const httpEndpoint = 'http://127.0.0.1:' + port;
    browserServer = spawn(executable, ['serve', '--host', '127.0.0.1', '--port', String(port)], {
        windowsHide: true,
        stdio: ['ignore', 'ignore', 'pipe'],
    });
    browserServer.stderr.on('data', (chunk) => { serverStderr += chunk; });
    let discovery;
    for (let i = 0; i < 50; i++) {
        if (browserServer.exitCode !== null) break;
        try {
            const r = await fetch(httpEndpoint + '/json/version', { signal: AbortSignal.timeout(750) });
            if (r.ok) {
                discovery = await r.json();
                break;
            }
        } catch {}
        await delay(100);
    }
    assert(discovery?.webSocketDebuggerUrl, 'Missing CDP discovery endpoint');

    const puppeteerBrowser = await puppeteer.connect({ browserWSEndpoint: discovery.webSocketDebuggerUrl, protocolTimeout: 15000 });
    try {
        const context = await puppeteerBrowser.createBrowserContext();
        const page = await context.newPage();
        const second = await context.newPage();
        await page.goto(fixtureUrl);
        await second.goto(fixtureUrl + '/second');
        assert.equal(await page.$eval('#value', (element) => element.textContent), 'script executed');
        assert.equal(await second.title(), 'Second');
        await page.click('#action');
        assert.equal(await page.$eval('#value', (element) => element.textContent), 'clicked');
        await context.close();
    } finally {
        await puppeteerBrowser.disconnect();
    }
    console.log('PASS Puppeteer CDP navigation, script, click and two pages');

    const playwrightBrowser = await chromium.connectOverCDP(httpEndpoint, { timeout: 15000 });
    try {
        const context = await playwrightBrowser.newContext();
        const page = await context.newPage();
        await page.goto(fixtureUrl, { timeout: 15000 });
        assert.equal(await page.locator('#value').textContent(), 'script executed');
        await context.close();
    } finally {
        await playwrightBrowser.close();
    }
    console.log('PASS Playwright CDP navigation and DOM');
} catch (error) {
    console.error(serverStderr);
    throw error;
} finally {
    if (browserServer && browserServer.exitCode === null && browserServer.signalCode === null) {
        browserServer.kill();
        await once(browserServer, 'exit');
    }
    fixtures.close();
}
