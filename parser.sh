#!/usr/bin/env bash
# todo: rewrite me to a real language, this is a hack for protyping.
#   ruby should really used, though parser:ast doesn't show __END__ data
# Assume bash is atleast version 4
shopt -s extglob
set -e

# bugs:
# IFS bugs causing weird behavior

file="${1:-darkice.rb}"

function clean(){ # Remove comments, ruby's csv-like backtick for \n
  local f=()  # file
  local p=()  # placeholder
  local c i x   # var for comments/csv
  local eofpatchdata wordarray  # affect how we represent data
  local IFS=$'\n' # Prevent `for` from looping words instead of each line.
  # Put each line into a array (design choice) to print out when done.
  readarray -t f < ${file}
  # --------
  for ((i=0; i < ${#f[@]}; i++ )); do
    c="${f[${i}]}"
    # check for patch __END__ and leave it alone.
    if [[ "${c}" == "__END__" || -n "${eofpatchdata}" ]]; then
      p+=(${c}); eofpatchdata=1
      continue
    fi
    # -- remove leading/trailing whitespace: https://stackoverflow.com/a/3352015
    c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
    # >> comment out build.head if it's not a 'if' block
    if [[ "${c}" == *" if build.head?" ]]; then
      # skip over
      c="# ${c}"
      p+=(${c})
      continue
    fi
    # -- comments
    [[ ${c:0:1} == "#" ]] && continue
    # -- comma
    x=${c##* }; x=${x: -1} # (last word, if comma)
    [[ "${x}" == "," ]] && c+=\ $'\v' # reserve \v for reverse-newline (design)
    # -- append
    p+=(${c})
  done; f=(${p[@]}); p=() # f == placeholder, p reset
  # ---------
  #   this for loops printfs to stdout and handles messy ruby multiline commands
  for ((i = 0; i <= ${#f[@]}; i++)); do
    printf -- '%s' "${f[$i]/$'\v'}"  # \v still in string!
    [[ ${f[$i]: -1} != $'\v' ]] && printf '\n'
  done
}

function parse(){
  # sub-functions
  function _args(){
    local IFS=',' # main has \n as IFS, change before shifting.
    local w
    #set -- "${@:2}"
    # FIXME: (bug) changing IFS to a newline affects local function, can't shift here?
    #   workaround is to (VVV) hack with sub replacement
    local l="$@"; l="${l#* }"

    for w in ${l}; do
      w="${w##+([[:space:]])}"; w="${w//\"}" #; w="${w#\"}"
      printf -- '%s' "$w"
    done; printf '\n'
    # l -> remove 'system' from argv
    # IFS is a comma to remove them
    # w removes the first space and quotes as a hack.
  }

  function _patch(){
    set -- "${@:2}"; local l="$@"
    if [[ -n ${DEBUG_PATCH} ]]; then printf -- 'patch:\t### %s %s ###\n' "$(caller)" "${l}"; fi
    local w i # loop vars
    #   nonlocal patchInfo is declared from parse()
    if [[ "${patchSkip}" -ne 0 ]]; then
      if [[ -n ${DEBUG} ]]; then printf -- 'patch:\t%s\n' "${line}"; fi

      # __END__
      if [[ "${patchInfo[type]}" == "data" ]]; then
        # IFS=$'\n'
        patchInfo[data_${patchInfo[count]}]="${l}"
        patchInfo[count]=$(( patchInfo[count]+1 ))
        return
      fi
      # figure out details, download url and what to apply:
      case "${1}" in
        url)
          patchInfo[type]="external"
          patchInfo[url]="$(_args "${l}")"
        ;;
        apply)
          patchInfo[type]="multi"
          #   FIXME: (?) There's a race condition here, the parser will see url first before apply.
          # Reuse code with _args
          l=( $(_args ${l}) )
          for ((i=0; i < ${#l[@]}; i++ )); do
            w="${l[$i]}"
            patchInfo[count]=$(( patchInfo[count]+1 ))
            patchInfo[data_${i}]="${w}"
          done
        ;;
        sha256) ;;  # TODO: checksum checking.
      esac
      return
    else  # first call
      patchInfo=(
        [type]=""
        [patchlevel]=""
        [url]=""
        [count]=0
        # [data_${i}]="patch/foobar.diff"
        # [data_${i}]="\t--- a/example.c b/example.c"
      )
      # Expected data layout:
      #   [0] -> patchlevel
      #   [1] -> type {data,external,multi}
      #   [2] -> buffer, similar to c buffers
      #   [3++] -> data (what patches we apply or hacked __END__ data)
      # http://mywiki.wooledge.org/BashFAQ/006
      case "${1}" in
        __END__)
          patchInfo[patchlevel]=1  # assume 1, no good way to guess.
          patchInfo[type]="data"
        ;;
        :p*)
          patchInfo[patchlevel]="${1: -1}"
          patchInfo[type]="external"
        ;;
        *) # Default - patch do
          patchInfo[patchlevel]="1"  # patch might not have the :p attribute
          patchInfo[patchInfo]="external"
        ;;
      esac
    fi
  }
  function _patch_output(){  # write to stdout/file
    #   TODO: output to a file
    for x in "${!patchInfo[@]}"; do printf '%s: %s\n' "$x" "${patchInfo[$x]}"; done

    if [[ ${patchInfo["type"]} == "data" ]]; then
      rm patch-file
      for ((i=0; i <= ${patchInfo['count']}; i++ )); do
        printf '%s\n' "${patchInfo["data_${i}"]}" >> patch-file
      done
    fi
  }

  function _resource(){
    local l="$@"
    local v="${l##* }"
    local r
    if [[ -n "${DEBUG_RESOURCE}" ]]; then printf -- 'resource:\t ### %s ###\n' "${l}"; fi

    if [[ -n "${STAGE}" ]]; then
      [[ "${l}" =~ \"(.*)\" ]] && r="${BASH_REMATCH[1]}"; : "${r:?"regex failed: $(caller) - ${l}"}"
      if [[ -n "${DEBUG_RESOURCE}" ]]; then printf -- 'resource:\t --- STAGE DO (%s) (%s) ---\n' "${r}" "${l}"; fi
      printf -- '%s\n%s\n' "download ${resourceInfo[$r]}" "extract ${resourceInfo[$r]##*/}"
    elif [[ "${v}" == "do" ]]; then  # resource "foo" __do__
      r="${2//\"}"
      resourceInfo[${r}]=""
      resourceInfo[__last__]="${r}"
    elif [[ "${l%% *}" == "url" ]]; then  # url "example.com"
      r="${resourceInfo[__last__]}" # get the last variable, it shouldn't have a url yet
      resourceInfo[${r}]="$(_args "${l}")"
      unset -v resourceInfo[__last__] # reset so we hopefully error out to bad code
    fi
  }
  # Main loop
  local f=()
  local line word
  readarray -t f -
  # ----------
  # loop variables:
  local endState; declare -i endState; endState=0
  local endSkip; declare -i endSkip; endSkip=0
  # https://unix.stackexchange.com/questions/282557/scope-of-local-variables-in-shell-functions
  local patchInfo; typeset -A patchInfo
  local patchSkip; declare -i patchSkip; patchSkip=0

  local resourceSkip
  local resourceInfo; declare -A resourceInfo
  unset STAGE # used to tell _resource() to echo out cmds to extract a resource
  resourceInfo=( [__last__]="" )  # XXX: can't find a way to retrieve the last resource

  shopt -u extglob; set -o noglob # DO NOT have globbing for word-by-word hacking, nightmare.
  for ((i=0; i < ${#f[@]}; i++ )); do
    # local IFS=$'\n'
    line="${f[$i]}"; word="${line%% *}"
    # debug
    [[ -n "${DEBUG_FILE}" ]] && printf -- '\t%s\t %s\n' "${i}" "${line}"

    #   -- end
    if [[ "${endSkip}" -ne 0 && "${word}" != "end" ]]; then
      [[ -n "${DEBUG}" ]] && printf -- '### Skipped: %s ###\n' "${line}"
      continue
    else endSkip=0
    fi
    #   -- patch
    if [[ "${patchSkip}" -ne 0 ]]; then
      if [[ "${word}" != "end" ]]; then   # we're in a patch block
        [[ "${patchInfo[type]}" == "data" ]] && \
            { local IFS=$'\n'; line="${f[$i]}"; } # reset line, IFS matters for EOF patch
        _patch _ ${line}
        [[ "${patchInfo[type]}" == "data" ]] && \
            [[ "${line:-x}" == "x" ]] && _patch_output # we're at the end, go ahead and print EOF patch.
        continue
      else  # word == 'end'; we're done with the patch block
        [[ -n "${DEBUG_PATCH}" ]] && _patch_output
        patchInfo=(); patchSkip=0
      fi
    else patchSkip=0  # default, we're not a patch block
    fi
    #   -- resource
    if [[ "${resourceSkip}" -ne 0 ]]; then
      if [[ "${word}" != "end" ]]; then
        _resource ${line}
      else
        # done
        resourceSkip=0
      fi
    else resourceSkip=0
    fi

    # main logic
    case "${word}" in
      # Formula keywords:
      class|stable) endState=$(( ${endState}+1 ))
      ;;
      end) endState=$(( ${endState}-1 ))
      ;;
      # -- skip
      bottle|test)
        endState=$(( ${endState}+1 ))
        endSkip=1
      ;;
      # -- formula
      # TODO: formula
      #
      def)
        endState=$(( ${endState}+1 ))
      ;;
      # -- patch
      patch|__END__)
        [[ "${line##* }" == ":DATA" ]] && {
          [[ -n ${DEBUG_PATCH} ]] && printf -- 'patch:\t### Expecting EOF Patch Data! ###\n'
          continue  # handle it later.
        }
        endState=$(( ${endState}+1 ))
        # hack for EOF patches
        [[ "${word}" == "__END__" ]] && line="_ __END__"
        _patch ${line}; patchSkip=1
        # XXX: order matters, we'll create patchInfo first and then pass to _patch()
      ;;
      # -- resource
      resource)
          _resource ${line}; resourceSkip=1
          endState=$(( ${endState}+1 ))
      ;;
      resource*.stage)
          STAGE=1 _resource ${line}
          endState=$(( ${endState}+1 ))
      ;;
    esac
    # [[ -n ${DEBUG} ]] && echo $endState
  done
  # ----------
  if [[ "${endState}" -ne 0 ]]; then
    printf -- '/// endState mismatch! (%s) ///\n' "${endState}"
  fi

  if [[ -n "${DEBUG_RESOURCE}" ]]; then
    for x in "${!resourceInfo[@]}"; do printf '%s: %s\n' "$x" "${resourceInfo[$x]}"; done
  fi
}

clean
# clean | parse

# ./bin/parser.rb ${file}
