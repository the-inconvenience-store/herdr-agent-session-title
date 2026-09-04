import net from "node:net";

const SOURCE = "plugin:herdr-agent-session-title";
const MAX_TITLE_CHARS = 120;
const SOCKET_TIMEOUT_MS = 500;
const TITLE_POLL_INTERVAL_MS = 100;
const TITLE_POLL_TIMEOUT_MS = 5_000;

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

export default function herdrAgentSessionTitle(pi) {
  let pendingTitlePoll;

  const stopTitlePoll = (ctx) => {
    if (pendingTitlePoll === undefined) return;
    ctx.clearTimer(pendingTitlePoll);
    pendingTitlePoll = undefined;
  };

  const scheduleTitlePoll = (ctx, previousTitle) => {
    if (process.env.HERDR_ENV !== "1") return;
    stopTitlePoll(ctx);

    const deadline = Date.now() + TITLE_POLL_TIMEOUT_MS;
    const poll = async () => {
      const title = pi.getSessionName();
      if (title && title !== previousTitle) {
        stopTitlePoll(ctx);
        await renameAgent(title);
        return;
      }
      if (Date.now() >= deadline) {
        pendingTitlePoll = undefined;
        return;
      }
      pendingTitlePoll = ctx.setTimeout(poll, TITLE_POLL_INTERVAL_MS);
    };
    pendingTitlePoll = ctx.setTimeout(poll, TITLE_POLL_INTERVAL_MS);
  };

  pi.on("input", (event, ctx) => {
    try {
      if (/^\/rename(?:\s|$)/.test(event.text.trim())) {
        scheduleTitlePoll(ctx, pi.getSessionName());
      }
    } catch {
      // Input handling must remain transparent to OMP.
    }
  });

  pi.on("session_stop", async (_event, ctx) => {
    try {
      if (process.env.HERDR_ENV !== "1") return;
      const title = pi.getSessionName();
      if (title) {
        stopTitlePoll(ctx);
        await renameAgent(title);
      } else if (!process.env.PI_NO_TITLE) {
        scheduleTitlePoll(ctx, undefined);
      }
    } catch {
      // A title integration must never disturb OMP session settlement.
    }
  });
}
