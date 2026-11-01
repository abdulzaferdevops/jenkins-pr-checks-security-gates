# jenkins-pr-checks-security-gates

Pull request checks with security gates, on a Jenkins controller running on Oracle Cloud
Infrastructure. Every pull request runs five gates in parallel and reports each one back to
GitHub as its own status check. Branch protection on `main` requires all five, so nothing is
merged until tests, secret scanning, static analysis, dependency scanning and Dockerfile
linting all pass.

Lab 8 of a series of CI/CD labs on OCI (GitHub · Jenkins · Docker · Oracle Linux). The sample
application is the Inventory API from the earlier labs; the pipeline uses the
[ci-labs shared library](https://github.com/abdulzaferdevops/jenkins-shared-library) (Lab 6).

## Flow

```mermaid
flowchart LR
  pr[Pull request opened<br/>or updated] -->|webhook| j[Jenkins multibranch job]
  j --> g{Five gates<br/>in parallel}
  g --> t[ci/tests]
  g --> s[ci/secrets]
  g --> a[ci/sast]
  g --> d[ci/dependencies]
  g --> f[ci/dockerfile]
  t & s & a & d & f -->|commit status| gh[GitHub pull request]
  gh -->|branch protection:<br/>all five required| m[Merge allowed]
```

## Gates

| Status check | Tool | Fails when |
|:--|:--|:--|
| `ci/tests` | flake8, pytest, pytest-cov | lint error, failing test, or coverage below 90% |
| `ci/secrets` | gitleaks 8.21 | a secret anywhere in the git history (output redacted) |
| `ci/sast` | bandit 1.7 | a finding of medium or higher severity **and** confidence |
| `ci/dependencies` | Trivy 0.56 | a HIGH or CRITICAL vulnerability that has a fixed version |
| `ci/dockerfile` | hadolint 2.12 | a warning or error in the Dockerfile |

Each gate reports `pending` when the build starts and `success` or `failure` when it ends. All
five always run, so one pull request shows every problem at once rather than one per push.

## Design decisions

- **Gates run on a copy, not a mount.** `ci/in-container.sh` creates a throwaway container,
  copies the workspace into it with `docker cp`, runs the check, and copies the reports back.
  Earlier labs used `--volumes-from` the Jenkins container, which also exposes `JENKINS_HOME`
  (credentials, other jobs). Here, test code and dependencies from a pull request cannot read
  Jenkins' secrets.
- **No pull requests from forks.** Building a fork runs a stranger's code on a controller
  that can reach Docker. Only branches in this repository are discovered.
- **The pull request head is built, and branch protection requires it to be up to date with
  `main`.** That gives the same guarantee as building a merge commit, and the statuses land on
  a commit GitHub knows.
- **Statuses go straight to the GitHub REST API** (`POST /repos/{repo}/statuses/{sha}`) with the
  job's own fine-grained token, so no extra Jenkins plugin is needed.
- **Reporting fails safe.** If Jenkins cannot post a status, the required check is missing
  and GitHub still blocks the merge.
- **A new push cancels the previous run** for the same pull request
  (`disableConcurrentBuilds(abortPrevious: true)`).
- **Secrets are scanned across history**, not just the latest commit: deleting a key in a
  later commit leaves it in git history, and the key must be rotated.

## Jenkins setup

- Multibranch Pipeline, branch source **GitHub**, credential: a fine-grained personal access
  token limited to this repository (Commit statuses: read and write; Contents, Pull requests:
  read-only).
- Behaviours: discover branches (excluding branches that are also pull requests), discover
  pull requests from origin (the current pull request revision), no fork discovery.
- Webhook events: pushes and pull requests.

## Results

| Change | Commit | Gates | Outcome |
|:--|:--|:--|:--|
| `?sort=` built with `eval` | `c30a298` | `ci/sast` ❌ bandit B307 (CWE-78); tests ✅ 14 passed, 100% coverage | Merge blocked: the unsafe code passed every test |
| Fixed with an allow-list, plus a test for `?sort=__class__` → 400 | `0b91d7c` | all five ✅, 15 tests | PR #1 merged |
| API key committed in `app/config.py` | `6218fb7` | `ci/secrets` ❌ gitleaks `generic-api-key`, value redacted in the log | Blocked |
| Key deleted in a follow-up commit | `3ecdc91` | `ci/secrets` still ❌: the key is in history (`6218fb7`) | Branch deleted unmerged; in real life, rotate the key |
| `urllib3==1.26.4` added | `2008f67` | `ci/dependencies` ❌ Trivy: **8 HIGH** CVEs (CVE-2021-33503 … ) | Blocked; the table gives the fixed version |
| Upgraded to `urllib3==2.8.0` | `fe9901e` | all five ✅ | Merged |

Direct pushes to `main` are rejected (`GH006: Protected branch update failed … 5 of 5 required status
checks are expected`), including for the repository owner. This README change itself went in
through a pull request.

## Licence

MIT
