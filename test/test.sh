#!/bin/bash

#### Local test environment for the tomcat image. Everything happens in containers:
#### the image is built here, the assertions run inside throwaway containers and, for the
#### integration groups, against a really started Tomcat. Nothing is written to the host
#### except the logs under 'test/.logs'.
####
####   bash test/test.sh default            docs unit image tomcat custom
####   bash test/test.sh all                additionally 'versions' (builds every tag)
####   bash test/test.sh unit               only these groups
####   bash test/test.sh --keep tomcat      leave the containers up afterwards
####   bash test/test.sh --list             print the group names
####   bash test/test.sh --help             this text
####
#### The base image the tests build against is 'tomcat:latest'; set TOMCAT_TEST_TAG to
#### use another tag of the official image, and TOMCAT_TEST_VERSIONS to narrow the
#### 'versions' group down to the tags that are actually in question:
####
####   TOMCAT_TEST_TAG=9-jre11 bash test/test.sh default
####   TOMCAT_TEST_VERSIONS="9-jre11 latest" bash test/test.sh versions
####
#### Called without an argument it prints this help: the run pulls the tomcat image and
#### starts servers, so it is not what an accidental call should start.
####
#### Clean up with 'bash test/clean.sh env', which this script also does on its own at the
#### end of a run and on an interrupt.

# Everything created here carries the docker label 'tomcat-test'. That is what lets
# 'clean.sh' remove the leftovers of an interrupted run without knowing what ran.
#
# Deliberately without 'set -e': a failed assertion has to be counted and the run has to
# continue, otherwise the first failure hides all the others.

# Git Bash rewrites arguments that look like a unix path into a windows path before
# docker sees them, which turns '/usr/local/tomcat/bin/catalina.sh' into a path inside
# the git installation
export MSYS_NO_PATHCONV=1

readonly TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
readonly LOG_DIR="${TEST_DIR}/.logs"
readonly WORK_DIR="${LOG_DIR}/work"

readonly LABEL="tomcat-test"
readonly PREFIX="tomcat-test"

# not 'tomcat:test': that name lives in the same repository as the official image this
# one is built FROM, so a stray '--build-arg IMAGE_TAG=test' would silently build the
# image on top of itself
readonly IMAGE="epicsoft-tomcat:test"
readonly CUSTOM_IMAGE="epicsoft-tomcat:test-custom"
readonly CUSTOM_PLAIN_IMAGE="epicsoft-tomcat:test-custom-plain"

# the tag of the official image the tests build on. every version is built in the
# 'versions' group; the other groups only need one
readonly BASE_TAG="${TOMCAT_TEST_TAG:-latest}"

# what a passed through value has to look like on the other side - proves the property
# carries the value and not just the name
readonly MARKER='tomcat-marker-42'

# a value nothing may pass on: it is set in variables that must be ignored, so a single
# 'not found' assertion covers every way the filter could go wrong
readonly NEVER='not-this-one'

readonly DEFAULT_GROUPS="docs unit image tomcat custom"
readonly ALL_GROUPS="docs unit image tomcat custom versions"

readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_RED='\033[0;31m'

KEEP="false"
TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILED_NAMES=()
RUN_OUTPUT=""
RUN_LOG=""

###############################################################################
#### Reporting
###############################################################################

section() {
  printf '\n\033[1m%s\033[0m\n' "${1}"
}

info() {
  printf '  ..   %s\n' "${1}"
}

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "  ${COLOR_GREEN}PASS${COLOR_RESET} %s\n" "${1}"
}

# the reason is printed right here, the full container log only on a failure - that is
# what keeps a green run to one line per case
fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_NAMES+=("${1}")

  printf "  ${COLOR_RED}FAIL${COLOR_RESET} %s\n" "${1}"

  if [ ! -z "${2}" ]; then
    printf '       %s\n' "${2}"
  fi

  if [ ! -z "${RUN_LOG}" ] && [ -f "${RUN_LOG}" ]; then
    printf '       log: %s\n' "${RUN_LOG}"
  fi
}

skip() {
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  printf "  ${COLOR_YELLOW}SKIP${COLOR_RESET} %s (%s)\n" "${1}" "${2}"
}

assertEquals() {
  if [ "${2}" == "${3}" ]; then
    pass "${1}"
  else
    fail "${1}" "expected '${2}', got '${3}'"
  fi
}

# compared with 'grep -F' and not with a case pattern: the needles hold quotes, dollar
# signs and backslashes, and a backslash in a case pattern escapes the next character -
# a needle like 'a\$b' would then match a haystack holding 'a$b' and turn a leak into a
# pass
containsText() {
  printf '%s' "${1}" | grep -q -F -- "${2}"
}

# the haystack goes into the message: 'not found' alone does not say whether the value
# was wrong or whether the command that produced it failed and returned its error instead
assertContains() {
  if containsText "${2}" "${3}"; then
    pass "${1}"
  else
    fail "${1}" "'${3}' not found in: ...$(printf '%s' "${2}" | tr '\n' ' ' | tail -c 200)"
  fi
}

assertNotContains() {
  if containsText "${2}" "${3}"; then
    fail "${1}" "'${3}' should not appear in: ...$(printf '%s' "${2}" | tr '\n' ' ' | tail -c 200)"
  else
    pass "${1}"
  fi
}

assertStartsWith() {
  case "${2}" in
    "${3}"* ) pass "${1}" ;;
    * ) fail "${1}" "'${2}' does not start with '${3}'" ;;
  esac
}

