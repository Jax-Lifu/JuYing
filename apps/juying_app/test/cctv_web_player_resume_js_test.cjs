const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

// Execute the shipped document script with a controllable media element. No
// network, browser installation, or copy of the restoration logic is needed.
const source = fs.readFileSync(
  path.join(
    __dirname,
    "../lib/features/player/presentation/cctv_official_web_player_page.dart",
  ),
  "utf8",
);
const template = source
  .split("const String _playerOnlyDocumentScript = r'''")[1]
  .split("''';")[0];

function fixture({ position = 120, live = false, selected = true } = {}) {
  let now = 0;
  let nextTimer = 0;
  const timers = new Map();
  const messages = [];
  class Element {
    constructor() {
      this.style = { setProperty() {} };
      this.classList = {
        add() {},
        remove() {},
        toggle() {},
        contains: () => false,
      };
      this.children = [];
      this.listeners = new Map();
      this.parts = new Map();
      this.dataset = {};
    }
    addEventListener(event, callback) {
      if (!this.listeners.has(event)) this.listeners.set(event, []);
      this.listeners.get(event).push(callback);
    }
    dispatch(event, values = {}) {
      for (const callback of this.listeners.get(event) || []) callback(values);
    }
    appendChild(child) {
      this.children.push(child);
      child.parentElement = this;
    }
    setAttribute() {}
    removeAttribute() {}
    getAttribute() {
      return null;
    }
    remove() {}
    getBoundingClientRect() {
      return { width: 640, height: 360 };
    }
    querySelector(selector) {
      if (!this.parts.has(selector)) this.parts.set(selector, new Element());
      return this.parts.get(selector);
    }
    querySelectorAll() {
      return [];
    }
  }
  class Video extends Element {
    constructor() {
      super();
      this.duration = NaN;
      this.readyState = 0;
      this.ranges = [];
      this.paused = false;
      this.seeking = false;
      this.volume = 1;
      this.muted = false;
      this.time = 0;
      this.assignments = [];
    }
    get currentTime() {
      return this.time;
    }
    set currentTime(value) {
      this.time = value;
      this.assignments.push(value);
    }
    get seekable() {
      return {
        length: this.ranges.length,
        start: (index) => this.ranges[index][0],
        end: (index) => this.ranges[index][1],
      };
    }
    play() {
      this.paused = false;
    }
    pause() {
      this.paused = true;
    }
  }
  let video = new Video();
  const quality = new Element();
  quality.textContent = "高清";
  quality.selected = selected;
  quality.getAttribute = (name) =>
    name === "aria-checked" ? String(quality.selected) : null;
  quality.click = () => {};
  const document = new Element();
  document.head = new Element();
  document.body = new Element();
  document.documentElement = new Element();
  document.body.appendChild(video);
  document.createElement = () => new Element();
  document.getElementById = (id) =>
    [...document.head.children, ...document.body.children].find(
      (element) => element.id === id,
    ) || null;
  document.querySelectorAll = (selector) =>
    selector.includes("vjs-menu-item")
      ? [quality]
      : selector.includes("video")
        ? [video]
        : [];
  document.querySelector = (selector) =>
    selector.includes("video")
      ? video
      : selector.startsWith("#")
        ? document.getElementById(selector.slice(1))
        : null;
  const window = new Element();
  window.top = window;
  window.self = window;
  window.chrome = {
    webview: { postMessage: (message) => messages.push(message) },
  };
  let mutation;
  const context = vm.createContext({
    window,
    document,
    HTMLMediaElement: Video,
    MutationObserver: class {
      constructor(callback) {
        mutation = callback;
      }
      observe() {}
    },
    Date: { now: () => now },
    setTimeout: (callback, delay = 0) => {
      const id = ++nextTimer;
      timers.set(id, { callback, due: now + delay });
      return id;
    },
    clearTimeout: (id) => timers.delete(id),
  });
  function inject(generation = 1, target = position) {
    const values = {
      QUALITY: '"高清"',
      IS_LIVE: String(live),
      PLAYBACK_RATE: "1",
      CAN_PREVIOUS: "false",
      CAN_NEXT: "true",
      HAS_EPISODES: "true",
      VOLUME: "1",
      MUTED: "false",
      GENERATION: String(generation),
      INITIAL_POSITION: String(target),
    };
    const script = template.replace(
      /__JUYING_([A-Z_]+)__/g,
      (_, key) => values[key],
    );
    vm.runInContext(script, context);
  }
  function tick(milliseconds) {
    const until = now + milliseconds;
    for (let attempts = 0; attempts < 10000; attempts++) {
      const next = [...timers]
        .filter(([, timer]) => timer.due <= until)
        .sort((a, b) => a[1].due - b[1].due)[0];
      if (!next) {
        now = until;
        return;
      }
      timers.delete(next[0]);
      now = next[1].due;
      next[1].callback();
    }
    throw new Error("Unbounded timer loop");
  }
  function playable(duration = 600) {
    video.duration = duration;
    video.readyState = 4;
    video.ranges = [[0, duration]];
  }
  inject();
  return {
    get video() {
      return video;
    },
    quality,
    messages,
    window,
    document,
    inject,
    tick,
    playable,
    replaceVideo() {
      video = new Video();
      document.body.appendChild(video);
      mutation();
    },
  };
}

