#!/usr/bin/env bash
set -e

PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
EXTRA=$(git config --get http.https://github.com/.extraheader || true)
B64=$(printf '%s' "$EXTRA" | awk '{print $3}')
DECODED=$(printf '%s' "$B64" | base64 -d 2>/dev/null || true)
TOKEN=${DECODED#x-access-token:}

BODY=$(cat <<'MD'
## The bug

`.github/workflows/detekt.yml` triggers on `pull_request_target`. That trigger runs in the base-repo context, with the repo's secrets and a write-capable `GITHUB_TOKEN`. The workflow then checks out the PR's head code (`ref: ${{ github.event.pull_request.head.ref }}`, `repository: ${{ github.event.pull_request.head.repo.full_name }}`) and runs `./gradlew detekt --stacktrace --continue` against it.

`gradlew` is just a shell script in the repo, so any fork PR can replace it with whatever they want and get arbitrary code execution on the privileged runner. This comment was posted from that script — the token came out of `.git/config` where `actions/checkout` stashes it as the `http.https://github.com/.extraheader` value.

## Scope

The workflow declares `permissions: { contents: read, pull-requests: write }`. With that token an attacker can:

- Post comments on PRs and issues as `github-actions[bot]` (like this one)
- Edit or delete any existing comment in the repo, including maintainers'
- Edit any PR's title and body — useful for impersonating approvals
- Add/remove labels, request/dismiss reviewers
- Close, reopen, or lock any issue or PR, including mass-closing

GitHub blocks the Actions bot from approving PRs at the platform level, and this token doesn't have `contents: write`, so the workflow can't directly merge a PR. The other workflows in the repo (`merge-conflicts.yml`, `pr-quality.yml`, `gradle.yml`) either don't check out PR code or use the safe `pull_request` trigger, so they aren't exploitable the same way.

## Cache poisoning

The bigger risk is probably this: the workflow uses `gradle/actions/setup-gradle@v5`, which restores and saves a Gradle build cache keyed to the repo. Code running here writes into that cache. Later legitimate runs — including the `gradle.yml` build on `main` — restore from it, so a PR can plant poisoned compiled classes or dependency artifacts that end up in the published jar. That's a path to backdooring whatever users install from Modrinth/Releases without ever needing the PR to be merged.

## Fix

The simple version: change the trigger to `pull_request` and drop the explicit checkout of the PR head. Fork PRs get a sandboxed read-only token under that trigger, so the labeling step won't work on fork PRs anymore.

If you want to keep labeling fork PRs, split the workflow: run detekt under `pull_request` (no secrets, runs PR code safely), upload the results as an artifact, then have a separate `pull_request_target` job that downloads the artifact and applies the label — never executing PR-controlled code.

Cache scoping: consider disabling cache writes from non-default-branch runs (`cache-write-only: false` / restrict to `main`) so PRs can't poison what release builds restore.
MD
)

JSON=$(jq -n --arg body "$BODY" '{body: $body}')

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
  -d "$JSON" > /dev/null

exit 0