assertSucceeds() {
  if [ "${2}" == "0" ]; then
    pass "${1}"
    return 0
  fi

  fail "${1}" "the run exited with ${2}"

  return 1
}

###############################################################################
#### Docker helpers
###############################################################################

# Runs one bash snippet in a throwaway container of the image under test. The output goes
# to a log file and into RUN_OUTPUT, the exit code is the return value.
#
# '$0' is set to the path of catalina.sh, because that is what setenv.sh sees in a real
# start: catalina.sh sources it, so '$0' is still catalina.sh and 'dirname "$0"' is the
# bin directory. Without this the sourced script would resolve its directory to '.' and
# the test would pass or fail for a reason the real container never has.
runInImage() {
  local _NAME=${1}
  local _SCRIPT=${2}
  local _CODE=0

  shift 2

  RUN_LOG="${LOG_DIR}/${_NAME}.log"

  docker run --rm --label "${LABEL}" "${@}" "${IMAGE}" \
    bash -c "${_SCRIPT}" /usr/local/tomcat/bin/catalina.sh > "${RUN_LOG}" 2>&1 || _CODE=$?

  RUN_OUTPUT="$(cat "${RUN_LOG}")"

  return ${_CODE}
}

# the whole point of the image in one line: source the script the way catalina.sh does
# and print what it put into CATALINA_OPTS
runSetenv() {
  local _NAME=${1}

  shift

  runInImage "${_NAME}" 'source /usr/local/tomcat/bin/setenv.sh; echo "${CATALINA_OPTS}"' "${@}"
}

# starts a real server in the background. the caller passes everything after 'run -d',
# including the image, because the custom group starts a different one
startTomcat() {
  local _NAME=${1}

  shift

  docker rm -f "${_NAME}" > /dev/null 2>&1

  docker run -d --name "${_NAME}" --label "${LABEL}" "${@}" \
    > /dev/null 2>> "${LOG_DIR}/docker.log"
}

# A started container says nothing about a started server: the JVM needs a moment, and
# the properties under test are logged by the VersionLoggerListener during startup. So
# every integration case waits for a line that only a server that came all the way up
# writes.
waitForLog() {
  local _NAME=${1}
  local _NEEDLE=${2}
  local _TRIES=${3:-90}
  local _I=0

  while [ ${_I} -lt ${_TRIES} ]; do
    if docker logs "${_NAME}" 2>&1 | grep -q -F -- "${_NEEDLE}"; then
      return 0
    fi

    if [ -z "$(docker ps -q --filter "name=^/${_NAME}$")" ]; then
      break
    fi

    sleep 1
    _I=$((_I + 1))
  done

  # a group that gives up here only reports a skip, and a skip without a reason is the
  # kind of thing that gets ignored until it hides a real failure
  RUN_LOG="${LOG_DIR}/${_NAME}.log"
  docker logs "${_NAME}" > "${RUN_LOG}" 2>&1
  info "'${_NAME}' did not log '${_NEEDLE}' within ${_I}s, see ${RUN_LOG}"

  return 1
}

# the log is kept even for a container that is removed right away - it is the only record
# of what the server was told
tomcatLog() {
  RUN_LOG="${LOG_DIR}/${1}.log"

  docker logs "${1}" > "${RUN_LOG}" 2>&1

  cat "${RUN_LOG}"
}

stopTomcat() {
  if [ "${KEEP}" == "true" ]; then
    return 0
  fi

  docker rm -f "${1}" > /dev/null 2>&1
}

# What the official image reports about itself. A tag like '11.0-jre21' is a moving name,
# these are the versions actually in it - the same two lines the pipeline reads before a
# build, so the labels the tests assert are built the way the published ones are.
baseTomcatVersion() {
  docker run --rm --label "${LABEL}" "tomcat:${1}" /usr/local/tomcat/bin/version.sh 2>/dev/null \
    | sed -n 's/^Server number:[[:space:]]*//p'
}

baseJavaVersion() {
  docker run --rm --label "${LABEL}" "tomcat:${1}" /usr/local/tomcat/bin/version.sh 2>/dev/null \
    | sed -n 's/^JVM Version:[[:space:]]*//p'
}

# empty for an image that was never pulled from a registry - the label is then empty too,
# and the assertion still holds
baseDigest() {
  docker image inspect -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "tomcat:${1}" 2>/dev/null \
    | cut -d@ -f2
}

buildImage() {
  local _TAG=${1}
  local _VERSION=${2}
  local _LOG=${3}

  # Built from inside the project with '.' as the context: MSYS_NO_PATHCONV keeps git
  # bash from rewriting the container paths, but it would then also hand docker - a
  # windows binary - a '/c/...' build context it cannot resolve. A relative path needs no
  # rewriting either way.
  ( cd "${PROJECT_DIR}" && docker build -t "${_TAG}" --label "${LABEL}" \
      --build-arg "IMAGE_TAG=${_VERSION}" \
      --build-arg "BUILD_DATE=${BUILD_DATE}" \
      --build-arg "VCS_REF=${VCS_REF}" \
      --build-arg "TOMCAT_VERSION=$(baseTomcatVersion "${_VERSION}")" \
      --build-arg "JAVA_VERSION=$(baseJavaVersion "${_VERSION}")" \
      --build-arg "BASE_DIGEST=$(baseDigest "${_VERSION}")" . ) > "${_LOG}" 2>&1
}

# one label out of the image under test
imageLabel() {
  docker image inspect -f "{{index .Config.Labels \"${1}\"}}" "${IMAGE}" 2>&1
}

