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
  run('direnv', ['exec', '.', 'bash', '-lc', `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "${escapeSql(sql)}"`]);
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
  commitMessage = `Seed ${branch}`,
}) {
  const barePath = repositoryBarePath(ownerSlug, repositoryName);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gitwiggum-diff-ai-'));
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

function jobStatusSql(username, repositoryName) {
  return `
    select status
    from diff_ai_response_jobs j
    join pull_requests pr on pr.id = j.pull_request_id
    join repositories r on r.id = pr.repository_id
    join users u on u.id = r.owner_user_id
    where u.username = '${username}'
      and r.name = '${repositoryName}'
      and pr.number = 1
    order by j.created_at desc
    limit 1;
  `;
}

function jobResponseLengthSql(username, repositoryName) {
  return `
    select coalesce(length(response), 0)
    from diff_ai_response_jobs j
    join pull_requests pr on pr.id = j.pull_request_id
    join repositories r on r.id = pr.repository_id
    join users u on u.id = r.owner_user_id
    where u.username = '${username}'
      and r.name = '${repositoryName}'
      and pr.number = 1
    order by j.created_at desc
    limit 1;
  `;
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ baseURL: appBaseUrl });
  page.on('console', (message) => console.log(`[browser:${message.type()}] ${message.text()}`));

  const suffix = Date.now().toString(36);
  const email = `repo-pr-diff-ai-${suffix}@example.com`;
  const username = `repo-pr-diff-ai-${suffix}`;
  const repositoryName = `pr-diff-ai-${suffix}`;
  const compareBranch = 'feature-diff-ai';

  try {
    console.log(`Using app base URL ${appBaseUrl}`);
    await signUpConfirmAndSignIn(page, { email, username, password: 'secret123' });
    await createRepository(page, {
      repositoryName,
      description: 'Diff AI streaming verification',
      visibility: 'public',
    });

    await expect
      .poll(() => fs.existsSync(repositoryBarePath(username, repositoryName)), {
        timeout: 15000,
        message: 'repository bare path should exist',
      })
      .toBe(true);

    seedRepositoryBranch({
      ownerSlug: username,
      repositoryName,
      branch: compareBranch,
      fromBranch: 'main',
      files: {
        'src/feature.txt': 'feature-only line\nsecond line\n',
      },
      commitMessage: 'Seed diff ai branch',
    });

    const barePath = repositoryBarePath(username, repositoryName);
    console.log(run('git', ['--git-dir', barePath, 'branch', '-a']));
    console.log(run('git', ['--git-dir', barePath, 'diff', '--find-renames', '--unified=3', 'main...feature-diff-ai']));

    await page.goto(`/${username}/${repositoryName}/pull-requests/new`);
    await page.getByLabel('Title').fill('Verify diff ai');
    await page.getByLabel('Compare branch').selectOption(compareBranch);
    await page.getByRole('button', { name: 'Create pull request' }).click();
    await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/conversation$`));

    await page.getByRole('link', { name: 'Files' }).click();
    await expect(page).toHaveURL(new RegExp(`/${username}/${repositoryName}/pull-requests/1/files$`));

    const bodyText = await page.locator('body').innerText();
    console.log('FILES_PAGE_BODY_START');
    console.log(bodyText);
    console.log('FILES_PAGE_BODY_END');

    await expect(page.getByText('src/feature.txt')).toBeVisible({ timeout: 10000 });
    await expect(page.getByText('+feature-only line')).toBeVisible({ timeout: 10000 });

    const askAiButton = page.getByRole('button', { name: 'Ask AI' }).first();
    await expect(askAiButton).toBeVisible({ timeout: 10000 });
    await askAiButton.click();

    await expect
      .poll(() => queryValue(jobStatusSql(username, repositoryName)), {
        timeout: 120000,
        intervals: [1000, 2000, 3000, 5000],
        message: 'diff ai job should succeed',
      })
      .toBe('job_status_succeeded');

    await expect
      .poll(() => Number(queryValue(jobResponseLengthSql(username, repositoryName)) || '0'), {
        timeout: 120000,
        intervals: [1000, 2000, 3000, 5000],
        message: 'diff ai job should stream non-empty content to the database',
      })
      .toBeGreaterThan(20);

    await expect(page.getByText('AI explanation')).toBeVisible({ timeout: 30000 });
    await expect(page.getByText('Ready')).toBeVisible({ timeout: 30000 });
    await expect
      .poll(async () => {
        const texts = await page.locator('div.border.rounded-3.bg-white pre code').allTextContents();
        return texts.join('\n').trim().length;
      }, {
        timeout: 30000,
        intervals: [1000, 2000, 3000],
        message: 'files tab should auto-refresh the streamed response',
      })
      .toBeGreaterThan(20);

    console.log('PLAYWRIGHT_DIFF_AI_OK');
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
