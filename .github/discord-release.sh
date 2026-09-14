#!/usr/bin/env bash
# Post a release's changelog section to Discord. Called by release.yml with the
# tag name; reads DISCORD_WEBHOOK from the environment.
#
# The section is lifted from CHANGELOG.md rather than the commit log, to match
# what CurseForge and Wago show.

set -euo pipefail

TAG=${1:?usage: discord-release.sh <tag>}
VERSION=${TAG#v}
REPO=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}
NAME=${REPO##*/}
CHANGELOG="$(dirname "${BASH_SOURCE[0]}")/../CHANGELOG.md"

# Everything between this version's heading and the next one.
NOTES=$(awk -v v="## $VERSION" '
    $0 == v { on = 1; next }
    on && /^## / { exit }
    on { print }
' "$CHANGELOG" | sed -e 's/^### /**/; s/^\*\*\(.*\)$/**\1**/' )

# Trim leading and trailing blank lines.
NOTES=$(printf '%s\n' "$NOTES" | sed -e '/./,$!d' | tac | sed -e '/./,$!d' | tac)

if [[ -z $NOTES ]]; then
    echo "No CHANGELOG.md section for $VERSION; posting the link alone." >&2
    NOTES="No changelog section for this release."
fi

# Discord caps an embed description at 4096 characters.
if (( ${#NOTES} > 4000 )); then
    NOTES="${NOTES:0:4000}"$'\n\n[...]'
fi

jq -n \
    --arg title "$NAME $TAG" \
    --arg desc "$NOTES" \
    --arg name "$NAME" \
    --arg url "https://github.com/$REPO/releases/tag/$TAG" \
    '{
        username: $name,
        embeds: [{
            title: $title,
            description: $desc,
            url: $url,
            color: 10181046
        }]
    }' > /tmp/discord-release.json

curl -sS -f -X POST -H "Content-Type: application/json" \
    --data-binary @/tmp/discord-release.json "$DISCORD_WEBHOOK"

echo "Posted $TAG to Discord."
