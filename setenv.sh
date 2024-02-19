#!/bin/bash

readonly SCRIPT_DIR=$(dirname "$0")
readonly DOCKER_APP_ENV_FILE=${SCRIPT_DIR}/dockerappenv.sh

if [[ -f "${DOCKER_APP_ENV_FILE}" ]]; then
  rm ${DOCKER_APP_ENV_FILE}
fi
touch ${DOCKER_APP_ENV_FILE}
chmod 755 ${DOCKER_APP_ENV_FILE}

declare -u _K
declare -l _KEY
declare _V
declare _VALUE
env -0 | while IFS='=' read -r -d '' _K _V; do
  if [[ ${_K} = APP_* ]]; then
    _KEY=$(echo ${_K} | sed 's:_:.:g')
    _VALUE=$(echo ${_V} | sed 's:^"\(.*\)$:\1:' | sed 's:^\(.*\)"$:\1:' | sed "s:^'\(.*\)$:\1:" | sed "s:^\(.*\)'$:\1:")
    printf "export CATALINA_OPTS=\"\$CATALINA_OPTS -D%s='%s'\"\n" "${_KEY}" "${_VALUE}" >> ${DOCKER_APP_ENV_FILE}
  fi
done

source ${DOCKER_APP_ENV_FILE}
