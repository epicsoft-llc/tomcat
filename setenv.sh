#!/bin/bash

#### Passes every docker environment with the prefix 'APP_' on to the application as a
#### system property: APP_DATABASE_NAME="example" becomes -Dapp.database.name=example and
#### is usable in a configuration as ${app.database.name}.
####
#### catalina.sh sources this file as 'bin/setenv.sh'. The image carries it a second time
#### as 'bin/dockerenv.sh', for users who bring their own setenv.sh and keep this feature
#### with 'source $(dirname "$0")/dockerenv.sh'.

# The value ends up in CATALINA_OPTS, and catalina.sh does not run the java command but
# hands it to 'eval' - so CATALINA_OPTS is read as shell syntax a second time. The single
# quotes around the value below are what keeps a value with spaces one argument there,
# and what stops a '$' or a '$(...)' that is part of a value from being expanded. A single
# quote in the value itself would end that protection, so each one is replaced by this
# sequence: leave the quoting, one escaped quote, back into the quoting.
_QUOTE="'\\''"

declare _NAME
declare -u _K
declare -l _KEY
declare _V
declare _VALUE
declare _INNER

# Read from a process substitution and not from 'env -0 | while ...': a pipe runs the loop
# in a subshell, and everything it assigns to CATALINA_OPTS is gone once that subshell
# ends. The way around that used to be writing the assignments to a file and sourcing it
# afterwards - which sent every value through the shell one more time, and so expanded a
# '$' and executed a '$(...)' that was only ever meant as data.
while IFS='=' read -r -d '' _NAME _V; do
  _K=${_NAME}

  if [[ ${_K} != APP_* ]]; then
    continue
  fi

  # The value is protected by the quoting below, the name is not - it stands in the same
  # line and is read by the same 'eval'. A space in it would make the rest of the line a
  # second argument and the server would not come up at all, with a java error that names
  # the value and not its cause. So a name that cannot be a property name is skipped, and
  # says so: silently dropping it would be found only in the running application.
  if [[ ${_K} == APP_ || ${_K} =~ [^A-Z0-9_] ]]; then
    echo "setenv.sh: ignoring '${_NAME}' - after 'APP_' only letters, digits and '_'" 1>&2
    continue
  fi

  _KEY=${_K//_/.}
  _VALUE=${_V}

  # One pair of quotes around the value is how a value with spaces is written in a compose
  # file, and is not part of the value. Only a real pair is taken off, and only when the
  # same quote does not appear inside it as well: stripping one leading and one trailing
  # quote on their own would eat the last character of 'he said "hi" and "bye"' and turn
  # '"a" and "b"' into something that was never written anywhere.
  case ${_VALUE} in
    \"*\" )
      _INNER=${_VALUE:1:${#_VALUE}-2}
      if [[ ${_INNER} != *\"* ]]; then
        _VALUE=${_INNER}
      fi
      ;;
    \'*\' )
      _INNER=${_VALUE:1:${#_VALUE}-2}
      if [[ ${_INNER} != *\'* ]]; then
        _VALUE=${_INNER}
      fi
      ;;
  esac

  # the quotes are meant to end up in the value literally: catalina.sh is what reads them
  # back, and a string is the only thing it can be handed
  # shellcheck disable=SC2089
  CATALINA_OPTS="${CATALINA_OPTS} -D${_KEY}='${_VALUE//\'/${_QUOTE}}'"
done < <(env -0)

# shellcheck disable=SC2090
export CATALINA_OPTS

# this runs in the shell of catalina.sh, so everything that is not CATALINA_OPTS is taken
# back out of it again - including the attributes the 'declare' calls set
unset -v _NAME _K _V _KEY _VALUE _INNER _QUOTE
