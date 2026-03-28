const { test, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');

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

function runGit(args, { cwd } = {}) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function repositoryBarePath(ownerSlug, repositoryName) {
  return path.join(repoRoot, 'data', 'repositories', ownerSlug, `${repositoryName}.git`);
}

function seedRepositoryFiles({ ownerSlug, repositoryName, files, branch = 'main' }) {
  const barePath = repositoryBarePath(ownerSlug, repositoryName);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-browser-'));
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
    runGit(['commit', '-m', 'Seed browser tree'], { cwd: cloneDir });
    runGit(['push', 'origin', `HEAD:${branch}`], { cwd: cloneDir });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

function seedRepositoryBranch({ ownerSlug, repositoryName, branch, files, fromBranch = 'main' }) {
  const barePath = repositoryBarePath(ownerSlug, repositoryName);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-branch-'));
  const cloneDir = path.join(tempRoot, 'repo');

  try {
    runGit(['clone', '--branch', fromBranch, barePath, cloneDir]);
    runGit(['checkout', '-b', branch], { cwd: cloneDir });
    runGit(['config', 'user.name', 'Playwright Seeder'], { cwd: cloneDir });
    runGit(['config', 'user.email', 'playwright@example.com'], { cwd: cloneDir });

    for (const [relativePath, content] of Object.entries(files)) {
      const absolutePath = path.join(cloneDir, relativePath);
      fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
      fs.writeFileSync(absolutePath, content, 'utf8');
    }

    runGit(['add', '.'], { cwd: cloneDir });
    runGit(['commit', '-m', `Seed ${branch}`], { cwd: cloneDir });
    runGit(['push', 'origin', `HEAD:${branch}`], { cwd: cloneDir });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

test('dashboard list shows visible repositories and create repository CTA', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-${suffix}@example.com`;
  const username = `repo-${suffix}`;
  const repositoryName = `alpha-${suffix}`;

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });

  await expect(page.getByRole('link', { name: 'Create repository' })).toBeVisible();
  await expect(page.getByText('No repositories yet')).toBeVisible();

  await page.getByRole('link', { name: 'Create repository' }).click();
  await expect(page.getByRole('heading', { name: 'Create repository' })).toBeVisible();
  await expect(page.getByText(`/${username}`)).toBeVisible();

  const userId = queryValue(`select id from users where email = '${email}';`);
  execSql(
    `insert into repositories (owner_user_id, name, description, is_private) values ('${userId}', '${repositoryName}', 'Seeded dashboard repository', false);`,
  );

  await page.goto('/Dashboard');
  await expect(page.getByText(repositoryName)).toBeVisible();
  await expect(page.getByText('Seeded dashboard repository')).toBeVisible();
  await expect(page.getByText('Public')).toBeVisible();
});

test('create repository redirects to the canonical owner route', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-create-${suffix}@example.com`;
  const username = `repo-create-${suffix}`;
  const repositoryName = `project-${suffix}`;

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  const userId = queryValue(`select id from users where email = '${email}';`);

  await createRepository(page, {
    repositoryName,
    description: 'Canonical repository route smoke test',
    visibility: 'private',
  });

  const latestCommitSha = queryValue(
    `select latest_commit_sha from repositories where owner_user_id = '${userId}' and name = '${repositoryName}';`,
  );
  const bareRepositoryPath = repositoryBarePath(username, repositoryName);
  const directoryExplorer = page.locator('.card').filter({ hasText: 'Directory explorer' });

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}$`));
  await expect(page.getByRole('heading', { name: `${username}/${repositoryName}` })).toBeVisible();
  await expect(page.getByText('Canonical repository route smoke test', { exact: true })).toBeVisible();
  await expect(page.getByText('Private')).toBeVisible();
  await expect(directoryExplorer.getByText('README.md', { exact: true })).toBeVisible();
  await expect(page.locator('pre code')).toContainText(`# ${repositoryName}`);
  await expect(page.locator('pre code')).toContainText('Created with GitWiggum.');
  await expect(page.getByText(latestCommitSha.slice(0, 10))).toBeVisible();
  expect(latestCommitSha).toMatch(/^[0-9a-f]{40}$/);
  expect(fs.existsSync(bareRepositoryPath)).toBe(true);

  await page.goto('/Dashboard');
  await expect(page.getByText(repositoryName)).toBeVisible();
});

test('repository shell keeps repository context across browser, pull requests, and agents routes', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-shell-${suffix}@example.com`;
  const username = `repo-shell-${suffix}`;
  const repositoryName = `shell-${suffix}`;

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Repository shell route smoke test',
    visibility: 'public',
  });

  const browserPath = `/${username}/${repositoryName}`;
  const pullRequestsPath = `/${username}/${repositoryName}/pull-requests`;
  const agentsPath = `/${username}/${repositoryName}/agents`;

  await expect(page.getByRole('link', { name: 'Browser' })).toHaveAttribute('href', browserPath);
  await expect(page.getByRole('link', { name: 'Pull requests' })).toHaveAttribute('href', pullRequestsPath);
  await expect(page.getByRole('link', { name: 'Agents' })).toHaveAttribute('href', agentsPath);

  await page.getByRole('link', { name: 'Pull requests' }).click();
  await expect(page).toHaveURL(new RegExp(`${pullRequestsPath}$`));
  await expect(page.getByRole('heading', { name: `${username}/${repositoryName}` })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Pull requests', exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'New pull request' })).toBeVisible();

  await page.getByRole('link', { name: 'Agents' }).click();
  await expect(page).toHaveURL(new RegExp(`${agentsPath}$`));
  await expect(page.getByRole('heading', { name: `${username}/${repositoryName}` })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Repository agents surface' })).toBeVisible();

  await page.getByRole('link', { name: 'Browser' }).click();
  await expect(page).toHaveURL(new RegExp(`${browserPath}$`));
  await expect(page.getByRole('heading', { name: `${username}/${repositoryName}` })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Repository root' })).toBeVisible();
});

test('browser root shows selected default branch and current path', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-browser-${suffix}@example.com`;
  const username = `repo-browser-${suffix}`;
  const repositoryName = `browser-${suffix}`;

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Browser root route smoke test',
    visibility: 'public',
  });

  const browserPath = `/${username}/${repositoryName}`;
  const selectedBranchCard = page.locator('.card').filter({ hasText: 'Selected branch' });
  const currentPathCard = page.locator('.card').filter({ hasText: 'Current path' });

  await expect(page).toHaveURL(new RegExp(`${browserPath}$`));
  await expect(page.getByRole('heading', { name: `${username}/${repositoryName}` })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Repository root' })).toBeVisible();
  await expect(selectedBranchCard.getByText('main', { exact: true })).toBeVisible();
  await expect(currentPathCard.locator('code')).toHaveText('/');
  expect(page.url()).not.toContain('?');
});

