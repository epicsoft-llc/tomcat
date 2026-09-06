#!/bin/bash

#### Removes what the test environment created. Runs on its own:
####
####   bash test/clean.sh env      the containers
####   bash test/clean.sh all      additionally the built test images and the logs
####   bash test/clean.sh --help   this text
####
#### Called without an argument it prints this text - it removes things, so an accidental
#### call should not be the one that does it.
####
#### 'test.sh' calls 'env' at the end of a run and on an interrupt, but a run that is
#### killed hard leaves things behind. Nothing here has to know what ran: everything the
#### tests create carries the label 'tomcat-test', so removing by label catches the
#### leftovers of any run in any state - including a server that is still up.

# Git Bash rewrites arguments that look like a unix path into a windows path before
# docker sees them
export MSYS_NO_PATHCONV=1

readonly CLEAN_LABEL="tomcat-test"
readonly CLEAN_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLEAN_LOG_DIR="${CLEAN_DIR}/.logs"

usage() {
  awk '
    /^####/ { started = 1; sub(/^#### ?/, ""); print; next }
    started { exit }
  ' "$0"
}

CLEAN_ALL="false"

case "${1:-}" in
  env ) ;;
  all ) CLEAN_ALL="true" ;;
  --help | -h | "" ) usage; exit 0 ;;
  * ) echo "unknown argument '${1}'"; echo; usage; exit 1 ;;
esac

cleanRemove() {
  local _WHAT=${1}
  local _IDS=${2}
  local _KIND=${3}

  if [ -z "${_IDS}" ]; then
    return 0
  fi

  echo "  removing ${_WHAT}: $(echo "${_IDS}" | wc -w)"
  echo "${_IDS}" | xargs docker "${_KIND}" rm -f > /dev/null 2>&1
}

echo "Cleaning up the test environment"

cleanRemove "container(s)" "$(docker ps -a -q --filter "label=${CLEAN_LABEL}")" "container"

# The official tomcat images are deliberately kept even with 'all': they are the base of
# every build here and belong to other things too, and pulling them again is by far the
# slowest part of a run. Only the images built here carry the label.
if [ "${CLEAN_ALL}" == "true" ]; then
  cleanRemove "image(s)" "$(docker image ls -q --filter "label=${CLEAN_LABEL}")" "image"

  if [ -d "${CLEAN_LOG_DIR}" ]; then
    echo "  removing logs"
    rm -rf "${CLEAN_LOG_DIR}"
  fi
fi

echo "Done"
