const { test, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const appBaseUrl = process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8000';

function queryValue(sql) {
  return execFileSync(
    'direnv',
    ['exec', '.', 'bash', '-lc', `psql "$DATABASE_URL" -Atc "${sql}"`],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  ).trim();
}

function execSql(sql) {
  execFileSync(
    'direnv',
    ['exec', '.', 'bash', '-lc', `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "${sql}"`],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
}

function runGit(args, { cwd, env } = {}) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: env ?? process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function runGitFailure(args, { cwd, env } = {}) {
  try {
    runGit(args, { cwd, env });
    return { ok: true, stdout: '', stderr: '' };
  } catch (error) {
    return {
      ok: false,
      stdout: error.stdout?.toString() ?? '',
      stderr: error.stderr?.toString() ?? '',
    };
  }
}

function withBasicAuth(baseUrl, username, password) {
  const url = new URL(baseUrl);
  url.username = username;
  url.password = password;
  return url.toString().replace(/\/$/, '');
}

function repositoryBarePath(ownerSlug, repositoryName) {
  return path.join(repoRoot, 'data', 'repositories', ownerSlug, `${repositoryName}.git`);
}

function seedRepositoryFiles({ ownerSlug, repositoryName, files, branch = 'main', commitMessage = 'Seed HTTP fetch' }) {
  const barePath = repositoryBarePath(ownerSlug, repositoryName);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-http-seed-'));
  const cloneDir = path.join(tempRoot, 'repo');

  try {
    runGit(['clone', '--branch', branch, barePath, cloneDir]);
    runGit(['config', 'user.name', 'Playwright Seeder'], { cwd: cloneDir });
    runGit(['config', 'user.email', 'playwright@example.com'], { cwd: cloneDir });

    for (const [relativePath, content] of Object.entries(files)) {
      const absolutePath = path.join(cloneDir, relativePath);
      fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
      fs.writeFileSync(absolutePath, content, 'utf8');
    }

    runGit(['add', '.'], { cwd: cloneDir });
    runGit(['commit', '-m', commitMessage], { cwd: cloneDir });
    runGit(['push', 'origin', `HEAD:${branch}`], { cwd: cloneDir });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

async function signUpConfirmAndSignIn(page, { email, username, password }) {
  await page.goto('/NewRegistration');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Username').fill(username);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByText('Account created. Confirm your email before signing in.')).toBeVisible();

  const userId = queryValue(`select id from users where email = '${email}';`);
  execSql(`update users set is_confirmed = true, confirmation_token = null where id = '${userId}';`);

  await page.goto('/NewSession');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
}

async function createRepository(page, { repositoryName, description, visibility = 'public' }) {
  await page.getByRole('link', { name: 'Create repository' }).click();
  await page.getByLabel('Repository name').fill(repositoryName);
  await page.getByLabel('Description').fill(description);
  await page.locator(`input[name="visibility"][value="${visibility}"]`).check();
  await page.getByRole('button', { name: 'Create repository' }).click();
}

test('http clone and fetch work against the public repository endpoint', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-http-${suffix}@example.com`;
  const username = `repo-http-${suffix}`;
  const repositoryName = `http-${suffix}`;
  const cloneUrl = `${appBaseUrl}/${username}/${repositoryName}.git`;
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-http-clone-'));
  const cloneDir = path.join(tempRoot, 'repo');

  try {
    await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
    await createRepository(page, {
      repositoryName,
      description: 'HTTP clone and fetch smoke test',
      visibility: 'public',
    });

    await expect(page.locator('code').filter({ hasText: 'git clone' })).toContainText(`/${username}/${repositoryName}.git`);

    runGit(['clone', cloneUrl, cloneDir]);
    expect(fs.existsSync(path.join(cloneDir, 'README.md'))).toBe(true);
    expect(fs.readFileSync(path.join(cloneDir, 'README.md'), 'utf8')).toContain(`# ${repositoryName}`);

    const initialHead = runGit(['rev-parse', 'HEAD'], { cwd: cloneDir });

    seedRepositoryFiles({
      ownerSlug: username,
      repositoryName,
      files: {
        'docs/http-fetch.md': 'fetched over smart http\n',
      },
    });

    runGit(['fetch', 'origin'], { cwd: cloneDir });
    const fetchedHead = runGit(['rev-parse', 'origin/main'], { cwd: cloneDir });

    expect(fetchedHead).not.toBe(initialHead);
    expect(runGit(['show', 'origin/main:docs/http-fetch.md'], { cwd: cloneDir })).toContain('fetched over smart http');
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('private http clone requires auth and authenticated push exposes the branch in the web UI', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-http-private-${suffix}@example.com`;
  const username = `repo-http-private-${suffix}`;
  const repositoryName = `private-${suffix}`;
  const password = 'secret123';
  const branchName = 'feature-http-push';
  const cloneUrl = `${appBaseUrl}/${username}/${repositoryName}.git`;
  const authenticatedBaseUrl = withBasicAuth(appBaseUrl, username, password);
  const authenticatedCloneUrl = `${authenticatedBaseUrl}/${username}/${repositoryName}.git`;
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-http-private-'));
  const cloneDir = path.join(tempRoot, 'repo');

  try {
    await signUpConfirmAndSignIn(page, { email, username, password });
    await createRepository(page, {
      repositoryName,
      description: 'Private HTTP auth and push smoke test',
      visibility: 'private',
    });

    const anonymousProbe = runGitFailure(['ls-remote', cloneUrl], {
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
    });
    expect(anonymousProbe.ok).toBe(false);

    runGit(['clone', authenticatedCloneUrl, cloneDir]);
    runGit(['checkout', '-b', branchName], { cwd: cloneDir });
    runGit(['config', 'user.name', 'Playwright HTTP Pusher'], { cwd: cloneDir });
    runGit(['config', 'user.email', 'playwright@example.com'], { cwd: cloneDir });
    fs.writeFileSync(path.join(cloneDir, 'pushed-over-http.txt'), 'branch pushed over authenticated http\n', 'utf8');
    runGit(['add', 'pushed-over-http.txt'], { cwd: cloneDir });
    runGit(['commit', '-m', 'Push over authenticated HTTP'], { cwd: cloneDir });
    runGit(['push', 'origin', `HEAD:${branchName}`], { cwd: cloneDir });

    await page.goto(`/${username}/${repositoryName}`);
    const branchSelector = page.locator('.card').filter({ hasText: 'Branch selector' });
    await expect(branchSelector.getByText(branchName, { exact: true })).toBeVisible();
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
