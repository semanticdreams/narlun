const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const webRoot = path.resolve(repoRoot, 'ui', 'build', 'web');

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitUntil(predicate, { timeout = 15_000, interval = 100, description = 'condition' } = {}) {
  const deadline = Date.now() + timeout;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const result = await predicate();
      if (result) {
        return result;
      }
    } catch (error) {
      lastError = error;
    }
    await wait(interval);
  }
  if (lastError) {
    throw new Error(`Timed out waiting for ${description}: ${lastError}`);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

function findFreePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close((error) => {
        if (error) {
          reject(error);
        } else {
          resolve(port);
        }
      });
    });
    server.on('error', reject);
  });
}

function stopProcess(process) {
  return new Promise((resolve) => {
    if (!process || process.killed) {
      resolve();
      return;
    }
    const timer = setTimeout(() => {
      process.kill('SIGKILL');
    }, 5_000);
    process.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
    process.kill('SIGTERM');
  });
}

class LiveHarness {
  constructor() {
    this.tempDir = null;
    this.redisProcess = null;
    this.backendProcess = null;
    this.redisPort = null;
    this.backendPort = null;
  }

  get rootUrl() {
    return `http://127.0.0.1:${this.backendPort}`;
  }

  get apiUrl() {
    return `${this.rootUrl}/api`;
  }

  async start() {
    this.tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'narlun-pw-'));
    this.redisPort = await findFreePort();
    this.backendPort = await findFreePort();

    this.redisProcess = spawn(
      'redis-server',
      ['--save', '', '--appendonly', 'no', '--port', `${this.redisPort}`, '--dir', this.tempDir],
      { stdio: 'ignore' },
    );
    await waitUntil(() => this.portIsOpen(this.redisPort), {
      timeout: 10_000,
      description: 'redis port',
    });
    await this.startBackend();
  }

  async startBackend() {
    const settingsPath = path.join(this.tempDir, 'app_settings.py');
    fs.writeFileSync(
      settingsPath,
      [
        `PORT = ${this.backendPort}`,
        `REDIS_URL = "redis://127.0.0.1:${this.redisPort}/0"`,
        'SECRET_KEY = "playwright-test-secret"',
        'SENTRY_DSN = ""',
        `WEB_ROOT = r"${webRoot}"`,
        '',
      ].join('\n'),
    );

    this.backendProcess = spawn(
      'uv',
      ['run', 'python', '-m', 'app.app'],
      {
        cwd: repoRoot,
        env: { ...process.env, APP_SETTINGS: settingsPath },
        stdio: 'ignore',
      },
    );
    await waitUntil(() => this.backendReady(), {
      timeout: 20_000,
      description: 'backend readiness',
    });
  }

  async stopBackend() {
    await stopProcess(this.backendProcess);
    this.backendProcess = null;
  }

  async restartBackend() {
    await this.stopBackend();
    await this.startBackend();
  }

  async close() {
    await stopProcess(this.backendProcess);
    await stopProcess(this.redisProcess);
    if (this.tempDir) {
      fs.rmSync(this.tempDir, { recursive: true, force: true });
    }
  }

  async backendReady() {
    try {
      const response = await fetch(`${this.apiUrl}/users/me`);
      return response.status === 200;
    } catch {
      return false;
    }
  }

  portIsOpen(port) {
    return new Promise((resolve) => {
      const socket = net.connect({ host: '127.0.0.1', port });
      socket.once('connect', () => {
        socket.end();
        resolve(true);
      });
      socket.once('error', () => {
        resolve(false);
      });
    });
  }
}

class BackendClient {
  constructor(apiUrl) {
    this.apiUrl = apiUrl.replace(/\/$/, '');
  }

  async signupGuest(username) {
    const response = await this.request('POST', '/users/signup', {
      body: { username },
      expectedStatus: 200,
    });
    return new BackendSession(this, username, response.json, response.cookie);
  }

  async getMe(jwtCookie) {
    const response = await this.request('GET', '/users/me', {
      cookie: jwtCookie,
      expectedStatus: 200,
    });
    return response.json;
  }

  async joinUser(jwtCookie, userId) {
    const response = await this.request('POST', '/social/join-user', {
      cookie: jwtCookie,
      body: { user_id: userId },
      expectedStatus: 200,
    });
    return response.json;
  }

  async sendMessage(jwtCookie, roomId, body) {
    const response = await this.request('POST', '/social/send-message', {
      cookie: jwtCookie,
      body: { room_id: roomId, body },
      expectedStatus: 200,
    });
    return response.json;
  }

  async checkin(jwtCookie, latitude, longitude) {
    const response = await this.request('POST', '/social/checkin', {
      cookie: jwtCookie,
      body: { lat: latitude, lon: longitude },
      expectedStatus: 200,
    });
    return response.json;
  }

  async signout(jwtCookie) {
    await this.request('POST', '/users/signout', {
      cookie: jwtCookie,
      expectedStatus: 204,
    });
  }

  async request(method, pathName, { cookie, body, expectedStatus }) {
    const headers = {};
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }
    if (cookie) {
      headers.Cookie = cookie;
    }
    const response = await fetch(`${this.apiUrl}${pathName}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (response.status !== expectedStatus) {
      throw new Error(`${method} ${pathName} returned ${response.status}: ${await response.text()}`);
    }
    const text = await response.text();
    const setCookie = response.headers.get('set-cookie');
    return {
      json: text ? JSON.parse(text) : null,
      cookie: setCookie ? setCookie.split(';', 1)[0] : null,
    };
  }
}

class BackendSession {
  constructor(client, username, user, jwtCookie) {
    this.client = client;
    this.username = username;
    this.user = user;
    this.jwtCookie = jwtCookie;
  }

  async joinUser(userId) {
    return this.client.joinUser(this.jwtCookie, userId);
  }

  async sendMessage(roomId, body) {
    return this.client.sendMessage(this.jwtCookie, roomId, body);
  }

  async checkin(latitude, longitude) {
    return this.client.checkin(this.jwtCookie, latitude, longitude);
  }

  async signout() {
    return this.client.signout(this.jwtCookie);
  }
}

function randomUsername(prefix) {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 10_000)}`;
}

module.exports = {
  BackendClient,
  LiveHarness,
  randomUsername,
  waitUntil,
};
