#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

function usage() {
  process.stderr.write('Usage: scripts/gitWiggum rgh capture [--base64]\n');
  process.exit(1);
}

function gitOutput(args, cwd) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim();
}

function resolveRepoContext(cwd) {
  const repoRoot = gitOutput(['rev-parse', '--show-toplevel'], cwd);
  const repoCommonDir = gitOutput(['rev-parse', '--path-format=absolute', '--git-common-dir'], cwd);
  return { repoRoot, repoCommonDir };
}

function walkJsonlFiles(rootDir) {
  if (!fs.existsSync(rootDir)) {
    return [];
  }

  const files = [];
  const stack = [rootDir];

  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        files.push(fullPath);
      }
    }
  }

  return files;
}

function findSessionFile(codexHome, threadId) {
  if (!threadId) {
    return null;
  }

  const activeSessionsDir = path.join(codexHome, 'sessions');
  const candidates = walkJsonlFiles(activeSessionsDir);
  return candidates.find((candidate) => candidate.includes(threadId)) || null;
}

function parseJsonl(filePath) {
  return fs
    .readFileSync(filePath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function extractMessageText(message) {
  const content = message?.payload?.content || [];
  return content
    .filter((item) => item.type === 'input_text' && typeof item.text === 'string')
    .map((item) => item.text.trim())
    .filter(Boolean)
    .join('\n');
}

function resolveSessionCommonDir(sessionCwd) {
  try {
    return gitOutput(['rev-parse', '--path-format=absolute', '--git-common-dir'], sessionCwd);
  } catch (_error) {
    return null;
  }
}

function selectLatestRepoSession(codexHome, currentRepoCommonDir) {
  const activeSessionsDir = path.join(codexHome, 'sessions');
  const candidates = walkJsonlFiles(activeSessionsDir)
    .map((filePath) => {
      try {
        const firstLine = fs.readFileSync(filePath, 'utf8').split('\n').find(Boolean);
        if (!firstLine) {
          return null;
        }
        const meta = JSON.parse(firstLine);
        if (meta.type !== 'session_meta') {
          return null;
        }
        const sessionCwd = meta.payload?.cwd;
        const originator = meta.payload?.originator || '';
        if (!sessionCwd || !originator.toLowerCase().includes('codex')) {
          return null;
        }
        const sessionCommonDir = resolveSessionCommonDir(sessionCwd);
        if (!sessionCommonDir || sessionCommonDir !== currentRepoCommonDir) {
          return null;
        }
        const stat = fs.statSync(filePath);
        return {
          filePath,
          updatedAt: stat.mtimeMs,
        };
      } catch (_error) {
        return null;
      }
    })
    .filter(Boolean)
    .sort((left, right) => right.updatedAt - left.updatedAt);

  return candidates[0]?.filePath || null;
}

function collectCapture(lines, sessionFile, repoRoot) {
  const sessionMeta = lines.find((entry) => entry.type === 'session_meta');
  if (!sessionMeta) {
    throw new Error(`session metadata missing in ${sessionFile}`);
  }

  const userMessages = [];
  let latestReasoning = null;

  for (const entry of lines) {
    if (entry.type !== 'response_item') {
      continue;
    }

    const payload = entry.payload || {};

    if (payload.type === 'message' && payload.role === 'user') {
      const text = extractMessageText(entry);
      if (text) {
        userMessages.push({
          timestamp: entry.timestamp,
          text,
        });
      }
    }

    if (payload.type === 'reasoning') {
      latestReasoning = {
        timestamp: entry.timestamp,
        summary: payload.summary || [],
        encrypted_content: payload.encrypted_content || null,
      };
    }
  }

  if (userMessages.length === 0) {
    throw new Error(`no user prompt found in ${sessionFile}`);
  }

  if (!latestReasoning) {
    throw new Error(`no reasoning payload found in ${sessionFile}`);
  }

  const promptMessages = userMessages.slice(-5);

  return {
    version: 1,
    source: 'codex',
    capturedAt: new Date().toISOString(),
    repoRoot,
    threadId: sessionMeta.payload?.id || null,
    threadName: sessionMeta.payload?.title || null,
    codexOriginator: sessionMeta.payload?.originator || null,
    sessionFile,
    prompt: promptMessages.map((message) => message.text).join('\n\n'),
    promptMessages,
    thinking: latestReasoning,
    rawPayload: {
      latestUserMessage: promptMessages[promptMessages.length - 1],
      latestReasoning,
    },
  };
}

function main() {
  const args = process.argv.slice(2);
  if (args.length > 1) {
    usage();
  }

  const base64Only = args[0] === '--base64';
  if (args.length === 1 && !base64Only) {
    usage();
  }

  const cwd = process.cwd();
  const codexHome = process.env.CODEX_HOME || path.join(process.env.HOME || '', '.codex');
  const threadId = process.env.CODEX_THREAD_ID || null;
  const { repoRoot, repoCommonDir } = resolveRepoContext(cwd);

  let sessionFile = findSessionFile(codexHome, threadId);
  if (!sessionFile) {
    sessionFile = selectLatestRepoSession(codexHome, repoCommonDir);
  }

  if (!sessionFile) {
    throw new Error('no matching Codex session found for this repository');
  }

  const lines = parseJsonl(sessionFile);
  const sessionMeta = lines.find((entry) => entry.type === 'session_meta');
  const sessionCwd = sessionMeta?.payload?.cwd;
  const sessionCommonDir = sessionCwd ? resolveSessionCommonDir(sessionCwd) : null;

  if (sessionCommonDir !== repoCommonDir) {
    throw new Error('the latest Codex session is not scoped to this repository');
  }

  const capture = collectCapture(lines, sessionFile, repoRoot);
  const json = JSON.stringify(capture);

  if (base64Only) {
    process.stdout.write(Buffer.from(json, 'utf8').toString('base64'));
    return;
  }

  process.stdout.write(`${JSON.stringify(capture, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
