#!/bin/bash -eEu

set -eEux
set -o pipefail
shopt -s extglob

GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY:-/proc/self/fd/1}
while read line; do
    read -r SUBMODULE_SHA SUBMODULE_NAME SUBMODULE_DESCRIBE <<<"$line"

    SUBMODULE_SHA=${SUBMODULE_SHA:1}
    GIT_CONFIG="$(git config -f .gitmodules -l | grep 'submodule.'$SUBMODULE_NAME.)"
    SUBMODULE_URL="$(echo "$GIT_CONFIG" | grep 'submodule.'$SUBMODULE_NAME'.url=' | sed 's/submodule\.'$SUBMODULE_NAME'\.url=//')"
    SUBMODULE_PATH="$(echo "$GIT_CONFIG" | grep 'submodule.'$SUBMODULE_NAME'.path=' | sed 's/submodule\.'$SUBMODULE_NAME'\.path=//')"
    SUBMODULE_BRANCH="$(echo "$GIT_CONFIG" | grep 'submodule.'$SUBMODULE_NAME'.branch=' | sed 's/submodule\.'$SUBMODULE_NAME'\.branch=//')"

    read -ra SUBMODULE_TAGS <<<"$(cd $SUBMODULE_PATH; git tag --points-at HEAD)"

    if [ ${#SUBMODULE_TAGS[@]} -gt 0 ]; then
        for tag in "${SUBMODULE_TAGS[@]}"; do
            TAG_FOUND="$(git tag --points-at HEAD | (grep $tag || true) )"
            if [ -z "$TAG_FOUND" ]; then
                git tag $tag
                git push origin HEAD --tags
            fi
        done
    fi
done <<< "$(git submodule status)"
