#!/bin/bash
# in-container.sh <image> [docker create options...] -- <command and arguments...>
#
# Runs one check in a throwaway container that gets a COPY of the workspace at /src.
# Unlike `--volumes-from <jenkins>`, the container never sees JENKINS_HOME, so code
# from a pull request (tests, dependencies, build scripts) cannot read Jenkins'
# credentials or other jobs' workspaces. Files the check writes to /src/reports
# are copied back to ./reports. The exit code is the check's exit code.
set -euo pipefail

image="${1:?usage: in-container.sh <image> [docker options...] -- <command...>}"
shift
opts=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  opts+=("$1")
  shift
done
[ "${1:-}" = "--" ] && shift

# safe.directory: the copied repository is owned by another user than the check runs as
cid=$(docker create --user 0:0 -w /src \
  --label "ci-labs.job=${JOB_NAME:-local}" --label "ci-labs.build=${BUILD_NUMBER:-0}" \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
  ${opts[@]+"${opts[@]}"} "$image" "$@")
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT

docker cp "$PWD/." "$cid:/src"
rc=0
docker start -a "$cid" || rc=$?

mkdir -p reports
docker cp "$cid:/src/reports/." reports/ >/dev/null 2>&1 || true
exit "$rc"