test("waits for content duration, seekable range and stable initial quality", () => {
  const f = fixture({ selected: false });
  f.tick(1500);
  assert.deepEqual(f.video.assignments, []);
  f.playable(20); // A short pre-roll cannot contain the requested position.
  f.tick(500);
  assert.deepEqual(f.video.assignments, []);
  f.playable();
  f.tick(500);
  assert.deepEqual(f.video.assignments, []);
  f.quality.selected = true;
  f.video.ranges = [[0, 90]];
  f.tick(1500);
  assert.deepEqual(f.video.assignments, []);
  f.video.ranges = [[0, 600]];
  f.tick(500);
  assert.equal(f.video.currentTime, 120);
  assert.deepEqual(f.video.assignments, [120]);
  assert.equal(
    f.messages.filter((m) => m.type === "juying:resume-applied").length,
    1,
  );
});

test("re-injection and quality replacement never restore an already consumed seek", () => {
  const f = fixture();
  f.playable();
  f.tick(2000);
  assert.equal(f.video.currentTime, 120);
  f.video.currentTime = 333;
  f.inject();
  f.window.__juyingSetQuality("高清");
  f.tick(2000);
  assert.equal(f.video.currentTime, 333);
  f.replaceVideo();
  f.playable();
  f.tick(2000);
  assert.deepEqual(f.video.assignments, []);
});

test("same video source reset before acknowledgement retries the pending restore", () => {
  const f = fixture();
  f.playable();
  for (
    let attempt = 0;
    attempt < 10 && f.video.assignments.length === 0;
    attempt++
  ) {
    f.tick(250);
  }
  assert.deepEqual(f.video.assignments, [120]);
  assert.equal(
    f.messages.filter((m) => m.type === "juying:resume-applied").length,
    0,
  );
  f.video.time = 0;
  f.video.readyState = 0;
  f.video.ranges = [];
  f.tick(250);
  f.playable();
  f.tick(750);
  assert.equal(f.video.currentTime, 120);
  assert.deepEqual(f.video.assignments, [120, 120]);
  assert.equal(
    f.messages.filter((m) => m.type === "juying:resume-applied").length,
    1,
  );
});

test("a newer generation invalidates the old pending restore", () => {
  const f = fixture();
  f.inject(2, 0);
  f.playable();
  f.tick(3000);
  assert.deepEqual(f.video.assignments, []);
  assert.equal(
    f.messages.filter((m) => m.type === "juying:resume-applied").length,
    0,
  );
});

test("user timeline input cancels restoration before metadata becomes seekable", () => {
  const f = fixture();
  const progress = f.document
    .getElementById("juying-controls")
    .querySelector(".jy-progress");
  f.video.duration = 600;
  progress.value = "50";
  progress.dispatch("input");
  assert.equal(f.video.currentTime, 30);
  f.playable();
  f.tick(3000);
  assert.deepEqual(f.video.assignments, [30]);
  assert.equal(
    f.messages.filter((m) => m.type === "juying:resume-cancelled").length,
    1,
  );
});

test("live streams and out-of-range positions do not seek", () => {
  const live = fixture({ live: true });
  live.playable();
  live.tick(61000);
  assert.deepEqual(live.video.assignments, []);
  const invalid = fixture({ position: 900 });
  invalid.playable();
  invalid.tick(61000);
  assert.deepEqual(invalid.video.assignments, []);
});
