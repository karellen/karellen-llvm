#!/bin/bash

set -eEux
set -o pipefail

OLD_PATH=$PATH
PYTHON=$(which python)
PYTHON_VER="$($PYTHON -c 'import sys; print("".join(map(str, sys.version_info[:2])))')"
PYTHON_VENV="$(readlink -nf ./venv-cp$PYTHON_VER)"
$PYTHON -m venv $PYTHON_VENV
PATH=$PYTHON_VENV/bin:$OLD_PATH
export PATH
PYTHON=$PYTHON_VENV/bin/python

"$PYTHON" -m pip install --no-input $(ls -f wheels/*py3-none*.whl wheels/*cp$PYTHON_VER*.whl 2>/dev/null || true)
"$PYTHON" -c pass
which clang
clang --version
which lldb
lldb --version
if [ "$PYTHON_VER" != "312" ]; then
    $PYTHON -c "import lldb;"
fi