# the versions the pipeline builds, read out of the pipeline itself so this list cannot
# drift away from what is actually published
ciVersions() {
  grep -oE 'VERSION: "[^"]+"' "${PROJECT_DIR}/.gitlab-ci.yml" \
    | sed 's/^VERSION: "//; s/"$//'
}

# the same list as README.md states it - '`9-jre11` based on `tomcat:9-jre11`'
readmeVersions() {
  grep -oE '^`[^`]+` based on' "${PROJECT_DIR}/README.md" \
    | sed 's/^`//; s/` based on$//'
}

###############################################################################
#### Group: docs - the version list exists in three places and has to agree
###############################################################################

group_docs() {
  section "docs - the published versions match the build jobs"

  local _CI="$(ciVersions | sort | tr '\n' ' ')"
  local _README="$(readmeVersions | sort | tr '\n' ' ')"

  assertEquals "README.md lists exactly the versions .gitlab-ci.yml builds" "${_CI}" "${_README}"

  # A version job is its name and its VERSION, everything else comes from the '.build'
  # template - the rules that keep it off every branch above all. A job copied without the
  # 'extends' line would publish from anywhere, and that is not visible in its own lines.
  local _COUNT="$(ciVersions | wc -l | tr -d ' ')"
  local _EXTENDS="$(grep -c '^  extends: \.build$' "${PROJECT_DIR}/.gitlab-ci.yml")"

  assertEquals "every version job is built from the .build template" "${_COUNT}" "${_EXTENDS}"

  # README.md is not only documentation: the 'uploadReadme' job pushes it to docker hub
  # as the repository description, so the example there is what users copy
  assertContains "README.md documents the dockerenv.sh line for a custom setenv.sh" \
    "$(cat "${PROJECT_DIR}/README.md")" 'source $(dirname "$0")/dockerenv.sh'

  # a CRLF in the script survives into the image and the container dies with
  # "$'\r': command not found" - the same file is also the one users source
  if grep -q $'\r' "${PROJECT_DIR}/setenv.sh"; then
    fail "setenv.sh has unix line endings" "CRLF found - the image will not run"
  else
    pass "setenv.sh has unix line endings"
  fi
}

###############################################################################
#### Group: unit - what setenv.sh puts into CATALINA_OPTS, without a server
###############################################################################

