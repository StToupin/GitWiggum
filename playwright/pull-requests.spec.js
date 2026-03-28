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

function seedRepositoryBranch({
  ownerSlug,
  repositoryName,
  branch,
  files,
  fromBranch = 'main',
  commitMessage = `Seed ${branch}`,
}) {
  const barePath = repositoryBarePath(ownerSlug, repositoryName);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-pr-branch-'));
  const cloneDir = path.join(tempRoot, 'repo');

  try {
    runGit(['clone', '--branch', fromBranch, barePath, cloneDir]);
    if (branch === fromBranch) {
      runGit(['checkout', branch], { cwd: cloneDir });
    } else {
      runGit(['checkout', '-b', branch], { cwd: cloneDir });
    }
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

test('create pull request from a pushed branch lands on a stable canonical route', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-pr-${suffix}@example.com`;
  const username = `repo-pr-${suffix}`;
  const repositoryName = `pr-${suffix}`;
  const compareBranch = 'feature-docs';

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Pull request creation smoke test',
    visibility: 'public',
  });
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: compareBranch,
    files: {
      'docs/feature.md': 'new feature branch content\n',
    },
  });

  await page.goto(`/${username}/${repositoryName}/pull-requests`);
  await expect(page.getByRole('heading', { name: 'Pull requests', exact: true })).toBeVisible();
  await page.getByRole('link', { name: 'New pull request' }).click();

  await expect(page.getByRole('heading', { name: 'Open a pull request' })).toBeVisible();
  await page.getByLabel('Title').fill('Add docs branch');
  await page.getByLabel('Compare branch').selectOption(compareBranch);
  await page.getByLabel('Create as draft').check();
  await page.getByRole('button', { name: 'Create pull request' }).click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/conversation$`));
  await expect(page.getByRole('heading', { name: '#1 Add docs branch' })).toBeVisible();
  await expect(page.getByText('main <- feature-docs')).toBeVisible();
  await expect(page.getByText('Draft')).toBeVisible();
  await expect(page.getByText(`/${username}/${repositoryName}/pull-requests/1/conversation`)).toBeVisible();

  await page.goto(`/${username}/${repositoryName}/pull-requests`);
  await expect(page.getByRole('link', { name: /Add docs branch/i })).toBeVisible();
});

test('pull request numbers increment within the same repository', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-pr-number-${suffix}@example.com`;
  const username = `repo-pr-number-${suffix}`;
  const repositoryName = `pr-number-${suffix}`;

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Pull request numbering smoke test',
    visibility: 'public',
  });
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: 'feature-alpha',
    files: {
      'alpha.txt': 'alpha\n',
    },
  });

  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: 'feature-beta',
    files: {
      'beta.txt': 'beta\n',
    },
  });

  await page.goto(`/${username}/${repositoryName}/pull-requests/new`);
  await page.getByLabel('Title').fill('Alpha branch');
  await page.getByLabel('Compare branch').selectOption('feature-alpha');
  await page.getByRole('button', { name: 'Create pull request' }).click();
  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/conversation$`));

  await page.goto(`/${username}/${repositoryName}/pull-requests/new`);
  await page.getByLabel('Title').fill('Beta branch');
  await page.getByLabel('Compare branch').selectOption('feature-beta');
  await page.getByRole('button', { name: 'Create pull request' }).click();
  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/2/conversation$`));
  await expect(page.getByRole('heading', { name: '#2 Beta branch' })).toBeVisible();
});

test('pull request conversation tab and commits tab preserve PR shell routing', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-pr-tabs-${suffix}@example.com`;
  const username = `repo-pr-tabs-${suffix}`;
  const repositoryName = `pr-tabs-${suffix}`;
  const compareBranch = 'feature-history';

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Pull request tab routing smoke test',
    visibility: 'public',
  });
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: compareBranch,
    files: {
      'docs/history.md': 'history branch content\n',
    },
  });

  await page.goto(`/${username}/${repositoryName}/pull-requests/new`);
  await page.getByLabel('Title').fill('Track compare history');
  await page.getByLabel('Compare branch').selectOption(compareBranch);
  await page.getByRole('button', { name: 'Create pull request' }).click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/conversation$`));
  await expect(page.getByRole('link', { name: 'Conversation' })).toHaveClass(/btn-dark/);
  await expect(page.getByRole('link', { name: 'Commits' })).toBeVisible();

  await page.getByRole('link', { name: 'Commits' }).click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/commits$`));
  await expect(page.getByRole('link', { name: 'Commits' })).toHaveClass(/btn-dark/);
  await expect(page.getByText('Seed feature-history')).toBeVisible();

  await page.getByRole('link', { name: 'Conversation' }).click();
  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/conversation$`));
  await expect(page.getByText('Track compare history')).toBeVisible();
});

test('pull request files tab renders the merge base diff', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-pr-files-${suffix}@example.com`;
  const username = `repo-pr-files-${suffix}`;
  const repositoryName = `pr-files-${suffix}`;
  const compareBranch = 'feature-diff';

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
  await createRepository(page, {
    repositoryName,
    description: 'Pull request files diff smoke test',
    visibility: 'public',
  });
  await expect.poll(() => fs.existsSync(repositoryBarePath(username, repositoryName))).toBe(true);

  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: compareBranch,
    fromBranch: 'main',
    files: {
      'src/feature.txt': 'feature-only line\n',
    },
    commitMessage: 'Seed feature diff',
  });

  seedRepositoryBranch({
    ownerSlug: username,
    repositoryName,
    branch: 'main',
    fromBranch: 'main',
    files: {
      'README.md': '# Drift on main\n',
    },
    commitMessage: 'Advance main branch',
  });

  await page.goto(`/${username}/${repositoryName}/pull-requests/new`);
  await page.getByLabel('Title').fill('Render diff from merge base');
  await page.getByLabel('Compare branch').selectOption(compareBranch);
  await page.getByRole('button', { name: 'Create pull request' }).click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/conversation$`));
  await page.getByRole('link', { name: 'Files', exact: true }).click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/files$`));
  await expect(page.getByText('src/feature.txt')).toBeVisible();
  await expect(page.getByText('+feature-only line')).toBeVisible();
  await expect(page.getByText('README.md', { exact: true })).not.toBeVisible();
});
