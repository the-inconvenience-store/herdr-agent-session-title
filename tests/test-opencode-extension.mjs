import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

import plugin, {
  normalizeAgentName,
  renameAgent,
  sanitizeTitle,
  startTitleSync,
} from "../scripts/herdr-agent-session-title-opencode.mjs";

assert.equal(sanitizeTitle("  hello\u0000\tworld  "), "hello world");
assert.equal(normalizeAgentName("Feature: opencode titles"), "feature-opencode-titles");
assert.equal(normalizeAgentName("123 Über_task!!!\nNext"), "session-123-ber-task-next");
assert.equal(normalizeAgentName("x".repeat(80)), "x".repeat(32));
assert.equal(normalizeAgentName("\u0000\t"), undefined);
assert.equal(sanitizeTitle(undefined), undefined);

assert.equal(typeof plugin.id, "string");
assert.equal(typeof plugin.setup, "function");

// A fake of the opencode TUI plugin context, limited to the surface the
// plugin reads: the router, session get/root, and the data event stream.
function createApi() {
  const sessions = new Map();
  const listeners = new Set();
  let route = { type: "home" };
  return {
    sessions,
    setRoute(next) { route = next; },
    emit(type, data = {}) {
      for (const listener of [...listeners]) listener({ details: { type, data } });
    },
    // opencode applies a rename to its store one turn after the event listeners
    // have run (measured against opencode 2.3.2), so the event arrives while
    // the stored title is still the old one.
    rename(id, title) {
      setTimeout(() => { sessions.get(id).title = title; }, 0);
      this.emit("session.renamed", { sessionID: id, title });
    },
    emitRaw(...args) {
      for (const listener of [...listeners]) listener(...args);
    },
    listenerCount: () => listeners.size,
    ui: { router: { current: () => route } },
    data: {
      session: {
        get: (id) => sessions.get(id),
        root(id) {
          let current = id;
          while (sessions.get(current)?.parentID) current = sessions.get(current).parentID;
          return current;
        },
      },
      listen(listener) {
        listeners.add(listener);
        return () => listeners.delete(listener);
      },
    },
  };
}

const originalEnvironment = Object.fromEntries(
  ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_SOCKET_PATH"].map((key) => [key, process.env[key]]),
);
const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "herdr-opencode-extension-"));
const requests = [];
const server = net.createServer((client) => {
  let input = "";
  client.setEncoding("utf8");
  client.on("data", (chunk) => {
    input += chunk;
    if (!input.endsWith("\n")) return;
    requests.push(JSON.parse(input));
    client.end('{"id":"test","result":{"type":"ok"}}\n');
  });
});

// Drive the once-per-second check with a virtual clock so the test does not
// cost seconds of wall time. Socket requests still use the real transport.
let now = 0;
let nextTimer = 0;
const timers = new Map();
const clock = {
  schedule(callback, interval) {
    const timer = ++nextTimer;
    timers.set(timer, { callback, interval, due: now + interval });
    return timer;
  },
  cancel(timer) { timers.delete(timer); },
};
const advance = async (milliseconds) => {
  const end = now + milliseconds;
  while (true) {
    const entry = [...timers.entries()]
      .filter(([, timer]) => timer.due <= end)
      .sort((a, b) => a[1].due - b[1].due)[0];
    if (!entry) break;
    const [, timer] = entry;
    now = timer.due;
    timer.due += timer.interval;
    await timer.callback();
  }
  now = end;
};

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const settle = () => sleep(40);
const waitFor = async (condition, message) => {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await sleep(10);
  }
  assert.fail(message);
};
const expectRename = async (name) => {
  await waitFor(() => requests.length > 0, `session title ${JSON.stringify(name)} was not synchronized`);
  const request = requests.shift();
  assert.equal(request.method, "agent.rename");
  assert.deepEqual(request.params, { target: "w1:p42", name });
  assert.match(request.id, /^plugin:herdr-agent-session-title:\d+:\d{6}$/);
  await settle();
  assert.deepEqual(requests, [], "duplicate rename requests");
};
const expectNoRename = async (message) => {
  await settle();
  assert.deepEqual(requests, [], message);
};
const start = (api, options = {}) => startTitleSync(api, { ...clock, ...options });