group_unit() {
  section "unit - docker environments become -D properties"

  local _CODE=0

  ## the documented translation ###############################################
  runSetenv "unit-basic" -e "APP_DATABASE_NAME=${MARKER}" || _CODE=$?
  assertSucceeds "the script runs" "${_CODE}" \
    && assertContains "  APP_DATABASE_NAME becomes app.database.name" \
      "${RUN_OUTPUT}" "-Dapp.database.name='${MARKER}'"

  runSetenv "unit-deep-name" -e "APP_ONE_TWO_THREE_FOUR=${MARKER}"
  assertContains "every underscore of the name becomes a dot" \
    "${RUN_OUTPUT}" "-Dapp.one.two.three.four='${MARKER}'"

  # 'declare -u' uppercases before the prefix is matched, 'declare -l' lowercases the
  # property name afterwards - a name written in mixed case has to survive both
  runSetenv "unit-mixed-name" -e "APP_Mixed_Case=${MARKER}"
  assertContains "a name in mixed case ends up lower case" \
    "${RUN_OUTPUT}" "-Dapp.mixed.case='${MARKER}'"

  # the same 'declare' attributes must not reach the value: a lowercased password or
  # database name would be a bug nobody sees until the login fails
  runSetenv "unit-value-case" -e "APP_VALUE_CASE=MixedCaseValue"
  assertContains "the value keeps its case" "${RUN_OUTPUT}" "-Dapp.value.case='MixedCaseValue'"

  ## quoting in the docker environment ########################################
  runSetenv "unit-quotes-double" -e "APP_QUOTED_DOUBLE=\"${MARKER}\""
  assertContains "double quotes around the value are removed" \
    "${RUN_OUTPUT}" "-Dapp.quoted.double='${MARKER}'"

  runSetenv "unit-quotes-single" -e "APP_QUOTED_SINGLE='${MARKER}'"
  assertContains "single quotes around the value are removed" \
    "${RUN_OUTPUT}" "-Dapp.quoted.single='${MARKER}'"

  # catalina.sh expands CATALINA_OPTS through 'eval', so the single quotes written here
  # are what keeps a value with spaces one argument
  runSetenv "unit-spaces" -e "APP_CUSTOM_ENV1=Hello from Docker 1"
  assertContains "a value with spaces is quoted as one argument" \
    "${RUN_OUTPUT}" "-Dapp.custom.env1='Hello from Docker 1'"

  runSetenv "unit-spaces-quoted" -e "APP_CUSTOM_ENV2=\"Hello from Docker 2\""
  assertContains "the outer quotes go, the spaces stay" \
    "${RUN_OUTPUT}" "-Dapp.custom.env2='Hello from Docker 2'"

  ## names that cannot be a property name #####################################
  # The value is protected by the quoting, the name is not - it is read by the same eval.
  # A name with a space in it used to end the server before it started, with 'Could not
  # find or load main class' naming the value.
  runSetenv "unit-name-space" -e "APP_BROKEN NAME=${NEVER}" -e "APP_WANTED=${MARKER}"
  assertNotContains "a name with a space is not passed on" "${RUN_OUTPUT}" "${NEVER}"
  assertContains "  and says which one it dropped" "${RUN_OUTPUT}" "ignoring 'APP_BROKEN NAME'"
  assertContains "  the other variables are unaffected" "${RUN_OUTPUT}" "-Dapp.wanted='${MARKER}'"

  runSetenv "unit-name-quote" -e "APP_BROKEN'NAME=${NEVER}" -e "APP_WANTED=${MARKER}"
  assertNotContains "a name with a quote is not passed on" "${RUN_OUTPUT}" "${NEVER}"
  assertContains "  the other variables are unaffected" "${RUN_OUTPUT}" "-Dapp.wanted='${MARKER}'"

  runSetenv "unit-name-empty" -e "APP_=${NEVER}" -e "APP_WANTED=${MARKER}"
  assertNotContains "the bare prefix is not a name" "${RUN_OUTPUT}" "${NEVER}"
  assertNotContains "  and gives no empty property" "${RUN_OUTPUT}" "-Dapp.="
  assertContains "  the other variables are unaffected" "${RUN_OUTPUT}" "-Dapp.wanted='${MARKER}'"

  # 'declare -u' uppercases before the prefix is matched, so a lower case name works too.
  # Documented in README.md, and asserted here so it stays that way.
  runSetenv "unit-name-lower" -e "app_database_name=${MARKER}"
  assertContains "a lower case name works like the upper case one" \
    "${RUN_OUTPUT}" "-Dapp.database.name='${MARKER}'"

  ## what must not be passed on ###############################################
  runSetenv "unit-prefix" \
    -e "APP_WANTED=${MARKER}" \
    -e "DATABASE_NAME=${NEVER}" \
    -e "APPLE_PIE=${NEVER}" \
    -e "MY_APP_NAME=${NEVER}"
  assertContains "the prefixed variable is passed on" "${RUN_OUTPUT}" "-Dapp.wanted='${MARKER}'"
  assertNotContains "  and nothing without the APP_ prefix is" "${RUN_OUTPUT}" "${NEVER}"

  ## several at once, and what was already there ##############################
  runSetenv "unit-multiple" \
    -e "APP_ONE=one-${MARKER}" \
    -e "APP_TWO=two-${MARKER}" \
    -e "APP_THREE=three-${MARKER}"
  assertContains "the first of three variables is there" "${RUN_OUTPUT}" "-Dapp.one='one-${MARKER}'"
  assertContains "  the second too" "${RUN_OUTPUT}" "-Dapp.two='two-${MARKER}'"
  assertContains "  and the third" "${RUN_OUTPUT}" "-Dapp.three='three-${MARKER}'"

  # the script appends, it does not replace: a container that is given memory settings
  # must keep them
  runSetenv "unit-existing-opts" \
    -e "CATALINA_OPTS=-Xmx512m" \
    -e "APP_DATABASE_NAME=${MARKER}"
  assertContains "an existing CATALINA_OPTS is kept" "${RUN_OUTPUT}" "-Xmx512m"
  assertContains "  and the property is appended to it" \
    "${RUN_OUTPUT}" "-Dapp.database.name='${MARKER}'"

  ## edge cases in the value ##################################################
  _CODE=0
  runSetenv "unit-none" || _CODE=$?
  assertSucceeds "without APP_ variables the script still succeeds" "${_CODE}"
  assertEquals "  and leaves CATALINA_OPTS empty" "" "${RUN_OUTPUT}"

  runSetenv "unit-empty-value" -e "APP_EMPTY="
  assertContains "an empty value gives an empty property" "${RUN_OUTPUT}" "-Dapp.empty=''"

  # the loop splits on the first '=' only, everything after it is the value
  runSetenv "unit-equals" -e "APP_JDBC_URL=jdbc:mysql://db:3306/app?useSSL=false&x=1"
  assertContains "an '=' inside the value survives" \
    "${RUN_OUTPUT}" "-Dapp.jdbc.url='jdbc:mysql://db:3306/app?useSSL=false&x=1'"

  runSetenv "unit-inner-quotes" -e "APP_MESSAGE=say \"hi\" now"
  assertContains "quotes inside the value are not touched" \
    "${RUN_OUTPUT}" "-Dapp.message='say \"hi\" now'"

  ## only a real pair of quotes is taken off ##################################
  # a leading and a trailing quote removed on their own eat the last character here
  runSetenv "unit-quotes-not-a-pair" -e "APP_MESSAGE=he said \"hi\" and \"bye\""
  assertContains "quotes around parts of the value are kept" \
    "${RUN_OUTPUT}" "-Dapp.message='he said \"hi\" and \"bye\"'"

  runSetenv "unit-quotes-both-parts" -e "APP_MESSAGE=\"a\" and \"b\""
  assertContains "a value that only starts and ends with a quote is kept" \
    "${RUN_OUTPUT}" "-Dapp.message='\"a\" and \"b\"'"

  runSetenv "unit-quotes-unbalanced" -e "APP_PART=\"abc"
  assertContains "a single leading quote is not a pair" "${RUN_OUTPUT}" "-Dapp.part='\"abc'"

  runSetenv "unit-quotes-empty" -e "APP_EMPTY_QUOTED=\"\""
  assertContains "a pair of quotes around nothing gives an empty value" \
    "${RUN_OUTPUT}" "-Dapp.empty.quoted=''"

  # the inner pair belongs to the value, only the outer one is the docker notation
  runSetenv "unit-quotes-nested" -e "APP_NESTED=\"'x'\""
  assertContains "only the outer pair is removed" "${RUN_OUTPUT}" "-Dapp.nested=''\\''x'\\'''"

  # a password is the typical APP_ value, and these are the characters that break naive
  # quoting
  runSetenv "unit-special-chars" -e 'APP_PASSWORD=pa\ss wo#rd&1'
  assertContains "backslash, hash and ampersand in a value survive" \
    "${RUN_OUTPUT}" "-Dapp.password='pa\\ss wo#rd&1'"

  # A '$' has no business being expanded: the value is data. The generated
  # 'dockerappenv.sh' is sourced, so anything the shell still evaluates there runs with
  # the rights of the tomcat process.
  runSetenv "unit-no-expansion" -e 'APP_LITERAL=${HOME}/x'
  assertContains "a '\$' in the value is not expanded" "${RUN_OUTPUT}" "-Dapp.literal='\${HOME}/x'"

  runSetenv "unit-no-substitution" -e 'APP_INJECT=a$(id -u)b'
  assertContains "a command substitution in the value is not executed" \
    "${RUN_OUTPUT}" "-Dapp.inject='a\$(id -u)b'"
  assertNotContains "  and its output does not end up in CATALINA_OPTS" "${RUN_OUTPUT}" "-Dapp.inject='a0b'"

  ## nothing is written, nothing is left behind ###############################
  # The properties are put together in the shell of catalina.sh itself. Assembling them in
  # a file next to the script and sourcing that - the way this worked before - is what sent
  # every value through the shell a second time, and what made the image need a writable
  # filesystem to start.
  _CODE=0
  runSetenv "unit-read-only" --read-only -e "APP_DATABASE_NAME=${MARKER}" || _CODE=$?
  assertSucceeds "the script runs with a read-only filesystem" "${_CODE}" \
    && assertContains "  and still passes the variable on" \
      "${RUN_OUTPUT}" "-Dapp.database.name='${MARKER}'"

  runInImage "unit-no-leftovers" \
    'source /usr/local/tomcat/bin/setenv.sh; ls /usr/local/tomcat/bin | grep -c dockerappenv.sh' \
    -e "APP_DATABASE_NAME=${MARKER}"
  assertEquals "no generated file is left behind in bin/" "0" "${RUN_OUTPUT}"

  # it is sourced into the shell of catalina.sh, so it must not leave anything there that
  # a second source trips over - a 'readonly' at the top of the script was exactly that
  runInImage "unit-source-twice" \
    'source /usr/local/tomcat/bin/setenv.sh
     source /usr/local/tomcat/bin/dockerenv.sh
     echo "${CATALINA_OPTS}"' \
    -e "APP_DATABASE_NAME=${MARKER}"
  assertNotContains "sourcing it a second time does not complain" "${RUN_OUTPUT}" "readonly variable"

  # the same shell also runs the rest of catalina.sh afterwards
  runInImage "unit-no-variables-left" \
    'source /usr/local/tomcat/bin/setenv.sh; echo "[${_KEY}${_VALUE}${_K}${_V}]"' \
    -e "APP_DATABASE_NAME=${MARKER}"
  assertEquals "the helper variables are cleaned up" "[]" "${RUN_OUTPUT}"
}

