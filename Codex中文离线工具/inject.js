// CDP injector for the Codex desktop app.
// Forces Statsig layer 72216192.enable_i18n = true so the app shell loads
// the bundled Simplified Chinese messages even without access to chatgpt.com.

const PORT = process.argv[2] || '9333';
const SDK_KEY = 'client-sYWqzCYMRkUg4DqqiZcR5DGTNl2iD7zNJY0HoeDLzxR';
const LAYER = '72216192';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getTargets() {
  const res = await fetch(`http://127.0.0.1:${PORT}/json/list`);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const list = await res.json();
  return Array.isArray(list) ? list : [];
}

function evaluate(wsUrl, expression) {
  return new Promise((resolve, reject) => {
    let ws;
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      return reject(e);
    }
    const timer = setTimeout(() => {
      try { ws.close(); } catch (e) {}
      reject(new Error('timeout'));
    }, 8000);
    ws.onopen = () => {
      ws.send(JSON.stringify({
        id: 1,
        method: 'Runtime.evaluate',
        params: { expression, returnByValue: true }
      }));
    };
    ws.onmessage = (ev) => {
      let data = ev.data;
      if (typeof data !== 'string') data = String(data);
      try {
        const msg = JSON.parse(data);
        if (msg.id === 1) {
          clearTimeout(timer);
          try { ws.close(); } catch (e) {}
          if (msg.result && msg.result.exceptionDetails) return reject(new Error('evaluate exception'));
          const value = msg.result && msg.result.result ? msg.result.result.value : undefined;
          resolve(value);
        }
      } catch (e) {}
    };
    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error('websocket error'));
    };
  });
}

const PATCH = `(() => {
  const SDK_KEY = ${JSON.stringify(SDK_KEY)};
  const LAYER = ${JSON.stringify(LAYER)};
  const g = window.__STATSIG__;
  const client = g && g.instance ? g.instance(SDK_KEY) : null;
  if (!client) return 'NO_CLIENT';
  const orig = client.getLayer.bind(client);
  client.getLayer = (name, fb) => {
    const layer = orig(name, fb);
    if (name === LAYER) {
      const baseGet = layer && typeof layer.get === 'function' ? layer.get.bind(layer) : null;
      return Object.assign({}, layer, {
        get: (key, dflt) => {
          if (key === 'enable_i18n') return true;
          if (key === 'locale_source') return 'IDE';
          return baseGet ? baseGet(key, dflt) : dflt;
        }
      });
    }
    return layer;
  };
  try { client.$emt({ name: 'values_updated', status: client.loadingStatus, values: client.getContext().values }); } catch (e) {}
  return 'PATCHED';
})()`;

const VERIFY = `(() => {
  const g = window.__STATSIG__;
  const c = g && g.instance ? g.instance(${JSON.stringify(SDK_KEY)}) : null;
  if (!c) return 'NO_CLIENT';
  return c.getLayer(${JSON.stringify(LAYER)}).get('enable_i18n', false);
})()`;

async function main() {
  let lastError = null;
  for (let attempt = 0; attempt < 30; attempt++) {
    let targets;
    try {
      targets = await getTargets();
    } catch (e) {
      lastError = e;
      await sleep(1000);
      continue;
    }
    const pages = targets.filter(
      (t) => t.webSocketDebuggerUrl && (t.type === 'page' || t.type === 'webview')
    );
    for (const t of pages) {
      try {
        const result = await evaluate(t.webSocketDebuggerUrl, PATCH);
        if (result === 'PATCHED') {
          console.log('PATCHED on ' + (t.url || 'unknown'));
          try {
            const check = await evaluate(t.webSocketDebuggerUrl, VERIFY);
            console.log('VERIFY enable_i18n = ' + check);
          } catch (e) {}
          process.exit(0);
        }
      } catch (e) {
        lastError = e;
      }
    }
    await sleep(1000);
  }
  console.error('INJECT FAILED: ' + (lastError ? lastError.message : 'no patchable target'));
  process.exit(1);
}

main();
