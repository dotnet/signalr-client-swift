# Supply-chain work report: signalr-client-swift

Branch `feature/supply-chain`, based on `dev` at `e9a4d8f`. Status: COMPLETE.

This repository is a fork of `dotnet/signalr-client-swift`. An earlier run
stopped at step 1 for that reason. The owner knew about the fork status and
chose to proceed on `dev`, the GitHub default branch. All pushes went to the
`origin` remote (`springtreesolutions`), never to `upstream` (`dotnet`).

## What was done

### Step 1: caller workflow

Added `.github/workflows/compliance.yml`, byte-for-byte identical to the
starter (checked with `cmp`). It runs the four `supply-chain / *` gates on
every pull request.

### Step 2: quarantine config

Skipped. The repository has no `package.json` and no Bun lockfile. This is a
Swift package (`Package.swift`).

### Step 3: CODEOWNERS

Added `.github/CODEOWNERS` with exactly the three lines from the steps
document. No CODEOWNERS file existed before (checked root, `.github/` and
`docs/`). Only the policy files need an admin review.

### Step 4: gitleaks pre-push hook

Route A. No hook manager found: no `.husky/`, no `package.json` (so no
`prepare` script or `simple-git-hooks`), no `lefthook` config, no
`.pre-commit-config.yaml`, and `core.hooksPath` was not set. Copied the
starter hook unchanged to `.githooks/pre-push` (mode 100755) and ran
`git config core.hooksPath .githooks` in this clone.

Self-test output:

```
Scanning 9f2e668c42d7e0f1dd35d06bc94f15ee8004b608..6eb1d3989b55edf9c11639b3c4904b48f9243816 for secrets
INF 1 commits scanned.
INF scanned ~2939 bytes (2.94 KB) in 71ms
INF no leaks found
exit=0
```

### Step 5: README

Kept the upstream README as it is. Added three sections at the end:

- Branch strategy and protection: `dev` is the default branch, protected by
  the organisation ruleset "Enforce PR workflow" (pull request required,
  code-owner review, squash or rebase merges, linear history, no force push,
  no deletion). Lists the policy-file review, the four checks, the other
  branches (`feat/swarm`, `feature/connection-status`,
  `feature/custom-json-decoder`) and that the fork has no `main`.
- Compliance: copied from the starter, Route A install instructions, no Bun
  text.
- Deploying: the package is consumed from git by Swift Package Manager. It
  describes what each upstream workflow does on this fork and where it refers
  to a branch or secret the fork does not have.

### Step 6: long-lived tokens

Listed every secret in the three upstream workflows. See the table below. No
workflow was changed.

## Notes

- This repository is one of 22 sharing the `0 5 * * 1` cron schedule in
  compliance.yml. The file was kept unchanged per instructions; an admin can
  stagger the minute later.
- The fork has no tags on `origin`. The `v1.0.0` and preview tags in a local
  clone come from the `upstream` remote.
- The README "Installation" section (upstream content, unchanged) points apps
  at `https://github.com/dotnet/signalr-client-swift`, not at this fork.
- `swift.yml` and `swift-e2e.yml` also trigger on `main`, which this fork does
  not have. That is harmless.
- `swift-e2e.yml` prints the first 20 characters of `E2E_CONNECTION_STRING` to
  the job log ("Starts with: ..."). GitHub masks only the full secret value,
  not a substring, so part of the connection string is visible in the log.
- `gh secret list` for the repository returned no secrets, so
  `E2E_CONNECTION_STRING` is not a repository secret here. Organisation
  secrets could not be checked (HTTP 403).
- `release.yml` checks out `main`, which this fork does not have, so it fails
  at checkout if someone runs it.

## Tokens found (step 6)

| Secret name | File | Used for | Proposed replacement or why it cannot be replaced |
| --- | --- | --- | --- |
| `E2E_CONNECTION_STRING` | `.github/workflows/swift-e2e.yml` (lines 37, 54) | Azure SignalR Service connection string (contains an access key) for the E2E tests. Passed to the .NET test server; the first 20 characters are echoed to the job log. | Not set on this fork. Options: delete or disable `swift-e2e.yml` on the fork if E2E tests against Azure are not needed. If they are needed, use Workload Identity Federation (OIDC) with an Azure AD identity instead of an access-key connection string. Upstream has a branch `xingsy97/e2e-oidc-azure-auth` that appears to move in that direction. In any case, remove the "Starts with" echo. |
| `GITHUB_TOKEN` | `.github/workflows/release.yml` (line 77) | Opens the version-bump pull request. | Short-lived. Fine. |

Workflows that push straight to the default branch: none. `release.yml` pushes
a tag (`git push origin "$TAG"`) with the default `GITHUB_TOKEN` and opens the
version bump as a pull request, not as a direct push. It targets `main`, which
does not exist here. If this fork needs releases, move to release-please with
a GitHub App token.

## Blockers

None.

## Questions for the owner

1. Is GitHub Actions enabled for this fork? The Actions permissions endpoint
   returned HTTP 403 for this token, so this could not be checked. GitHub
   disables workflows on forks by default. If Actions is off, the four
   `supply-chain / *` checks will never report.
2. Should the upstream workflows stay on the fork? `swift-e2e.yml` fails
   without `E2E_CONNECTION_STRING`, and `release.yml` fails because there is
   no `main`.
3. Does an organisation secret named `E2E_CONNECTION_STRING` exist and reach
   this repository? Organisation secrets could not be listed (HTTP 403).
4. How do SpringTree apps consume this fork (branch, commit, or a future tag)?
   The Deploying section says a branch or commit, because the fork has no tags
   and no working release workflow.

## Still to do (steps 7 and 8, out of scope here)

Open the PR against `dev`, watch the four `supply-chain / *` checks, fix findings, hand off to an admin with the token list.
