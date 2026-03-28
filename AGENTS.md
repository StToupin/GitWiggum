# gitWiggum Agent Notes

## Build Verification

- When checking whether the app compiles, reproducing compile errors, or claiming the build is clean in `/Users/vcombey/cava/gitWiggum`, run `devenv up` from the repo root.
- In a fresh git worktree, approve the repo's existing `.envrc` first with `direnv allow` from the repo root before relying on `devenv up` or `direnv exec . ...`; otherwise the app might not boot because the worktree environment was never authorized.
- If `devenv` is not available in the current shell, run `direnv exec . devenv up` from the repo root so the repo's `.envrc` loads the correct dev environment first.
- Do not use `nix develop -c devenv up` as the fallback here; in this repo it can fail with a `devenv was not able to determine the current directory` assertion even when the project is otherwise fine.
- Treat `devenv up` as the source of truth for compile and startup status in this repo.
- Use `ghci`, `cabal build`, or targeted module loads only as supplemental diagnostics after `devenv up`, not as the primary compile check.
- Do not treat `cabal build exe:App` as a compile verification step in this repo. It can fail with missing `Generated.Types`, `Config`, or other IHP-generated modules even when the app itself compiles and runs correctly under `devenv up`.
- If a supplemental `cabal build` or `ghci` command fails but `devenv up` succeeds, report that as a tooling or generated-module mismatch, not as an application compile failure.
- If `devenv up` fails because of an environment issue unrelated to compilation, call that out separately instead of reporting it as a clean compile or a code compile error.
- If `devenv up` fails inside `typedSql` with a missing-column error against the local database, check whether this worktree DB was bootstrapped from `Application/Schema.sql` with an empty `schema_migrations` table. In that state, bare `migrate` will replay old revisions and fail on already-existing columns.
- For that local recovery path: start the worktree-local postgres with `direnv exec . bash -lc 'start-postgres'`, apply the missing idempotent SQL migration files directly with `direnv exec . psql "$DATABASE_URL" -f Application/Migration/<revision>.sql`, then backfill `schema_migrations` from the filenames in `Application/Migration` before rerunning `direnv exec . migrate` and `devenv up`.

## Running Alongside Other Agents

- First prefer isolating this worktree instead of killing another live `gitWiggum` checkout. Before starting `devenv up`, check which listeners are occupied with `lsof -nP -iTCP:<port> -sTCP:LISTEN`.
- If you find a running `RunDevServer`, confirm which checkout owns it with `lsof -p <pid> | rg " cwd "`. Do not assume the process belongs to the current worktree just because it is a `gitWiggum` server.
- Linked git worktrees now auto-derive a deterministic port slot in `.envrc` from the worktree path. In a linked worktree, plain `direnv exec . devenv up` should already pick non-default ports without extra manual overrides.
- The main checkout keeps the legacy defaults. Linked worktrees automatically shift `PORT`, `gitWiggum_SSH_PORT`, `IHP_HOOGLE_PORT`, `SMTP_PORT`, `MAILHOG_UI_PORT`, `MINIO_API_PORT`, `MINIO_CONSOLE_PORT`, `AWS_ENDPOINT`, `APP_HOSTNAME`, and `PLAYWRIGHT_BASE_URL`.
- Do not assume the app is on `8000` when you are inside a linked worktree. Check the resolved values first with:
  `direnv exec . env | rg '^(PORT|APP_HOSTNAME|PLAYWRIGHT_BASE_URL|gitWiggum_SSH_PORT|IHP_HOOGLE_PORT|SMTP_PORT|MAILHOG_UI_PORT|MINIO_API_PORT|MINIO_CONSOLE_PORT|AWS_ENDPOINT)='`
