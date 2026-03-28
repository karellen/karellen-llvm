#!/bin/bash

set -eEu
set -o pipefail

# Upload wheels from GitHub releases that are missing on PyPI.
# Only processes incomplete releases (where some but not all wheels were uploaded).
# Requires: gh, curl, python3, twine
# Environment: TWINE_USERNAME, TWINE_PASSWORD (or ~/.pypirc)

REPO="${GITHUB_REPOSITORY:-karellen/karellen-llvm}"
DRY_RUN="${DRY_RUN:-}"
RELEASE_LIMIT="${RELEASE_LIMIT:-10}"
WHEEL_DIR="$(mktemp -d)"
trap 'rm -rf "$WHEEL_DIR"' EXIT

parse_wheel() {
    # Parse wheel filename into package name and version.
    # karellen_llvm_core-22.1.1.post23-py3-none-manylinux_2_28_x86_64.whl
    # -> karellen-llvm-core 22.1.1.post23
    python3 -c "
import re, sys
fn = sys.argv[1]
m = re.match(r'^([A-Za-z0-9](?:[A-Za-z0-9._]*[A-Za-z0-9])?)-(\d[^-]*)-', fn)
if m:
    name = m.group(1).replace('_', '-')
    version = m.group(2)
    print(f'{name}\t{version}')
else:
    sys.exit(1)
" "$1"
}

get_pypi_filenames() {
    # Fetch all filenames on PyPI for a given package/version.
    # Returns one filename per line, or nothing if the version doesn't exist.
    local package="$1"
    local version="$2"

    curl -s -f "https://pypi.org/pypi/${package}/${version}/json" 2>/dev/null \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data.get('urls', []):
    print(f['filename'])
" 2>/dev/null || true
}

MISSING_COUNT=0
UPLOADED_COUNT=0
SKIPPED_RELEASES=0
CHECKED_RELEASES=0

echo "Checking GitHub releases for $REPO..."

while IFS=$'\t' read -r tag title; do
    # Collect all wheel assets for this release
    declare -a WHEELS=()
    while read -r asset_name; do
        [ -z "$asset_name" ] && continue
        case "$asset_name" in
            *.whl) WHEELS+=("$asset_name") ;;
        esac
    done < <(gh release view "$tag" -R "$REPO" --json assets -q '.assets[].name')

    [ ${#WHEELS[@]} -eq 0 ] && continue

    # Extract the version from the first wheel (all wheels in a release share the same version)
    IFS=$'\t' read -r first_package first_version < <(parse_wheel "${WHEELS[0]}") || continue

    # Collect all PyPI filenames for this version across all packages in one pass
    declare -A PYPI_FILES=()
    declare -A SEEN_PACKAGES=()
    for whl in "${WHEELS[@]}"; do
        IFS=$'\t' read -r pkg ver < <(parse_wheel "$whl") || continue
        if [ -z "${SEEN_PACKAGES[$pkg]+x}" ]; then
            SEEN_PACKAGES[$pkg]=1
            while read -r pypi_fn; do
                [ -n "$pypi_fn" ] && PYPI_FILES[$pypi_fn]=1
            done < <(get_pypi_filenames "$pkg" "$ver")
        fi
    done

    # Count how many wheels are already on PyPI
    local_on_pypi=0
    local_missing=0
    declare -a MISSING_WHEELS=()
    for whl in "${WHEELS[@]}"; do
        if [ -n "${PYPI_FILES[$whl]+x}" ]; then
            local_on_pypi=$((local_on_pypi + 1))
        else
            local_missing=$((local_missing + 1))
            MISSING_WHEELS+=("$whl")
        fi
    done

    CHECKED_RELEASES=$((CHECKED_RELEASES + 1))

    if [ "$local_on_pypi" -eq 0 ]; then
        # Nothing on PyPI — skip entirely (never uploaded)
        SKIPPED_RELEASES=$((SKIPPED_RELEASES + 1))
        echo ""
        echo "=== Release: $tag — skipped (no wheels on PyPI) ==="
        unset WHEELS PYPI_FILES SEEN_PACKAGES MISSING_WHEELS
        continue
    fi

    if [ "$local_missing" -eq 0 ]; then
        echo ""
        echo "=== Release: $tag — complete ==="
        unset WHEELS PYPI_FILES SEEN_PACKAGES MISSING_WHEELS
        continue
    fi

    echo ""
    echo "=== Release: $tag — ${local_on_pypi} on PyPI, ${local_missing} missing ==="
    MISSING_COUNT=$((MISSING_COUNT + local_missing))

    for whl in "${MISSING_WHEELS[@]}"; do
        IFS=$'\t' read -r pkg ver < <(parse_wheel "$whl") || continue
        echo "  MISSING: $whl ($pkg $ver)"

        if [ -z "$DRY_RUN" ]; then
            gh release download "$tag" -R "$REPO" -p "$whl" -D "$WHEEL_DIR" --clobber

            if twine upload --non-interactive --skip-existing "$WHEEL_DIR/$whl"; then
                UPLOADED_COUNT=$((UPLOADED_COUNT + 1))
                echo "  UPLOADED: $whl"
            else
                echo "  FAILED: $whl" >&2
            fi

            rm -f "$WHEEL_DIR/$whl"
        fi
    done

    unset WHEELS PYPI_FILES SEEN_PACKAGES MISSING_WHEELS
done < <(gh release list -R "$REPO" --limit "$RELEASE_LIMIT" --json tagName,name -q '.[] | [.tagName, .name] | @tsv')

echo ""
echo "=== Summary ==="
echo "Releases checked: $CHECKED_RELEASES"
echo "Releases skipped (not on PyPI): $SKIPPED_RELEASES"
echo "Missing wheels (incomplete releases): $MISSING_COUNT"
if [ -z "$DRY_RUN" ]; then
    echo "Uploaded: $UPLOADED_COUNT"
    echo "Failed: $((MISSING_COUNT - UPLOADED_COUNT))"
else
    echo "(dry run — nothing uploaded)"
fi
