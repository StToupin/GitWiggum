module Web.View.Static.Home where

import Web.View.Prelude

data HomeView = HomeView

instance View HomeView where
    html HomeView = [hsx|
        <div class="row g-4 g-lg-5 align-items-center py-4 py-lg-5">
            <div class="col-12 col-lg-7">
                <div class="mb-3 text-uppercase small fw-semibold text-secondary">
                    Local-first code review
                </div>
                <h1 class="display-4 fw-bold mb-3">
                    Review pull requests, ask AI about diffs, and keep git workflows real.
                </h1>
                <p class="lead text-secondary mb-4">
                    GitWiggum is a lightweight local git host for repository browsing, pull requests,
                    and AI-assisted review flows. Start by creating your account.
                </p>
                <div class="d-flex flex-wrap gap-3">
                    <a class="btn btn-dark btn-lg" href={pathTo NewRegistrationAction} data-posthog-id="home-sign-up-primary">
                        Create account
                    </a>
                </div>
            </div>
            <div class="col-12 col-lg-5">
                <div class="card shadow-sm border-0 bg-body-tertiary">
                    <div class="card-body p-4">
                        <h2 class="h4 mb-3">What ships first</h2>
                        <ul class="list-unstyled mb-0 d-grid gap-3">
                            <li>
                                <div class="fw-semibold">Real repositories</div>
                                <div class="text-secondary">Create repos, browse branches, and open pull requests.</div>
                            </li>
                            <li>
                                <div class="fw-semibold">Inline diff AI</div>
                                <div class="text-secondary">Ask for explanations on a specific changed line and persist the answer.</div>
                            </li>
                            <li>
                                <div class="fw-semibold">Prompt-to-PR agents</div>
                                <div class="text-secondary">Run local Codex jobs that turn a prompt into a draft pull request.</div>
                            </li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
    |]
