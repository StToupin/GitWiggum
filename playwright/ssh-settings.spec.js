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
  await expect(page).toHaveURL(/\/Dashboard$/);
}

test('users can save an SSH public key and see the configured status persist', async ({ page }) => {
  const suffix = Date.now().toString(36);
  const email = `repo-ssh-${suffix}@example.com`;
  const username = `repo-ssh-${suffix}`;
  const sshPublicKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJwM2O0o39YqK0PXmXqQyV2pAonyz1ME3iAFH4x63Hzl playwright@example.com';

  await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });

  await page.goto('/settings/ssh');
  await expect(page.getByRole('heading', { name: 'SSH keys' })).toBeVisible();
  await expect(page.getByText('Not configured')).toBeVisible();

  await page.getByLabel('SSH public key').fill(sshPublicKey);
  await page.getByRole('button', { name: 'Save SSH key' }).click();

  await expect(page).toHaveURL(/\/settings\/ssh$/);
  await expect(page.getByText('SSH public key saved.')).toBeVisible();
  await expect(page.getByText('Configured')).toBeVisible();
  await expect(page.getByLabel('SSH public key')).toHaveValue(sshPublicKey);

  await page.reload();
  await expect(page.getByText('Configured')).toBeVisible();
  await expect(page.getByLabel('SSH public key')).toHaveValue(sshPublicKey);
});