test('browse folders updates the browser route and renders nested contents', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-folders-${suffix}@example.com`;
  const username = `repo-folders-${suffix}`;
  const repositoryName = `folders-${suffix}`;

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Nested folder browser smoke test',
    visibility: 'public',
  });
  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}$`));
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryFiles({
    ownerSlug: username,
    repositoryName,
    files: {
      'src/App.hs': 'module App where\n',
      'src/components/Button.hs': 'module Button where\n',
      'docs/guide.md': '# Guide\n',
    },
  });

  await page.goto(`/${username}/${repositoryName}`);
  await page
    .locator('[data-posthog-id="repository-browser-folder"]')
    .filter({ hasText: 'src' })
    .click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/tree/main/src$`));
  await expect(page.locator('.card').filter({ hasText: 'Current path' }).locator('code')).toHaveText('/src');
  await expect(page.locator('[data-posthog-id="repository-browser-folder"]').filter({ hasText: 'components' })).toBeVisible();
  await expect(page.getByText('App.hs', { exact: true })).toBeVisible();

  await page
    .locator('[data-posthog-id="repository-browser-folder"]')
    .filter({ hasText: 'components' })
    .click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/tree/main/src/components$`));
  await expect(page.locator('.card').filter({ hasText: 'Current path' }).locator('code')).toHaveText('/src/components');
  await expect(page.getByText('Button.hs', { exact: true })).toBeVisible();
  expect(page.url()).not.toContain('?');
});

test('switch branch updates the route and visible browser content', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-branch-${suffix}@example.com`;
  const username = `repo-branch-${suffix}`;
  const repositoryName = `branches-${suffix}`;
  const branchName = 'feature-ui';

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Branch selector smoke test',
    visibility: 'public',
  });
  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}$`));
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryFiles({
    ownerSlug: username,
    repositoryName,
    files: {
      'src/App.hs': 'module App where\n',
    },
  });
  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: branchName,
    files: {
      'feature-only.txt': 'feature branch only\n',
    },
  });

  await page.goto(`/${username}/${repositoryName}`);
  const branchSelector = page.locator('.card').filter({ hasText: 'Branch selector' });
  await expect(branchSelector.getByText('main', { exact: true })).toBeVisible();
  await expect(branchSelector.getByText(branchName, { exact: true })).toBeVisible();
  await expect(page.getByText('src', { exact: true })).toBeVisible();

  await page
    .locator('[data-posthog-id="repository-browser-branch"]')
    .filter({ hasText: branchName })
    .click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/tree/${branchName}$`));
  await expect(page.locator('.card').filter({ hasText: 'Selected branch' }).getByText(branchName, { exact: true })).toBeVisible();
  await expect(page.getByText('feature-only.txt', { exact: true })).toBeVisible();
  expect(page.url()).not.toContain('?');
});

test('preview file shows content and updates when switching branches', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-preview-${suffix}@example.com`;
  const username = `repo-preview-${suffix}`;
  const repositoryName = `preview-${suffix}`;
  const branchName = 'feature-ui';

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'File preview smoke test',
    visibility: 'public',
  });
  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}$`));
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryFiles({
    ownerSlug: username,
    repositoryName,
    files: {
      'src/App.hs': 'main branch preview\n',
    },
  });
  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: branchName,
    files: {
      'src/App.hs': 'feature branch preview\n',
    },
  });

  await page.goto(`/${username}/${repositoryName}`);
  await page
    .locator('[data-posthog-id="repository-browser-folder"]')
    .filter({ hasText: 'src' })
    .click();
  await page
    .locator('[data-posthog-id="repository-browser-file"]')
    .filter({ hasText: 'App.hs' })
    .click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/tree/main/src/App.hs$`));
  await expect(page.locator('.card').filter({ hasText: 'Current path' }).locator('code')).toHaveText('/src/App.hs');
  await expect(page.locator('.card').filter({ hasText: 'File preview' }).locator('pre code')).toContainText('main branch preview');
  await expect(page.locator('.card').filter({ hasText: 'File preview' })).toContainText('Seed browser tree');

  await page
    .locator('[data-posthog-id="repository-browser-branch"]')
    .filter({ hasText: branchName })
    .click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/tree/${branchName}/src/App.hs$`));
  await expect(page.locator('.card').filter({ hasText: 'Current path' }).locator('code')).toHaveText('/src/App.hs');
  await expect(page.locator('.card').filter({ hasText: 'File preview' }).locator('pre code')).toContainText('feature branch preview');
  await expect(page.locator('.card').filter({ hasText: 'File preview' })).toContainText(`Seed ${branchName}`);
});