###############################################################################
#### Group: image - what the Dockerfile put into the image
###############################################################################

group_image() {
  section "image - files, labels and the base image"

  runInImage "image-modes" 'stat -c "%a %n" /usr/local/tomcat/bin/setenv.sh /usr/local/tomcat/bin/dockerenv.sh'
  assertContains "setenv.sh is executable" "${RUN_OUTPUT}" "755 /usr/local/tomcat/bin/setenv.sh"
  assertContains "dockerenv.sh is executable" "${RUN_OUTPUT}" "755 /usr/local/tomcat/bin/dockerenv.sh"

  # the two copies are the extension point: a user who mounts an own setenv.sh sources
  # dockerenv.sh, so the second copy has to be the same script and not an older one
  runInImage "image-identical" \
    'cmp -s /usr/local/tomcat/bin/setenv.sh /usr/local/tomcat/bin/dockerenv.sh && echo identical || echo different'
  assertEquals "dockerenv.sh is a copy of setenv.sh" "identical" "${RUN_OUTPUT}"

  # sourced under its second name it has to do exactly the same thing - 'dirname "$0"'
  # resolves through catalina.sh either way
  runSetenv "image-dockerenv-name" -e "APP_DATABASE_NAME=${MARKER}"
  local _VIA_SETENV="${RUN_OUTPUT}"

  runInImage "image-dockerenv" 'source /usr/local/tomcat/bin/dockerenv.sh; echo "${CATALINA_OPTS}"' \
    -e "APP_DATABASE_NAME=${MARKER}"
  assertEquals "sourcing dockerenv.sh gives the same result" "${_VIA_SETENV}" "${RUN_OUTPUT}"

  # the smoke test the pipeline runs after every build
  local _VERSION="$(docker run --rm --label "${LABEL}" "${IMAGE}" /usr/local/tomcat/bin/version.sh 2>&1)"
  assertContains "version.sh reports a tomcat version" "${_VERSION}" "Server version: Apache Tomcat/"

  ## labels ###################################################################
  assertEquals "org.label-schema.version is the built tag" "${BASE_TAG}" "$(imageLabel org.label-schema.version)"
  assertEquals "org.label-schema.build-date is the build argument" "${BUILD_DATE}" "$(imageLabel org.label-schema.build-date)"
  assertEquals "org.label-schema.vcs-ref is the commit" "${VCS_REF}" "$(imageLabel org.label-schema.vcs-ref)"
  assertEquals "image.name identifies the image" "epicsoft_tomcat" "$(imageLabel image.name)"

  # the OCI keys are what registries and scanners read; they carry the same three build
  # arguments and must not fall behind the label-schema ones
  assertEquals "org.opencontainers.image.version is the built tag" \
    "${BASE_TAG}" "$(imageLabel org.opencontainers.image.version)"
  assertEquals "org.opencontainers.image.created is the build argument" \
    "${BUILD_DATE}" "$(imageLabel org.opencontainers.image.created)"
  assertEquals "org.opencontainers.image.revision is the commit" \
    "${VCS_REF}" "$(imageLabel org.opencontainers.image.revision)"
  assertEquals "org.opencontainers.image.base.name names the official image" \
    "docker.io/library/tomcat:${BASE_TAG}" "$(imageLabel org.opencontainers.image.base.name)"
  assertEquals "org.opencontainers.image.licenses is set" "MIT" "$(imageLabel org.opencontainers.image.licenses)"

  ## the versions behind the moving tag #######################################
  # 'latest' and '11.0-jre21' are names that hold something else every few weeks. These
  # labels are what says which Tomcat and which JRE a given image really is, and the digest
  # is what makes two builds of the same tag distinguishable at all.
  local _TOMCAT_VERSION="$(baseTomcatVersion "${BASE_TAG}")"

  assertEquals "image.tomcat.version is the version in the image" \
    "${_TOMCAT_VERSION}" "$(imageLabel image.tomcat.version)"
  assertEquals "image.java.version is the jre in the image" \
    "$(baseJavaVersion "${BASE_TAG}")" "$(imageLabel image.java.version)"
  assertEquals "org.opencontainers.image.base.digest is the digest it was built from" \
    "$(baseDigest "${BASE_TAG}")" "$(imageLabel org.opencontainers.image.base.digest)"

  # and it has to be the version of this image, not of the one the tag pointed at earlier
  assertContains "the label matches what the image itself reports" \
    "$(docker run --rm --label "${LABEL}" "${IMAGE}" /usr/local/tomcat/bin/version.sh 2>&1)" \
    "Server number:  ${_TOMCAT_VERSION}"
}

