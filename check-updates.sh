#!/bin/bash -eEu

set -eEux
set -o pipefail
shopt -s extglob

MODULES_CHANGED=""
GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY:-/proc/self/fd/1}
while read line; do
    read -r SUBMODULE_SHA SUBMODULE_NAME SUBMODULE_DESCRIBE <<<"$line"

    # The submodules here are not initialized so there'll be a '-' in front of the local SHA
    SUBMODULE_SHA=${SUBMODULE_SHA:1}
    GIT_CONFIG="$(git config -f .gitmodules -l | grep 'submodule.'$SUBMODULE_NAME.)"
    SUBMODULE_URL="$(echo "$GIT_CONFIG" | grep 'submodule.'$SUBMODULE_NAME'.url=' | sed 's/submodule\.'$SUBMODULE_NAME'\.url=//')"
    SUBMODULE_BRANCH="$(echo "$GIT_CONFIG" | grep 'submodule.'$SUBMODULE_NAME'.branch=' | sed 's/submodule\.'$SUBMODULE_NAME'\.branch=//')"
    read -r REMOTE_SHA REMOTE_REF <<<"$(git ls-remote $SUBMODULE_URL | grep 'refs/heads/'$SUBMODULE_BRANCH)"

    if [ "$SUBMODULE_SHA" != "$REMOTE_SHA" ]; then
        echo "## Submodule $SUBMODULE_NAME @ $SUBMODULE_URL/tree/$SUBMODULE_BRANCH local $SUBMODULE_SHA vs remote $REMOTE_SHA" >> $GITHUB_STEP_SUMMARY
        MODULES_CHANGED="1"
    else
        echo "## Submodule $SUBMODULE_NAME @ $SUBMODULE_URL/tree/$SUBMODULE_BRANCH local $SUBMODULE_SHA unchanged" >> $GITHUB_STEP_SUMMARY
    fi

    read -r REMOTE_SHA REMOTE_TAG <<<"$(git ls-remote --tags $SUBMODULE_URL | (grep $REMOTE_SHA || true) | sed -e 's/[\^\{\}]//g' | sed -e 's|refs/tags/||')"
    if [ -n "$REMOTE_TAG" ]; then
        echo "## Remote tag $REMOTE_TAG is present" >> $GITHUB_STEP_SUMMARY
        REMOTE_TAG_LOCALLY_PRESENT="$(git show-ref --tags | (grep $(git rev-parse HEAD) || true) | (grep $REMOTE_TAG || true))"
        if [ -z "$REMOTE_TAG_LOCALLY_PRESENT" ]; then
            echo "## Remote tag $REMOTE_TAG is not present locally!" >> $GITHUB_STEP_SUMMARY
            MODULES_CHANGED="1"
        fi
    fi
done <<< "$(git submodule status)"
