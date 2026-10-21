const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,
  '../lib/features/player/presentation/web_media_resolver.dart'), 'utf8');
const script = source.match(/const _snifferScript = r'''([\s\S]*?)''';/)[1];

function browser({ videos = [], entries = [] } = {}) {
  const messages = [];
  let response;
  class Xhr {
    open() {}
    addEventListener(_, listener) { this.listener = listener; }
    getResponseHeader() { return this.type; }
    complete(status, type, url) {
      this.status = status;
      this.type = type;
      this.responseURL = url;
      this.listener();
    }
  }
  const window = {
    chrome: { webview: { postMessage: message => messages.push(message) } },
    fetch: async () => response,
  };
  vm.runInNewContext(script, {
    window, XMLHttpRequest: Xhr, URL,
    document: {
      baseURI: 'https://player.test/watch',
      querySelectorAll: () => videos,
      addEventListener() {},
    },
    location: { href: 'https://player.test/watch' },
    navigator: { userAgent: 'fixture' },
    performance: { getEntriesByType: () => entries },
    setInterval() {},
  });
  return {
    window, Xhr, messages,
    respond(status, type, url) {
      response = { status, url, headers: { get: () => type } };
      return response;
    },
  };
}

test('failed and HTML fetches leave the session open for the actual manifest', async () => {
  const b = browser();
  b.respond(403, 'text/html', 'https://cdn.test/blocked.m3u8');
  await b.window.fetch('https://cdn.test/blocked.m3u8');
  b.respond(200, 'text/html', 'https://cdn.test/challenge.m3u8');
  await b.window.fetch('https://cdn.test/challenge.m3u8');
  assert.equal(b.messages.length, 0);
  const response = b.respond(200, 'application/vnd.apple.mpegurl',
    'https://cdn.test/master.m3u8');
  assert.equal(await b.window.fetch('https://cdn.test/master.m3u8'), response);
  assert.equal(b.messages.length, 1);
  assert.equal(b.messages[0].url, 'https://cdn.test/master.m3u8');
});

test('XHR reports only a successful response', () => {
  const b = browser();
  const bad = new b.Xhr();
  bad.open('GET', 'https://cdn.test/blocked.m3u8');
  bad.complete(403, 'text/html', 'https://cdn.test/blocked.m3u8');
  assert.equal(b.messages.length, 0);
  const good = new b.Xhr();
  good.open('GET', 'https://cdn.test/ok.mpd');
  good.complete(200, 'application/dash+xml', 'https://cdn.test/ok.mpd');
  assert.equal(b.messages[0].url, 'https://cdn.test/ok.mpd');
});

test('an unready or failed DOM video does not claim success', () => {
  const b = browser({ videos: [
    { src: 'https://cdn.test/early.mp4', readyState: 0 },
    { currentSrc: 'https://cdn.test/bad.mp4', readyState: 1, error: {} },
  ] });
  assert.equal(b.messages.length, 0);
});

test('loaded DOM media is resolved while blobs and segments are excluded', () => {
  const b = browser({ videos: [
    { currentSrc: 'blob:https://player.test/id', readyState: 1 },
    { currentSrc: 'https://cdn.test/001.m4s', readyState: 1 },
    { currentSrc: 'https://cdn.test/movie.mp4?token=fixture', readyState: 1 },
  ] });
  assert.equal(b.messages.length, 1);
  assert.equal(b.messages[0].url, 'https://cdn.test/movie.mp4?token=fixture');
});

test('failed performance entries cannot override a later loaded video', () => {
  const b = browser({ entries: [
    { name: 'https://cdn.test/blocked.m3u8', initiatorType: 'video', responseStatus: 403 },
    { name: 'https://cdn.test/unknown.m3u8', initiatorType: 'fetch', responseStatus: 200 },
    { name: 'https://cdn.test/movie.mp4', initiatorType: 'video', responseStatus: 200 },
  ] });
  assert.equal(b.messages.length, 1);
  assert.equal(b.messages[0].url, 'https://cdn.test/movie.mp4');
});
