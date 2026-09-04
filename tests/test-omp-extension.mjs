import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

import extension, {
  normalizeAgentName,
  renameAgent,
  sanitizeTitle,
} from "../scripts/herdr-agent-session-title-omp.mjs";

assert.equal(sanitizeTitle("  hello\u0000\tworld  "), "hello world");
assert.equal(normalizeAgentName("Feature: OMP titles"), "feature-omp-titles");
assert.equal(normalizeAgentName("123 Über_task!!!\nNext"), "session-123-ber-task-next");
assert.equal(normalizeAgentName("x".repeat(80)), "x".repeat(32));
assert.equal(normalizeAgentName("\u0000\t"), undefined);

let sessionTitle = "";
const handlers = new Map();
extension({
  getSessionName: () => sessionTitle,
  on: (event, handler) => handlers.set(event, handler),
});
assert.deepEqual([...handlers.keys()], ["input", "session_stop"]);
const onInput = handlers.get("input");
const onSessionStop = handlers.get("session_stop");
assert.equal(typeof onInput, "function");
assert.equal(typeof onSessionStop, "function");

const originalEnvironment = {
  HERDR_ENV: process.env.HERDR_ENV,
  HERDR_PANE_ID: process.env.HERDR_PANE_ID,
  HERDR_SOCKET_PATH: process.env.HERDR_SOCKET_PATH,
};
const restoreEnvironment = () => {
  for (const [name, value] of Object.entries(originalEnvironment)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
};

const startServer = async (socketPath) => {
  let resolveRequest;
  const requestReceived = new Promise((resolve) => {
    resolveRequest = resolve;
  });
  const server = net.createServer((client) => {
    let input = "";
    client.setEncoding("utf8");
    client.on("data", (chunk) => {
      input += chunk;
      if (!input.endsWith("\n")) return;
      resolveRequest(input);
      client.end('{"id":"test","result":{"type":"ok"}}\n');
    });
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, resolve);
  });
  return {
    requestReceived,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
};

const waitForRequest = (request, failureMessage) =>
  new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(failureMessage)), 2_000);
    request.then(
      (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
      (error) => {
        clearTimeout(timeout);
        reject(error);
      },
    );
  });

const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "herdr-omp-extension-"));
try {
  delete process.env.HERDR_ENV;
  delete process.env.HERDR_PANE_ID;
  delete process.env.HERDR_SOCKET_PATH;
  sessionTitle = "outside herdr";
  await onSessionStop();

  const missingSocket = path.join(tempDirectory, "missing.sock");
  assert.equal(
    await renameAgent("socket failure", {
      HERDR_ENV: "1",
      HERDR_PANE_ID: "%7",
      HERDR_SOCKET_PATH: missingSocket,
    }),
    false,
  );

  const socketPath = path.join(tempDirectory, "herdr.sock");
  const firstServer = await startServer(socketPath);

  process.env.HERDR_ENV = "1";
  process.env.HERDR_PANE_ID = "%42";
  process.env.HERDR_SOCKET_PATH = socketPath;
  sessionTitle = "123 OMP: Session Title";
  await onSessionStop();

  const rawRequest = await firstServer.requestReceived;
  assert.equal(rawRequest.split("\n").length, 2, rawRequest);
  const request = JSON.parse(rawRequest);
  assert.equal(request.method, "agent.rename");
  assert.deepEqual(request.params, {
    target: "%42",
    name: "session-123-omp-session-title",
  });
  assert.match(request.id, /^plugin:herdr-agent-session-title:\d+:\d{6}$/);

  await firstServer.close();

  const delayedSocketPath = path.join(tempDirectory, "herdr-delayed.sock");
  const delayedServer = await startServer(delayedSocketPath);
  process.env.HERDR_SOCKET_PATH = delayedSocketPath;
  sessionTitle = "";
  const timerContext = {
    setTimeout: (callback, delay) => setTimeout(callback, delay),
    clearTimer: (timer) => clearTimeout(timer),
  };
  await onSessionStop(undefined, timerContext);
  setTimeout(() => {
    sessionTitle = "Generated after session stop";
  }, 150);

  const delayedRawRequest = await waitForRequest(
    delayedServer.requestReceived,
    "generated title was not synchronized",
  );
  assert.deepEqual(JSON.parse(delayedRawRequest).params, {
    target: "%42",
    name: "generated-after-session-stop",
  });
  await delayedServer.close();

  const renameSocketPath = path.join(tempDirectory, "herdr-rename.sock");
  const renameServer = await startServer(renameSocketPath);
  process.env.HERDR_SOCKET_PATH = renameSocketPath;
  sessionTitle = "Old title";
  await onInput({ text: "/rename Manual OMP Name" }, timerContext);
  setTimeout(() => {
    sessionTitle = "Manual OMP Name";
  }, 150);

  const renameRawRequest = await waitForRequest(
    renameServer.requestReceived,
    "/rename title was not synchronized",
  );
  assert.deepEqual(JSON.parse(renameRawRequest).params, {
    target: "%42",
    name: "manual-omp-name",
  });
  await renameServer.close();
} finally {
  restoreEnvironment();
  fs.rmSync(tempDirectory, { recursive: true, force: true });
}

console.log("test-omp-extension: OK");