###############################################################################
#### Group: tomcat - the properties on the command line of a started server
###############################################################################

group_tomcat() {
  section "tomcat - a started server gets the properties"

  local _NAME="${PREFIX}-server"

  # no published port: the assertions read the log, and a bound port is one more thing
  # that can already be taken on the machine running the tests
  startTomcat "${_NAME}" \
    -e "APP_DATABASE_NAME=${MARKER}" \
    -e "APP_CUSTOM_ENV1=Hello from Docker 1" \
    -e "APP_CUSTOM_ENV2=\"Hello from Docker 2\"" \
    -e "APP_CUSTOM_ENV3='Hello from Docker 3'" \
    -e 'APP_PASSWORD=p'"'"'a"s$(id -u)w#1' \
    -e "APP_BROKEN NAME=${NEVER}" \
    -e "DATABASE_NAME=${NEVER}" \
    "${IMAGE}"

  if ! waitForLog "${_NAME}" "Server startup in"; then
    skip "the server starts with APP_ variables set" "it did not come up"
    stopTomcat "${_NAME}"
    return 0
  fi

  # the container in this case also carries a name that cannot become a property. Before
  # such a name was skipped it ended up as a second word on the java command line, and the
  # server died with 'Could not find or load main class' before it logged anything.
  pass "the server starts with APP_ variables set"

  local _LOG="$(tomcatLog "${_NAME}")"

  assertContains "an unusable name does not stop the start, it is reported" \
    "${_LOG}" "ignoring 'APP_BROKEN NAME'"

  # catalina.sh runs the java command through 'eval', which is what turns the single
  # quotes from setenv.sh back into one argument - so the log shows the bare value
  assertContains "the property is on the command line" \
    "${_LOG}" "Command line argument: -Dapp.database.name=${MARKER}"
  assertContains "a value with spaces arrives as one argument" \
    "${_LOG}" "Command line argument: -Dapp.custom.env1=Hello from Docker 1"
  assertContains "a value written with double quotes arrives unquoted" \
    "${_LOG}" "Command line argument: -Dapp.custom.env2=Hello from Docker 2"
  assertContains "a value written with single quotes arrives unquoted" \
    "${_LOG}" "Command line argument: -Dapp.custom.env3=Hello from Docker 3"
  assertNotContains "nothing without the prefix reaches the server" "${_LOG}" "${NEVER}"

  # the whole way through both quoting steps: the loop writes it into CATALINA_OPTS, the
  # eval in catalina.sh reads it back, and the JVM has to see the characters that were in
  # the compose file - a single quote, a double quote and a command substitution that is
  # part of a password and not a command
  assertContains "a password with quotes and a '\$(...)' arrives unchanged" \
    "${_LOG}" 'Command line argument: -Dapp.password=p'"'"'a"s$(id -u)w#1'

  stopTomcat "${_NAME}"

  ## a server without any APP_ variable #######################################
  # the image has to stay a plain tomcat when the feature is not used
  local _PLAIN="${PREFIX}-server-plain"

  startTomcat "${_PLAIN}" "${IMAGE}"

  if waitForLog "${_PLAIN}" "Server startup in"; then
    pass "the server starts without any APP_ variable"
    assertNotContains "  and gets no app properties" "$(tomcatLog "${_PLAIN}")" "-Dapp."
  else
    skip "the server starts without any APP_ variable" "it did not come up"
  fi

  stopTomcat "${_PLAIN}"
}

