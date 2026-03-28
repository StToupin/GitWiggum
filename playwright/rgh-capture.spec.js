const { test, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');

function run(command, args, cwd, extraEnv = {}) {
  return execFileSync(command, args, {
    cwd,
    encoding: 'utf8',
    env: {
      ...process.env,
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function resolveGitPath(cwd, gitPath) {
  return path.isAbsolute(gitPath) ? gitPath : path.join(cwd, gitPath);
}

function resolveWorktreeGitDir(cwd) {
  return resolveGitPath(cwd, run('git', ['rev-parse', '--git-dir'], cwd));
}

function resolveActiveHooksDir(cwd) {
  return resolveGitPath(cwd, run('git', ['rev-parse', '--git-path', 'hooks'], cwd));
}

function copyFeatureFiles(targetRoot) {
  fs.cpSync(path.join(repoRoot, 'scripts'), path.join(targetRoot, 'scripts'), {
    recursive: true,
  });
  fs.cpSync(path.join(repoRoot, '.githooks'), path.join(targetRoot, '.githooks'), {
    recursive: true,
  });
  fs.copyFileSync(path.join(repoRoot, 'justfile'), path.join(targetRoot, 'justfile'));
}

test('rgh installs hooks and appends codex capture as a base64 commit trailer', async () => {
  const worktreeParent = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-rgh-'));
  const worktreePath = path.join(worktreeParent, 'worktree');
  const testFile = `playwright-capture-${Date.now().toString(36)}.txt`;

  try {
    run('git', ['worktree', 'add', '--detach', worktreePath, 'HEAD'], repoRoot);
    copyFeatureFiles(worktreePath);

    expect(run('./scripts/gitWiggum', ['rgh', 'build'], worktreePath)).toContain('rgh build ok');

    run('./scripts/gitWiggum', ['rgh', 'install-hooks'], worktreePath);
    run('./scripts/gitWiggum', ['rgh', 'install-hooks'], worktreePath);

    const activeHooksDir = resolveActiveHooksDir(worktreePath);
    const preCommitPath = path.join(activeHooksDir, 'pre-commit');
    const commitMsgPath = path.join(activeHooksDir, 'commit-msg');

    expect(fs.realpathSync(preCommitPath)).toBe(fs.realpathSync(path.join(worktreePath, '.githooks', 'pre-commit')));
    expect(fs.realpathSync(commitMsgPath)).toBe(fs.realpathSync(path.join(worktreePath, '.githooks', 'commit-msg')));

    fs.writeFileSync(path.join(worktreePath, testFile), 'capture smoke\n');
    run('git', ['add', testFile], worktreePath);
    run('git', ['commit', '-m', 'Smoke capture trailer'], worktreePath, {
      GIT_AUTHOR_NAME: 'Playwright',
      GIT_AUTHOR_EMAIL: 'playwright@example.com',
      GIT_COMMITTER_NAME: 'Playwright',
      GIT_COMMITTER_EMAIL: 'playwright@example.com',
    });

    const commitBody = run('git', ['log', '-1', '--format=%B'], worktreePath);
    const trailerMatch = commitBody.match(/^GitWiggum-Capture-Base64:\s+([A-Za-z0-9+/=]+)$/m);

    expect(trailerMatch).toBeTruthy();

    const capture = JSON.parse(Buffer.from(trailerMatch[1], 'base64').toString('utf8'));

    expect(capture.source).toBe('codex');
    expect(capture.prompt).toBeTruthy();
    expect(capture.promptMessages.length).toBeGreaterThan(0);
    expect(capture.rawPayload.latestUserMessage).toBeTruthy();
    expect(capture.prompt).toContain(capture.rawPayload.latestUserMessage.text);
    expect(capture.promptMessages.at(-1)).toEqual(capture.rawPayload.latestUserMessage);
    expect(capture.thinking).toBeTruthy();
    expect(capture.thinking.encrypted_content).toBeTruthy();
    expect(capture.rawPayload.latestReasoning.encrypted_content).toBeTruthy();
  } finally {
    try {
      run('git', ['worktree', 'remove', '--force', worktreePath], repoRoot);
    } catch (_error) {
      // Best effort cleanup for the temporary worktree.
    }
    fs.rmSync(worktreeParent, { recursive: true, force: true });
  }
});
