# Lab 04: GitHub Actions CI/CD

## Objective

Building a real CI/CD pipeline --- not a "hello world" action but something that actually lints, tests, builds Docker images, and deploys to Kubernetes with environment-based approval gates.

## What I Learned

### Docker layer caching in Actions

Build times went from 4 minutes to 45 seconds using `docker/build-push-action` with the GitHub Actions cache backend. The trick is `cache-from: type=gha` and `cache-to: type=gha,mode=max`. Without this, every workflow run downloads and installs all dependencies from scratch.

### Concurrency groups

Without concurrency groups, pushing 3 commits in quick succession triggers 3 parallel workflow runs. The first two are wasted work since only the latest matters. Setting `concurrency: group: ${{ github.ref }}` with `cancel-in-progress: true` kills the stale runs.

### Environment protection rules

GitHub environments let you add required reviewers, wait timers, and deployment branch restrictions. Prod requires manual approval from a team lead. The secret scoping caught me off guard --- secrets are per-environment, not just per-repo. Had to add kubeconfig to each environment separately.

### Matrix builds

Testing across Python 3.10, 3.11, and 3.12 in parallel. Found a bug that only showed up on 3.10 because of a walrus operator in a f-string. Matrix strategies are worth the extra CI minutes.

## Pipeline Flow

```
Push to main
  |
  v
[Lint] --> [Test (matrix)] --> [Build Docker] --> [Push to GHCR]
                                                       |
                                                       v
                                               [Deploy to staging]
                                                       |
                                                  (approval)
                                                       |
                                                       v
                                               [Deploy to prod]
                                                       |
                                                       v
                                                [Smoke test]
```

## Gotchas

1. `GITHUB_TOKEN` permissions are read-only by default in forks. Need `packages: write` for GHCR pushes.
2. `actions/checkout@v4` only fetches a shallow clone. Need `fetch-depth: 0` for version tagging.
3. Docker build context in Actions uses the repo root, not the workflow file location.
4. Reusable workflows can't access secrets from the caller unless you explicitly pass them or use `secrets: inherit`.