###############################################################################
#### Group: custom - an own setenv.sh, the way README.md describes it
###############################################################################

# The own setenv.sh is baked into a derived image instead of bind mounted: a single file
# cannot be mounted out of a named volume, and a bind mount would need a host path -
# which on a windows host is exactly the thing that behaves differently for every reader
# of this file. What is under test is the file at /usr/local/tomcat/bin/setenv.sh, and
# how it got there does not change what catalina.sh does with it.
buildCustomImages() {
  mkdir -p "${WORK_DIR}"

  cat > "${WORK_DIR}/setenv.sh" << 'EOF'
#!/bin/bash

export CATALINA_OPTS="$CATALINA_OPTS -Dcustom.marker=tomcat-custom-42"

#### Load Docker environments
source $(dirname "$0")/dockerenv.sh
EOF

  cat > "${WORK_DIR}/setenv-plain.sh" << 'EOF'
#!/bin/bash

export CATALINA_OPTS="$CATALINA_OPTS -Dcustom.marker=tomcat-custom-42"
EOF

  cat > "${WORK_DIR}/Dockerfile" << EOF
FROM ${IMAGE}
ARG SETENV
COPY \${SETENV} /usr/local/tomcat/bin/setenv.sh
RUN chmod 755 /usr/local/tomcat/bin/setenv.sh
EOF

  ( cd "${WORK_DIR}" && docker build -t "${CUSTOM_IMAGE}" --label "${LABEL}" \
      --build-arg SETENV=setenv.sh . ) > "${LOG_DIR}/build-custom.log" 2>&1 || return 1

  ( cd "${WORK_DIR}" && docker build -t "${CUSTOM_PLAIN_IMAGE}" --label "${LABEL}" \
      --build-arg SETENV=setenv-plain.sh . ) > "${LOG_DIR}/build-custom-plain.log" 2>&1
}

group_custom() {
  section "custom - an own setenv.sh keeps the feature by sourcing dockerenv.sh"

  if ! buildCustomImages; then
    skip "an own setenv.sh that sources dockerenv.sh" "the derived image did not build, see ${LOG_DIR}/build-custom.log"
    return 0
  fi

  local _NAME="${PREFIX}-custom"

  startTomcat "${_NAME}" -e "APP_DATABASE_NAME=${MARKER}" "${CUSTOM_IMAGE}"

  if waitForLog "${_NAME}" "Server startup in"; then
    local _LOG="$(tomcatLog "${_NAME}")"

    assertContains "the own setenv.sh is used" "${_LOG}" "-Dcustom.marker=tomcat-custom-42"
    assertContains "  and the sourced dockerenv.sh still passes APP_ on" \
      "${_LOG}" "Command line argument: -Dapp.database.name=${MARKER}"
  else
    skip "an own setenv.sh that sources dockerenv.sh" "the server did not come up"
  fi

  stopTomcat "${_NAME}"

  ## and the other half of that documented sentence ###########################
  # without the source line the feature is gone - if this one ever passes, the note in
  # README.md is telling users to add a line they do not need
  local _PLAIN="${PREFIX}-custom-plain"

  startTomcat "${_PLAIN}" -e "APP_DATABASE_NAME=${MARKER}" "${CUSTOM_PLAIN_IMAGE}"

  if waitForLog "${_PLAIN}" "Server startup in"; then
    local _PLAIN_LOG="$(tomcatLog "${_PLAIN}")"

    assertContains "an own setenv.sh without the source line still works" \
      "${_PLAIN_LOG}" "-Dcustom.marker=tomcat-custom-42"
    assertNotContains "  but then no APP_ variable is passed on" "${_PLAIN_LOG}" "-Dapp.database.name"
  else
    skip "an own setenv.sh without the source line" "the server did not come up"
  fi

  stopTomcat "${_PLAIN}"
}

###############################################################################
#### Group: versions - every tag the pipeline publishes
###############################################################################

# Not in 'default': this builds and pulls one official image per published tag, which is
# minutes and gigabytes. It is the group to run after changing the version list or the
# Dockerfile.
#
# TOMCAT_TEST_VERSIONS narrows that to the tags given - one added version does not need
# the other eight pulled again. Only this group honours it: the list group 'docs' compares
# is the published one, and an override there would compare the pipeline against itself.
versionsUnderTest() {
  if [ ! -z "${TOMCAT_TEST_VERSIONS}" ]; then
    printf '%s\n' ${TOMCAT_TEST_VERSIONS}
    return 0
  fi

  ciVersions
}

