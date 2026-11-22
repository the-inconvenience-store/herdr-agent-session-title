import net from "node:net";

const SOURCE = "plugin:herdr-agent-session-title";
const MAX_TITLE_CHARS = 120;
const SOCKET_TIMEOUT_MS = 500;
const RECONCILE_INTERVAL_MS = 1_000;

export function sanitizeTitle(title) {
  if (typeof title !== "string") return undefined;
  const cleaned = title
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned ? cleaned.slice(0, MAX_TITLE_CHARS) : undefined;
}

export function normalizeAgentName(title) {
  const cleaned = sanitizeTitle(title);
  if (!cleaned) return undefined;

  let normalized = cleaned
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/[-_]+/g, "-")
    .replace(/^[-_]+|[-_]+$/g, "")
    .slice(0, 32)
    .replace(/[-_]+$/g, "");

  if (!normalized || !/^[a-z]/.test(normalized)) {
    normalized = `session-${normalized}`.slice(0, 32).replace(/[-_]+$/g, "");
  }
  return normalized || undefined;
}

export function renameAgent(title, environment = process.env) {
  if (environment.HERDR_ENV !== "1") return Promise.resolve(false);

  const paneId = environment.HERDR_PANE_ID;
  const socketPath = environment.HERDR_SOCKET_PATH;
  const name = normalizeAgentName(title);
  if (!paneId || !socketPath || !name) return Promise.resolve(false);

  const request = {
    id: `${SOURCE}:${Date.now()}:${Math.floor(Math.random() * 1_000_000)
      .toString()
      .padStart(6, "0")}`,
    method: "agent.rename",
    params: {
      target: paneId,
      name,
    },
  };
  const payload = `${JSON.stringify(request)}\n`;

  return new Promise((resolve) => {
    const client = net.createConnection({ path: socketPath });
    let settled = false;

    const finish = (renamed) => {
      if (settled) return;
      settled = true;
      client.destroy();
      resolve(renamed);
    };

    client.setTimeout(SOCKET_TIMEOUT_MS);
    client.on("connect", () => client.write(payload));
    client.on("data", (chunk) => {
      if (chunk.includes(10)) finish(true);
    });
    client.on("end", () => finish(true));
    client.on("close", () => finish(true));
    client.on("timeout", () => finish(false));
    client.on("error", () => finish(false));
  });
}

/**
 * Mirrors the title of the session shown in this opencode TUI into the herdr
 * agent name. Returns a function that stops the synchronization.
 *
 * The source of truth is the public session store: the routed session's root
 * is read with `data.session.root`, and its title with `data.session.get`.
 * A new opencode session has no title until one is generated or set, so an
 * untitled session is skipped. The `session.renamed` event is only an
 * accelerator that lets a rename land immediately instead of on the next
 * once-per-second check; the check alone is sufficient if that event changes.
 * The store applies a rename just after the event listeners run, so the event
 * triggers a check on the next turn of the event loop instead of a read inside
 * the callback, which would still see the old title.
 */
export function startTitleSync(api, {
  environment = process.env,
  rename = renameAgent,
  schedule = globalThis.setInterval,
  cancel = globalThis.clearInterval,
  defer = globalThis.setTimeout,
  undefer = globalThis.clearTimeout,
} = {}) {
  if (environment.HERDR_ENV !== "1") return () => {};

  let sent;
  let shown;
  let queue = Promise.resolve();
  const deferred = new Set();

  const currentRoot = () => {
    const route = api.ui.router.current();
    if (route?.type !== "session" || typeof route.sessionID !== "string") return undefined;
    const root = api.data.session.root(route.sessionID);
    return typeof root === "string" && root ? root : route.sessionID;
  };

  const publish = (root, title) => {
    const clean = sanitizeTitle(title);
    if (!clean) return;
    const key = `${root}\n${clean}`;
    if (key === sent) return;
    // Claim the key before the asynchronous send so overlapping triggers do
    // not duplicate it; a failed delivery releases it for the next check.
    sent = key;
    queue = queue.then(async () => {
      let delivered = false;
      try {
        delivered = await rename(clean, environment);
      } catch {
        // A title integration must never disturb opencode.
      }
      if (!delivered && sent === key) sent = undefined;
    });
  };

  const reconcile = () => {
    try {
      const root = currentRoot();
      // Like the OMP integration, a session that comes into view sends its
      // title again, even if it is the one sent last, so the name is
      // re-asserted after visiting another session or the home screen.
      if (root !== shown) {
        shown = root;
        sent = undefined;
      }
      if (root) publish(root, api.data.session.get(root)?.title);
    } catch {
      // A title integration must never disturb opencode.
    }
  };

  const stopListening = api.data.listen(({ details } = {}) => {
    if (details?.type !== "session.renamed") return;
    const check = defer(() => {
      deferred.delete(check);
      reconcile();
    }, 0);
    deferred.add(check);
  });
  const timer = schedule(reconcile, RECONCILE_INTERVAL_MS);
  reconcile();

  return () => {
    cancel(timer);
    for (const pending of deferred) undefer(pending);
    deferred.clear();
    stopListening?.();
  };
}

export default {
  id: "herdr.agent-session-title",
  setup(api) {
    try {
      return startTitleSync(api);
    } catch {
      return () => {};
    }
  },
};
