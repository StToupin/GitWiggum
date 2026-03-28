const { test, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
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

  await page.getByRole('link', { name: 'Create repository' }).click();
  await page.getByLabel('Repository name').fill(repositoryName);
  await page.getByLabel('Description').fill('Canonical repository route smoke test');
  await page.locator('input[name="visibility"][value="private"]').check();
  await page.getByRole('button', { name: 'Create repository' }).click();

  await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}$`));
  await expect(page.getByRole('heading', { name: `${username}/${repositoryName}` })).toBeVisible();
  await expect(page.getByText('Canonical repository route smoke test')).toBeVisible();
  await expect(page.getByText('Private')).toBeVisible();

  await page.goto('/Dashboard');
  await expect(page.getByText(repositoryName)).toBeVisible();
});