- Manual overrides still win. If you need a specific port block, export the relevant env vars before `direnv exec . devenv up` or put them in `.env`.
- MailHog is no longer a fixed `services.mailhog` service in this repo. It now follows `SMTP_PORT` for SMTP and `MAILHOG_UI_PORT` for the UI/API, so parallel worktrees no longer collide on `1025` and `8025` by default.
- Stripe forwarding is also worktree-aware now. `processes.stripe-listen` forwards to `http://127.0.0.1:${PORT}/StripeWebhook` instead of hardcoding `8000`.
- If postgres looks stale for this worktree, verify the current socket before trusting it. Use `direnv exec . psql "$DATABASE_URL" -c 'select 1'` and `lsof -nP -U | rg "$PGHOST"` to confirm the server behind this worktree is actually alive.
- If `.devenv/state/postgres/postmaster.pid` exists but the socket is dead, treat it as a stale worktree-local runtime, not as an app compile failure. Kill only the matching `devenv`/postgres processes for this worktree, then relaunch `devenv up`.
- `Ctrl-C` on the foreground `devenv up` should now tear down that specific worktree's supervised processes more reliably, including the app-side children it started. It still does not stop another checkout's `devenv up`, and it will not clean up old detached or already-orphaned processes from a previous bad session.
- Only kill other `gitWiggum` runtimes when isolation is not sufficient or when the lingering processes are clearly stale. If you do kill them, target the concrete listener PIDs or the matching worktree/runtime path, not unrelated system processes.

## Test Verification

- verify each feature with playwright
- after implementing a new feature, update the fixture when needed so the feature can be exercised from the seeded test data
- when working from a git worktree, commit the changes, push the branch, and create a pull request if one does not already exist
- Managed git hooks are installed into the current worktree's `$(git rev-parse --git-dir)/hooks`, so a fresh linked worktree does not inherit the main checkout's `pre-commit` hook automatically.
- `devenv up` now installs or refreshes the managed hooks for the current checkout automatically. If you need to bootstrap them before the app stack is running, run `direnv allow` and then `direnv exec . just install-hooks` from the repo root so the managed `pre-commit` hook formats staged Haskell files with `fourmolu`.
- If the hook is not installed yet or you want an explicit formatting pass, run `direnv exec . ./scripts/format-haskell.sh --staged` before committing, `direnv exec . just format-haskell` for a repo-wide rewrite, and `direnv exec . just check-haskell-format` to verify the tree is clean.
- For Playwright, if `@playwright/test` or the Playwright CLI is missing, run `direnv exec . npm ci` from the repo root before running browser tests.
- For Playwright, if browser binaries are missing, run `direnv exec . ./scripts/ensure-playwright-browsers.sh` from the repo root before running tests.
- Use focused Playwright runs for feature verification, e.g. `direnv exec . npm run test:playwright -- playwright/<spec>.js --grep "<test name>"`.
- `direnv exec . cabal test App-test --test-options='...'` can be used as a supplemental Hspec check, but the current suite is blocked by an existing missing `wai-request-params` test dependency in `Test/Controller/JsonApiSpec.hs`.
- If `App-test` fails on the hidden `wai-request-params` package while the feature-specific Playwright check and `devenv up` succeed, report that as an existing test-suite dependency issue, not as evidence that the feature implementation is broken.
- never use `sqlQuery` or `sqlExec`; use `sqlQueryTyped` with `[typedSql| ... |]` for raw queries, and use `sqlExecTyped` for raw write statements without `RETURNING`
- never use hx-boost=false for internal code, only for link to external sites
- On new UI code, add explicit stable `data-posthog-id` attributes to buttons, links, and other user-triggered actions so PostHog tracking does not depend on visible text.
- For top-level page tabs that behave like separate pages, follow the same pattern used in pull requests, repositories, and account settings: use dedicated actions/routes for each tab and wire the tab header to those actions. Do not model those tabs with `?tab=` query params.

## AutoRefresh Pattern