group_versions() {
  section "versions - every tag from .gitlab-ci.yml builds and runs"

  local _VERSION
  local _TAG
  local _OUT
  local _NUMBER
  local _JVM
  local _MAJOR
  local _JRE

  for _VERSION in $(versionsUnderTest); do
    _TAG="${PREFIX}-version:${_VERSION}"

    info "building ${_VERSION}"

    RUN_LOG="${LOG_DIR}/build-${_VERSION}.log"

    if ! buildImage "${_TAG}" "${_VERSION}" "${RUN_LOG}"; then
      fail "${_VERSION} builds" "the build failed"
      continue
    fi

    pass "${_VERSION} builds"

    _OUT="$(docker run --rm --label "${LABEL}" "${_TAG}" /usr/local/tomcat/bin/version.sh 2>&1)"

    RUN_LOG="${LOG_DIR}/version-${_VERSION}.log"
    printf '%s\n' "${_OUT}" > "${RUN_LOG}"

    _NUMBER="$(printf '%s' "${_OUT}" | sed -n 's/^Server number: *//p')"
    _JVM="$(printf '%s' "${_OUT}" | sed -n 's/^JVM Version: *//p')"

    # 'latest' says nothing about which version is behind it, so only the tags that name
    # one are checked against it
    if [ "${_VERSION}" == "latest" ]; then
      assertContains "  ${_VERSION} reports a tomcat version" "${_OUT}" "Server version: Apache Tomcat/"
      continue
    fi

    _MAJOR="${_VERSION%%-*}"
    assertStartsWith "  ${_VERSION} runs tomcat ${_MAJOR}" "${_NUMBER}" "${_MAJOR}."

    case "${_VERSION}" in
      *-jre* )
        _JRE="${_VERSION#*-jre}"
        assertStartsWith "  ${_VERSION} runs on jre ${_JRE}" "${_JVM}" "${_JRE}."
        ;;
    esac
  done
}

###############################################################################
#### Main
###############################################################################

cleanup() {
  if [ "${KEEP}" == "true" ]; then
    printf '\n--keep: the containers are left running, remove them with bash test/clean.sh env\n'
    return 0
  fi

  printf '\n'
  bash "${TEST_DIR}/clean.sh" env
}

# only the leading '####' block, not every line starting with it - the section banners
# further down do too
usage() {
  awk '
    /^####/ { started = 1; sub(/^#### ?/, ""); print; next }
    started { exit }
  ' "$0"
}

main() {
  local _GROUPS=""
  local _ARG

  if [ ${#} == 0 ]; then
    usage
    exit 0
  fi

  for _ARG in "${@}"; do
    case "${_ARG}" in
      --list ) echo "${ALL_GROUPS}"; exit 0 ;;
      --help | -h ) usage; exit 0 ;;
      --keep ) KEEP="true" ;;
      default ) _GROUPS="${_GROUPS} ${DEFAULT_GROUPS}" ;;
      all ) _GROUPS="${_GROUPS} ${ALL_GROUPS}" ;;
      -* ) echo "unknown option '${_ARG}'"; exit 1 ;;
      * ) _GROUPS="${_GROUPS} ${_ARG}" ;;
    esac
  done

  # reached by something like '--keep' on its own, which selects no group at all
  if [ -z "${_GROUPS}" ]; then
    echo "no group given"
    echo
    usage
    exit 1
  fi

  if [ -z "$(docker info --format '{{.ServerVersion}}' 2>/dev/null)" ]; then
    echo "docker is not reachable"
    exit 1
  fi

  # Two runs at once destroy each other: they share the container names and the image
  # tag, and the cleanup of whichever finishes first pulls them out from under the other.
  # That surfaces as 'no such container' in the middle of an unrelated test, which costs
  # far more time to understand than this check costs to run.
  #
  # Checked through docker and not with a lock file: there is no flock on a windows host,
  # and the containers are the shared resource anyway.
  if [ ! -z "$(docker ps -q --filter "label=${LABEL}")" ]; then
    echo "containers of another run are still up:"
    docker ps --filter "label=${LABEL}" --format '  {{.Names}} ({{.Status}})'
    echo
    echo "wait for that run to finish, or remove them with 'bash test/clean.sh env'"
    exit 1
  fi

  mkdir -p "${LOG_DIR}"
  rm -f "${LOG_DIR}"/*.log
  rm -rf "${WORK_DIR}"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # the build arguments the image records, so the tests can assert what the Dockerfile
  # wrote. VCS_REF stays empty where there is no git - the label is then empty too, and
  # the assertion still holds
  BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  VCS_REF="$(git -C "${PROJECT_DIR}" rev-parse --short HEAD 2>/dev/null)"
  readonly BUILD_DATE
  readonly VCS_REF

  section "building ${IMAGE} from tomcat:${BASE_TAG}"

  if ! buildImage "${IMAGE}" "${BASE_TAG}" "${LOG_DIR}/build.log"; then
    echo "  the build failed, see ${LOG_DIR}/build.log"
    exit 1
  fi

  info "built"

  local _GROUP

  # 'all unit' or 'default tomcat' name a group twice, and starting a server twice for
  # nothing costs half a minute
  local _UNIQUE=""

  for _GROUP in ${_GROUPS}; do
    case " ${_UNIQUE} " in
      *" ${_GROUP} "* ) continue ;;
    esac

    _UNIQUE="${_UNIQUE} ${_GROUP}"
  done

  for _GROUP in ${_UNIQUE}; do
    if [ -z "$(type -t "group_${_GROUP}")" ]; then
      echo "unknown group '${_GROUP}', known are: ${ALL_GROUPS}"
      exit 1
    fi

    "group_${_GROUP}"
  done

  section "summary"

  printf '  %s test(s), %s failed, %s skipped\n' "${TESTS_RUN}" "${TESTS_FAILED}" "${TESTS_SKIPPED}"

  if [ ${TESTS_FAILED} != 0 ]; then
    local _NAME

    for _NAME in "${FAILED_NAMES[@]}"; do
      printf "  ${COLOR_RED}failed${COLOR_RESET} %s\n" "${_NAME}"
    done

    printf '  logs: %s\n' "${LOG_DIR}"
    exit 1
  fi

  printf "  ${COLOR_GREEN}everything passed${COLOR_RESET}\n"
}

main "${@}"
