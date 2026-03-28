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

test('auth schema boot smoke', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /Review pull requests/i })).toBeVisible();
});

test('sign up creates an inactive account and shows confirmation notice', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `auth-${suffix}@example.com`;
  const username = `auth-${suffix}`;

  await page.goto('/NewRegistration');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Username').fill(username);
  await page.getByLabel('Password').fill('secret123');
  await page.getByRole('button', { name: 'Create account' }).click();

  await expect(page.getByText('Account created. Confirm your email before signing in.')).toBeVisible();
  await expect(page.getByRole('heading', { name: /Review pull requests/i })).toBeVisible();

  const isConfirmed = queryValue(`select is_confirmed from users where email = '${email}';`);
  expect(isConfirmed).toBe('f');
});
