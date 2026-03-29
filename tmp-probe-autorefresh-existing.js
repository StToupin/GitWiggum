const { chromium, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { resolveAppBaseUrl } = require('./playwright/helpers/app-base-url');

const repoRoot = __dirname;
const appBaseUrl = resolveAppBaseUrl();

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  }).trim();
}

function escapeSql(sql) {
  return sql.replace(/"/g, '\\"');
}

function queryValue(sql) {
  return run('direnv', ['exec', '.', 'bash', '-lc', `psql "$DATABASE_URL" -Atc "${escapeSql(sql)}"`]);
}

function execSql(sql) {
  return run('direnv', ['exec', '.', 'bash', '-lc', `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "${escapeSql(sql)}"`]);
}

function runGit(args, { cwd } = {}) {
  return run('git', args, { cwd });
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
  commitMessage,
}) {
  const barePath = repositoryBarePath(ownerSlug, repositoryName);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-autorefresh-'));
  const cloneDir = path.join(tempRoot, 'repo');

  try {
    runGit(['clone', '--branch', fromBranch, barePath, cloneDir]);
    runGit(branch === fromBranch ? ['checkout', branch] : ['checkout', '-b', branch], { cwd: cloneDir });
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

async function main() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ baseURL: appBaseUrl });
  const suffix = Date.now().toString(36);
  const email = `autorefresh-${suffix}@example.com`;
  const username = `autorefresh-${suffix}`;
  const repositoryName = `autorefresh-${suffix}`;
  const compareBranch = 'feature-autorefresh';
  const password = 'secret123';

  try {
    await page.goto('/NewRegistration');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Username').fill(username);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Create account' }).click();

    const userId = queryValue(`select id from users where email = '${email}'`);
    execSql(`update users set is_confirmed = true, confirmation_token = null where id = '${userId}'`);

    await page.goto('/NewSession');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Sign in' }).click();

    await page.getByRole('link', { name: 'Create repository' }).click();
    await page.getByLabel('Repository name').fill(repositoryName);
    await page.getByRole('button', { name: 'Create repository' }).click();

    await expect
      .poll(() => fs.existsSync(repositoryBarePath(username, repositoryName)), { timeout: 15000 })
      .toBe(true);

    seedRepositoryBranch({
      ownerSlug: username,
      repositoryName,
      branch: compareBranch,
      fromBranch: 'main',
      files: { 'src/live.txt': 'hello\n' },
      commitMessage: 'Seed live branch',
    });

    await page.goto(`/${username}/${repositoryName}/pull-requests/new`);
    await page.getByLabel('Title').fill('Auto refresh probe');
    await page.getByLabel('Compare branch').selectOption(compareBranch);
    await page.getByRole('button', { name: 'Create pull request' }).click();
    await page.getByRole('link', { name: 'Files' }).click();
    await expect(page.getByText('src/live.txt')).toBeVisible({ timeout: 10000 });

    await page.getByRole('button', { name: 'Ask AI' }).click();

    const jobIdSql = `
      select j.id
      from diff_ai_response_jobs j
      join pull_requests pr on pr.id = j.pull_request_id
      join repositories r on r.id = pr.repository_id
      join users u on u.id = r.owner_user_id
      where u.username = '${username}'
        and r.name = '${repositoryName}'
        and pr.number = 1
      order by j.created_at desc
      limit 1
    `;

    await expect.poll(() => queryValue(jobIdSql), { timeout: 15000 }).not.toBe('');
    const jobId = queryValue(jobIdSql);

    await page.reload();
    await expect(page.getByText('AI explanation')).toBeVisible({ timeout: 10000 });

    const probeText = `AUTORELOAD_PROBE_${suffix}`;
    execSql(`
      update diff_ai_response_jobs
      set status = 'job_status_running',
          response = '${probeText}'
      where id = '${jobId}'
    `);

    await expect(page.getByText(probeText)).toBeVisible({ timeout: 10000 });
    console.log('AUTORELOAD_EXISTING_ROW_OK');
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