- On pages wrapped in `autoRefresh`, same-page HTML mutations should return `204 No Content` on success and let auto-refresh update the DOM. Do not redirect back to the same page/tab after a successful mutation.
- Keep redirects only for real navigation changes or invalid/error branches that must move the user somewhere else.
- For internal HTMX page-to-page redirects, prefer real framework redirects (`redirectToPathSeeOther`, `redirectToSeeOther`, or the shared helpers that delegate to them) over `HX-Redirect` when the interaction is a boosted form or link. HTMX will follow the HTTP redirect inside the request, morphdom-swap the inherited target such as `#gitWiggum-page-content`, and keep the sidebar shell mounted.
- If the interaction can be a normal boosted form or link, prefer that over an explicit `hx-post` so validation responses stay on the current page while redirected success responses update history automatically.
- If a non-boosted HTMX request must navigate and its success path only redirects, add `hx-push-url="true"` or `hx-replace-url="true"` on the trigger so the final redirected URL is reflected in browser history. Do not use that on forms that can re-render validation errors, or HTMX will push the action URL into history.
- Reserve `HX-Redirect` for the rare cases where a hard browser navigation is actually required.
- On `autoRefresh` pages, prefer normal `query`/`fetch` reads for data that must live-update. If you use `sqlQueryTyped` or other custom SQL in a rendered read path, you must `trackTableRead` for every table involved or auto-refresh will not subscribe to those changes.
- If a `204` mutation does not update the page, debug the auto-refresh subscription/client lifecycle first. Do not add ad hoc refresh headers or same-page redirect fallbacks as the default fix.

## Migration Rules

- IHP tracks applied migrations by revision in the `schema_migrations` table, not just by "latest migration file".
- On deploy, the migration runner applies every migration revision present in `Application/Migration` that is missing from `schema_migrations`, in revision order.
- A late branch can still deploy an older-timestamped migration if that revision is missing from the target database, even when newer migrations from `main` were already applied.
- Before generating or editing migrations, rebase on the latest `main` so the migration directory and schema reflect the already-merged history.
- Never modify an existing numbered migration file to reflect a new schema change. Existing revisions may already be applied in deployed databases, so follow-up schema work must always go into a new migration file.
- Preferred workflow after changing `Application/Schema.sql`:
  1. Rebase on the latest `main`.
  2. Start the local dev database with `direnv exec . start-postgres` or, if you already need the full app stack, `direnv exec . devenv up`.
  3. Run `direnv exec . new-migration "<description>"` from the repo root. In this repo, `new-migration` exists on the command line and uses the running local Postgres / `DATABASE_URL` to generate the new timestamped migration under `Application/Migration`.
  4. Review the generated SQL and keep it forward-only and idempotent when needed.
- If `new-migration` fails because the local Postgres is not running or is unhealthy, treat that as an environment issue to fix first. Do not work around it by editing an older migration file.
- If you changed `Application/Schema.sql` manually, make sure the new migration captures only the delta introduced by that schema change; do not copy unrelated DDL from older revisions into the new file.
- Do not create duplicate DDL across multiple migration files. If a schema change is already represented by another staged or merged migration, reconcile the files before shipping.
- If a migration revision has already been applied in any database, do not silently delete, rename, or reuse that revision. Keep it and reconcile with a no-op compatibility migration or a forward-only corrective migration.
- Do not destroy the database just to resolve conflicting migrations. Prefer forward-only fixes and compatibility no-ops.
- If a previously applied accidental migration must stop doing work for fresh databases, keep the revision file in the repo as a documented no-op and move the real schema change into later canonical migrations.
- When canonical migrations may run against databases that already contain the table, column, index, or constraint, make those migrations idempotent with `IF NOT EXISTS` or guarded `DO $$ ... $$` checks where needed.

## Secrets

- Shared local secrets use `sops + age`.
- The local age identity for this machine is stored at `~/.config/sops/age/keys.txt`.
- Repo helper scripts automatically prefer `SOPS_AGE_KEY_FILE` when set, then `~/.config/sops/age/keys.txt`, then the legacy macOS path `~/Library/Application Support/sops/age/keys.txt`.
- `devenv up` automatically attempts to sync `secrets/shared.env` into `.env.secrets` before starting repo processes.
- Agents can still run `just install-secrets` from the repo root to force a manual sync.
- Never print, commit, or otherwise expose the private age key.
