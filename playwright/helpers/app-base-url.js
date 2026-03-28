const { execFileSync } = require('node:child_process');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '../..');
const explicitBaseUrl = process.env.PLAYWRIGHT_BASE_URL;
const configuredPort = (process.env.PORT || '').trim();
const fallbackBaseUrl =
  configuredPort === '' ? 'http://127.0.0.1:8000' : `http://127.0.0.1:${configuredPort}`;

function run(command, args) {
  try {
    return execFileSync(command, args, {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return '';
  }
}

function listChildPids(parentPid) {
  const output = run('pgrep', ['-P', String(parentPid)]);
  if (output === '') {
    return [];
  }

  return output
    .split(/\s+/)
    .map((value) => value.trim())
    .filter(Boolean);
}

function listDescendantPids(rootPid) {
  const result = [];
  const queue = [String(rootPid)];

  while (queue.length > 0) {
    const pid = queue.shift();
    const childPids = listChildPids(pid);
    result.push(...childPids);
    queue.push(...childPids);
  }

  return result;
}

function findRepoRunDevServerPid() {
  const output = run('pgrep', ['-x', 'RunDevServer']);
  if (output === '') {
    return null;
  }

  const runDevServerPids = output
    .split(/\s+/)
    .map((value) => value.trim())
    .filter(Boolean);

  for (const pid of runDevServerPids) {
    const processEnv = run('ps', ['eww', '-p', pid]);
    if (processEnv.includes(`PWD=${repoRoot}`) || processEnv.includes(`OLDPWD=${repoRoot}`)) {
      return pid;
    }
  }

  return null;
}

function findListeningPort(pid) {
  const output = run('lsof', ['-Pan', '-p', String(pid), '-iTCP', '-sTCP:LISTEN']);
  const match = output.match(/TCP\s+(?:127\.0\.0\.1|\*):(\d+)\s+\(LISTEN\)/);
  return match ? match[1] : null;
}

function canReachUrl(url) {
  try {
    execFileSync('curl', ['-fsS', '-o', '/dev/null', '--max-time', '2', url], {
      cwd: repoRoot,
      stdio: ['ignore', 'ignore', 'ignore'],
    });
    return true;
  } catch {
    return false;
  }
}

function resolveAppBaseUrl() {
  if (explicitBaseUrl && canReachUrl(explicitBaseUrl)) {
    return explicitBaseUrl;
  }

  const runDevServerPid = findRepoRunDevServerPid();
  if (runDevServerPid === null) {
    return fallbackBaseUrl;
  }

  const candidatePids = [runDevServerPid, ...listDescendantPids(runDevServerPid)];
  for (const pid of candidatePids) {
    const port = findListeningPort(pid);
    if (port !== null) {
      return `http://127.0.0.1:${port}`;
    }
  }

  return fallbackBaseUrl;
}

function resolveConfiguredPublicBaseUrl() {
  const configuredHostname = (process.env.APP_HOSTNAME || '').trim();
  if (configuredHostname === '') {
    throw new Error('APP_HOSTNAME must be set');
  }

  const defaultScheme = (process.env.IHP_ENV || '').trim() === 'Production' ? 'https://' : 'http://';
  return `${defaultScheme}${configuredHostname}`.replace(/\/+$/, '');
}

module.exports = {
  resolveAppBaseUrl,
  resolveConfiguredPublicBaseUrl,
};