try {
  const socketPath = path.join(tempDirectory, "herdr.sock");
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, resolve);
  });

  // Outside herdr the plugin must not even subscribe to events.
  delete process.env.HERDR_ENV;
  let api = createApi();
  api.sessions.set("ses_a", { title: "outside herdr" });
  api.setRoute({ type: "session", sessionID: "ses_a" });
  let stop = start(api);
  assert.equal(api.listenerCount(), 0);
  await advance(10_000);
  await expectNoRename("renamed outside herdr");
  stop();

  assert.equal(await renameAgent("socket failure", {
    HERDR_ENV: "1",
    HERDR_PANE_ID: "w1:p42",
    HERDR_SOCKET_PATH: path.join(tempDirectory, "missing.sock"),
  }), false);

  process.env.HERDR_ENV = "1";
  process.env.HERDR_PANE_ID = "w1:p42";
  process.env.HERDR_SOCKET_PATH = socketPath;

  // On the home screen there is no session to mirror.
  api = createApi();
  stop = start(api);
  await advance(10_000);
  await expectNoRename("renamed without a session");
  stop();

  // A resumed session synchronizes immediately, without another model turn,
  // and an unchanged title is not sent again.
  api = createApi();
  api.sessions.set("ses_a", { title: "Resumed session" });
  api.setRoute({ type: "session", sessionID: "ses_a" });
  stop = start(api);
  await expectRename("resumed-session");
  await advance(10_000);
  await expectNoRename("unchanged title must not repeatedly rename");

  // Rename Session emits an event; the title lands without waiting a second,
  // even though the store still holds the old title when the event fires.
  api.rename("ses_a", "Event rename");
  await expectRename("event-rename");
  await advance(10_000);
  await expectNoRename("the stale title must not be sent back after the event");

  // A title change with no event is still found by the periodic check.
  api.sessions.get("ses_a").title = "Polled rename";
  await advance(1_000);
  await expectRename("polled-rename");

  // Events and payloads that are not about the displayed session are ignored.
  api.sessions.set("ses_other", { title: "Other session" });
  api.emit("session.renamed", { sessionID: "ses_other", title: "Other session" });
  api.emit("session.created", { sessionID: "ses_other" });
  api.emit("session.renamed");
  api.emitRaw();
  api.emitRaw({});
  api.emitRaw({ details: null });
  await expectNoRename("unrelated events must not rename");

  // A new opencode session has no title until one is generated or set.
  api.sessions.set("ses_b", {});
  api.setRoute({ type: "session", sessionID: "ses_b" });
  await advance(30_000);
  await expectNoRename("an untitled session must not rename");
  api.sessions.get("ses_b").title = "Late generated title";
  await advance(1_000);
  await expectRename("late-generated-title");

  // Viewing a subagent session keeps using the root session's title.
  api.sessions.set("ses_child", { parentID: "ses_b", title: "Subagent title" });
  api.setRoute({ type: "session", sessionID: "ses_child" });
  await advance(10_000);
  await expectNoRename("a child session must not rename the agent");
  api.sessions.get("ses_b").title = "Root again";
  await advance(1_000);
  await expectRename("root-again");

  // Switching sessions resets deduplication, even if their titles match.
  api.setRoute({ type: "session", sessionID: "ses_a" });
  await advance(1_000);
  await expectRename("polled-rename");
  api.sessions.set("ses_c", { title: "Polled rename" });
  api.setRoute({ type: "session", sessionID: "ses_c" });
  await advance(1_000);
  await expectRename("polled-rename");

  // Leaving for the home screen keeps the last name and sends nothing.
  api.setRoute({ type: "home" });
  await advance(10_000);
  await expectNoRename("the home screen must not rename");

  // Back-to-back renames arrive in order.
  api.setRoute({ type: "session", sessionID: "ses_a" });
  await advance(1_000);
  await expectRename("polled-rename");
  api.rename("ses_a", "First");
  api.rename("ses_a", "Second");
  await waitFor(() => requests.length === 2, "both renames were not delivered");
  assert.deepEqual(requests.splice(0).map((request) => request.params.name), ["first", "second"]);

  // A session that comes back into view re-asserts its title, whether the
  // detour was an untitled session or the home screen.
  api = createApi();
  api.sessions.set("ses_a", { title: "Alpha" });
  api.sessions.set("ses_b", {});
  api.setRoute({ type: "session", sessionID: "ses_a" });
  const stopReturn = start(api);
  await expectRename("alpha");
  api.setRoute({ type: "session", sessionID: "ses_b" });
  await advance(2_000);
  await expectNoRename("an untitled session must not rename");
  api.setRoute({ type: "session", sessionID: "ses_a" });
  await advance(1_000);
  await expectRename("alpha");
  api.setRoute({ type: "home" });
  await advance(2_000);
  await expectNoRename("the home screen must not rename");
  api.setRoute({ type: "session", sessionID: "ses_a" });
  await advance(1_000);
  await expectRename("alpha");
  await advance(10_000);
  await expectNoRename("a session that stays in view must not repeat");
  stopReturn();

  // After stop() nothing reacts any more.
  stop();
  assert.equal(api.listenerCount(), 0);
  assert.equal(timers.size, 0);
  api.rename("ses_a", "After stop");
  await advance(10_000);
  await expectNoRename("renamed after stop");

  // stop() also cancels a check that a rename event has already scheduled.
  api = createApi();
  api.sessions.set("ses_a", { title: "Before stop" });
  api.setRoute({ type: "session", sessionID: "ses_a" });
  stop = start(api);
  await expectRename("before-stop");
  api.rename("ses_a", "Too late");
  stop();
  await advance(10_000);
  await expectNoRename("a pending check ran after stop");

  // A failed delivery is retried by the next check and then not repeated.
  api = createApi();
  api.sessions.set("ses_a", { title: "Flaky socket" });
  api.setRoute({ type: "session", sessionID: "ses_a" });
  const attempts = [];
  stop = start(api, {
    rename: async (title) => { attempts.push(title); return attempts.length > 1; },
  });
  await settle();
  assert.deepEqual(attempts, ["Flaky socket"]);
  await advance(1_000);
  await settle();
  assert.deepEqual(attempts, ["Flaky socket", "Flaky socket"]);
  await advance(10_000);
  await settle();
  assert.equal(attempts.length, 2, "a delivered title must not be retried");
  stop();

  // opencode must never be disturbed: API errors are swallowed and a later
  // check recovers.
  api = createApi();
  api.sessions.set("ses_a", { title: "Recovers" });
  api.setRoute({ type: "session", sessionID: "ses_a" });
  let failing = true;
  const realGet = api.data.session.get;
  api.data.session.get = (id) => {
    if (failing) throw new Error("store unavailable");
    return realGet(id);
  };
  stop = start(api);
  await advance(2_000);
  await expectNoRename("a failing store must not rename");
  failing = false;
  await advance(1_000);
  await expectRename("recovers");
  stop();

  // The exported plugin object wires the same logic to the real timers and
  // never throws into the host, even when the context is unusable.
  const realStop = plugin.setup(createApi());
  assert.equal(typeof realStop, "function");
  realStop();
  assert.equal(typeof plugin.setup({}), "function");
} finally {
  timers.clear();
  for (const [name, value] of Object.entries(originalEnvironment)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(tempDirectory, { recursive: true, force: true });
}
console.log("test-opencode-extension: OK");
