const { once } = require('node:events');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { WebSocketServer } = require('ws');

const stickyCookieName = 'gitWiggum_ha_node';
const autoRefreshClientScript = fs.readFileSync(
  path.resolve(__dirname, '../../static/ihp-auto-refresh-htmx.js'),
  'utf8',
);

function parseCookies(cookieHeader = '') {
  return cookieHeader
    .split(';')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .reduce((cookies, entry) => {
      const separatorIndex = entry.indexOf('=');
      if (separatorIndex === -1) {
        return cookies;
      }

      const key = entry.slice(0, separatorIndex).trim();
      const value = entry.slice(separatorIndex + 1).trim();
      cookies[key] = value;
      return cookies;
    }, {});
}

function createNodeState(name) {
  return {
    name,
    draining: false,
    httpRequests: 0,
    websocketRequests: 0,
    sessions: new Map(),
  };
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderMorphdomStub() {
  return `
    window.morphdom = function (fromNode, toNode, options) {
      if (!fromNode || !toNode) {
        return fromNode;
      }

      if (fromNode === document.body) {
        document.body.innerHTML = toNode.innerHTML;
        return document.body;
      }

      if (options && options.childrenOnly) {
        fromNode.innerHTML = toNode.innerHTML;
        return fromNode;
      }

      fromNode.innerHTML = toNode.innerHTML;
      Array.prototype.slice.call(toNode.attributes).forEach(function (attribute) {
        fromNode.setAttribute(attribute.name, attribute.value);
      });
      return fromNode;
    };
  `;
}

function renderFixtureHtml({ nodeName, sessionId, socketNodeText, includeScripts }) {
  const scripts = includeScripts
    ? `
      <script>${renderMorphdomStub()}</script>
      <script>${autoRefreshClientScript}</script>
    `
    : '';

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta property="ihp-auto-refresh-id" content="${escapeHtml(sessionId)}" />
    <title>gitWiggum HA Harness</title>
  </head>
  <body>
    <main id="fixture-root" data-node="${escapeHtml(nodeName)}">
      <h1 id="fixture-title">Served by ${escapeHtml(nodeName)}</h1>
      <p id="http-node">${escapeHtml(nodeName)}</p>
      <p id="socket-node">${escapeHtml(socketNodeText)}</p>
    </main>
    ${scripts}
  </body>
</html>`;
}

async function startHaHarness() {
  const nodes = {
    'web-a': createNodeState('web-a'),
    'web-b': createNodeState('web-b'),
  };

  function listHealthyNodes() {
    return Object.values(nodes).filter((node) => !node.draining);
  }

  function chooseNode(preferredNodeName) {
    if (
      preferredNodeName &&
      Object.prototype.hasOwnProperty.call(nodes, preferredNodeName) &&
      !nodes[preferredNodeName].draining
    ) {
      return nodes[preferredNodeName];
    }

    const healthyNodes = listHealthyNodes();
    if (healthyNodes.length === 0) {
      return null;
    }

    return healthyNodes[0];
  }

  function snapshot() {
    return {
      nodes: Object.fromEntries(
        Object.entries(nodes).map(([name, node]) => [
          name,
          {
            draining: node.draining,
            httpRequests: node.httpRequests,
            websocketRequests: node.websocketRequests,
            activeSessions: node.sessions.size,
            sessionIds: Array.from(node.sessions.keys()).sort(),
          },
        ]),
      ),
    };
  }

  function closeNodeSessions(nodeName, closeCode = 1012, reason = 'draining') {
    const node = nodes[nodeName];
    if (!node) {
      throw new Error(`Unknown node: ${nodeName}`);
    }

    for (const socket of node.sessions.values()) {
      socket.close(closeCode, reason);
    }
  }

  const server = http.createServer((request, response) => {
    const requestUrl = new URL(request.url, 'http://127.0.0.1');

    if (requestUrl.pathname === '/healthz') {
      response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('ok');
      return;
    }

    if (requestUrl.pathname === '/readyz') {
      if (listHealthyNodes().length > 0) {
        response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('ready');
      } else {
        response.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('not ready');
      }
      return;
    }

    if (requestUrl.pathname === '/favicon.ico') {
      response.writeHead(204);
      response.end();
      return;
    }

    if (requestUrl.pathname !== '/') {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('not found');
      return;
    }

    const cookies = parseCookies(request.headers.cookie);
    const node = chooseNode(cookies[stickyCookieName]);
    if (!node) {
      response.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('no healthy backends');
      return;
    }

    node.httpRequests += 1;
    const sessionId = `${node.name}-${randomUUID()}`;
    response.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'set-cookie': `${stickyCookieName}=${node.name}; Path=/; SameSite=Lax`,
    });
    response.end(
      renderFixtureHtml({
        nodeName: node.name,
        sessionId,
        socketNodeText: 'awaiting websocket',
        includeScripts: true,
      }),
    );
  });

  const webSocketServer = new WebSocketServer({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const requestUrl = new URL(request.url, 'http://127.0.0.1');
    if (requestUrl.pathname !== '/AutoRefreshWSApp') {
      socket.destroy();
      return;
    }

    const cookies = parseCookies(request.headers.cookie);
    const node = chooseNode(cookies[stickyCookieName]);
    if (!node) {
      socket.write('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    webSocketServer.handleUpgrade(request, socket, head, (webSocket) => {
      node.websocketRequests += 1;
      let sessionId = null;

      webSocket.on('message', (message) => {
        sessionId = String(message);
        node.sessions.set(sessionId, webSocket);
        webSocket.send(
          renderFixtureHtml({
            nodeName: node.name,
            sessionId,
            socketNodeText: node.name,
            includeScripts: false,
          }),
        );
      });

      webSocket.on('close', () => {
        if (sessionId) {
          node.sessions.delete(sessionId);
        }
      });
    });
  });

  server.listen(0, '127.0.0.1');
  await once(server, 'listening');

  const address = server.address();
  if (!address || typeof address === 'string') {
    throw new Error('Failed to determine the HA harness port.');
  }

  const baseUrl = `http://127.0.0.1:${address.port}`;

  return {
    baseUrl,
    stickyCookieName,
    state: snapshot,
    drain(nodeName) {
      const node = nodes[nodeName];
      if (!node) {
        throw new Error(`Unknown node: ${nodeName}`);
      }

      node.draining = true;
      closeNodeSessions(nodeName);
    },
    undrain(nodeName) {
      const node = nodes[nodeName];
      if (!node) {
        throw new Error(`Unknown node: ${nodeName}`);
      }

      node.draining = false;
    },
    reset() {
      Object.keys(nodes).forEach((nodeName) => {
        nodes[nodeName].draining = false;
        nodes[nodeName].httpRequests = 0;
        nodes[nodeName].websocketRequests = 0;
        closeNodeSessions(nodeName, 1001, 'reset');
      });
    },
    async stop() {
      Object.keys(nodes).forEach((nodeName) => {
        closeNodeSessions(nodeName, 1001, 'shutdown');
      });
      await new Promise((resolve) => webSocketServer.close(resolve));
      await new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    },
  };
}

module.exports = {
  startHaHarness,
};
