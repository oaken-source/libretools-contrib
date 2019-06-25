#!/bin/bash
###############################################################################
#     libretools-contrib -- helper scripts for parabola package management    #
#                                                                             #
#     Copyright (C) 2019  Andreas Grapentin                                   #
#                                                                             #
#     This program is free software: you can redistribute it and/or modify    #
#     it under the terms of the GNU General Public License as published by    #
#     the Free Software Foundation, either version 3 of the License, or       #
#     (at your option) any later version.                                     #
#                                                                             #
#     This program is distributed in the hope that it will be useful,         #
#     but WITHOUT ANY WARRANTY; without even the implied warranty of          #
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
#     GNU General Public License for more details.                            #
#                                                                             #
#     You should have received a copy of the GNU General Public License       #
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.   #
###############################################################################

. "$(librelib messages)"
. "$(librelib conf)"

usage() {
  print "usage: %s [-h] <operation> [...]" "${0##*/}"
  print "operations:"
  print "    %s l [dir(s)]" "${0##*/}"
  print "    %s q [-y] [arch(es)]" "${0##*/}"
  print "    %s u [id(s)] [dir(s)] [*]" "${0##*/}"
  print "    %s c [id(s)] [dir(s)] [-]" "${0##*/}"
  print "    %s k" "${0##*/}"
  echo
  prose "A libremakepkg queueing tool."
  echo
  prose "FIXME: There should be some help here."
}

_list_println() {
  # output format:
  #     <one space>
  #     <id, left-aligned, 5 chars wide>
  #     <two spaces>
  #     <package name, left aligned, left ellipsized, $(tput cols) - 38 chars wide>
  #     <two spaces>
  #     <arch, left-aligned, 7 chars wide>
  #     <two spaces>
  #     <status, left-aligned, 8 chars wide>
  #     <two spaces>
  #     <elapsed time, fixed width, 8 chars wide>
  #     <one space>

  local len
  len=$(( $(tput cols) - 38 ))

  local elapsed="$5"
  if [[ "$5" =~ ^[0-9./]+$ ]]; then
    local h m s
    s="$(printf "%.0f" "${5%%/*}")"

    m=$(( s / 60 ))
    s=$(( s % 60 ))
    h=$(( m / 60 ))
    m=$(( m % 60 ))

    elapsed=$(printf "%02i:%02i:%02i" "$h" "$m" "$s")
  fi

  local jobname="$2"
  jobname="$(echo "$jobname" | awk -v len=$len \
    '{ if (length($0) > len) print "..." substr($0, length($0)-len+4, len-3); else print; }')"

  printf " %-5s  %-${len}s  %-7s  %-8s  %-8s \n" \
    "$1" "$jobname" "$3" "$4" "$elapsed"
}

qbu_list() {
  # list all jobs, or filter by the ones specified
  local snapshot
  snapshot=$(tsp | tail -n+2)

  if [ "$#" -gt 0 ]; then
    local snapshot_filtered
    while IFS=$'\n' read -r line; do
      for arg in "$@"; do
        arg="$(readlink -f "$arg")"
        if [ ! -d "$arg" ] || [ ! -e "$arg/PKGBUILD" ]; then continue; fi

        if echo "$line" | grep -q "$arg/"; then
          snapshot_filtered="$snapshot_filtered\n$line"
          break
        fi
      done
    done < <(echo "$snapshot")
    snapshot="$snapshot_filtered"
  fi

  local running=() queued=() failed=() finished=()
  IFS=$'\n'
  mapfile -t running  < <(echo "$snapshot" | grep ' running ')
  mapfile -t queued   < <(echo "$snapshot" | grep ' queued ')
  mapfile -t failed   < <(echo "$snapshot" | grep ' finished ' | awk '$4 != "0" {print $0}')
  mapfile -t finished < <(echo "$snapshot" | grep ' finished ' | awk '$4 == "0" {print $0}')
  unset IFS

  tput bold
  _list_println "ID" "package" "arch" "state" "elapsed"
  echo -n '[m'

  tput setaf 6
  for l in "${running[@]}"; do
    IFS=' ' read -r -a args <<< "$(echo "$l" | awk '{print $1, $(NF-1), $(NF), $2}')"
    _list_println "${args[@]}" ""
  done
  echo -n '[m'

  for l in "${queued[@]}"; do
    IFS=' ' read -r -a args <<< "$(echo "$l" | awk '{print $1, $(NF-1), $(NF), $2}')"
    _list_println "${args[@]}" ""
  done

  tput setaf 1
  for l in "${failed[@]}"; do
    IFS=' ' read -r -a args <<< "$(echo "$l" | awk '{print $1, $(NF-1), $(NF), "failed", $5}')"
    _list_println "${args[@]}"
  done
  echo -n '[m'

  tput setaf 2
  for l in "${finished[@]}"; do
    IFS=' ' read -r -a args <<< "$(echo "$l" | awk '{print $1, $(NF-1), $(NF), $2, $5}')"
    _list_println "${args[@]}"
  done
  echo -n '[m'

  echo -n "running: $(tput setaf 6)[${#running[@]}]$(echo -n '[m'), "
  echo -n "queued: [${#queued[@]}], "
  echo -n "failed: $(tput setaf 1)[${#failed[@]}]$(echo -n '[m'), "
  echo    "finished: $(tput setaf 2)[${#finished[@]}]$(echo -n '[m')"
}

_in_array() {
  local needle="$1"; shift
  for e in "$@"; do
    [[ "$e" == "$needle" ]] && return 0;
  done
  return 1
}

qbu_enqueue() {
  # enqueue builds for the given arches, if specified, otherwise for all supported
  if [[ ! -f PKGBUILD ]]; then
    error "PKGBUILD does not exist."
    exit "$EXIT_FAILURE"
  fi

  # parse options
  local yes
  while getopts 'y' arg; do
    case "$arg" in
      y) yes="yes";;
      *) usage >&2; exit "$EXIT_INVALIDARGUMENT";;
    esac
  done
  local shiftlen=$(( OPTIND - 1 ))
  shift $shiftlen

  local arch=() validpgpkeys=()
  load_PKGBUILD || exit "$EXIT_FAILURE"

  if [ "x$yes" != "xyes" ]; then
    # check if any keys need to be imported
    for key in "${validpgpkeys[@]}"; do
      if ! gpg --list-keys "$key" &>/dev/null; then
        read -p " Import missing key $key? [Y/n] " -n 1 -r
        (( ${#REPLY} == 1 )) && echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then exit "$EXIT_FAILURE"; fi
        gpg --recv-keys "$key" || exit "$EXIT_FAILURE"
      fi
    done

    # check if the source checksums match
    local makepkg_res
    if ! makepkg_res="$(makepkg -f --verifysource 2>&1)"; then
      echo " Source verification failed:"
      sed 's/^/ | /' <<< "$makepkg_res"
      read -p " run updpkgsums? [y/N] " -n 1 -r
      (( ${#REPLY} == 1 )) && echo
      if ! [[ $REPLY =~ ^[Yy]$ ]]; then exit "$EXIT_FAILURE"; fi
      updpkgsums || exit "$EXIT_FAILURE"
    fi

    # ask namcap for help
    local issues
    issues="$(namcap ./PKGBUILD 2>&1)"
    if [ -n "$issues" ]; then
      echo "$issues"
      read -p " Continue? [y/N] " -n 1 -r
      (( ${#REPLY} == 1 )) && echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit "$EXIT_FAILURE"
      fi
    fi
  fi

  local chosen=('any')
  [ "$#" -eq 0 ] || chosen=("$@")

  local ARCHES
  load_conf libretools.conf ARCHES || exit "$EXIT_FAILURE"

  # determine what arches to build for
  local builds=()
  if _in_array 'any' "${chosen[@]}"; then
    if _in_array 'any' "${arch[@]}"; then
      if _in_array "$(uname -m)" "${ARCHES[@]}"; then
        builds+=("$(uname -m)")
      else
        error "native arch %s is not enabled in libretools.conf" "$(uname -m)"
      fi
    else
      for a in "${arch[@]}"; do
        if _in_array "$a" "${ARCHES[@]}"; then
          builds+=("$a")
        fi
      done
    fi
  else
    for a in "${chosen[@]}"; do
      if ! _in_array 'any' "${arch[@]}" && ! _in_array "$a" "${arch[@]}"; then
        error "requested arch %s not supported by PKGBUILD" "$a"
        continue
      fi
      if ! _in_array "$a" "${ARCHES[@]}"; then
        error "requested arch %s not enabled in libretools.conf" "$a"
        continue
      fi
      builds+=("$a")
    done
  fi

  if [ "${#builds[@]}" -eq 0 ]; then
    error "no builds left to queue"
    exit "$EXIT_INVALIDARGUMENT"
  fi

  # unqueue duplicates
  for a in "${builds[@]}"; do
    if tsp | grep ' running ' | grep -q "x $(readlink -f .)/ $a"; then
      warning "build for %s is running" "$a"
    fi
    for id in $(tsp | grep -v ' running ' | grep " x $(readlink -f .)/ $a" | awk '{print $1}'); do
      tsp -r "$id"
    done
  done

  # queue build jobs in tsp
  for a in "${builds[@]}"; do
    tsp "$0" x "$(readlink -f .)/" "$a"
  done
}

qbu_dequeue() {
  # clear all successfully completed jobs, or the ones specified
  local args=("$@")
  [[ $# -gt 0 ]] || args+=("*")

  for a in "${args[@]}"; do
    if [[ "$a" == "*" ]]; then
      # clear all successfully completed
      local finished=()
      IFS=$'\n'
      mapfile -t finished < <(tsp | grep ' finished ' | awk '$4 == "0" {print $1}')
      unset IFS

      for f in "${finished[@]}"; do tsp -r "$f"; done
    elif [[ $a =~ ^[0-9]+$ ]]; then
      # clear by id
      tsp -r "$a"
    else
      # clear by directory
      local finished=()
      IFS=$'\n'
      mapfile -t finished < \
        <(tsp | grep ' finished ' | grep "x $(readlink -f "$a")/ " | awk '$4 == "0" {print $1}')
      unset IFS

      for f in "${finished[@]}"; do tsp -r "$f"; done
    fi
  done
}

qbu_logcat() {
  # cat the output of the specified jobs, or the currently running
  local args=("$@")
  [[ $# -gt 0 ]] || args+=("-")

  for a in "${args[@]}"; do
    if [[ "$a" == "-" ]]; then
      # cat currently running
      while tsp | grep -q ' running '; do tsp -c; done
    elif [[ $a =~ ^[0-9]+$ ]]; then
      # cat by id
      tsp -c "$a"
    else
      # cat by directory
      local tasks=()
      IFS=$'\n'
      mapfile -t tasks < <(tsp | grep "x $(readlink -f "$a")/ " | awk '{print $1}')
      unset IFS

      for f in "${tasks[@]}"; do tsp -c "$f"; done
    fi
  done
}

qbu_kill() {
  # kill the currently running job
  if [[ $# -gt 0 ]]; then
    usage >&2
    exit "$EXIT_INVALIDARGUMENT"
  fi

  tsp -k
}

_notify() {
  if type -p notify-send >/dev/null; then
    local NOTIFY_HINT
    load_conf libretools.conf NOTIFY_HINT 2>&1

    notify-send "${NOTIFY_HINT[@]}" "$@"
  fi
}

_build_exit() {
  local res=$?

  local build
  build="$(printf '%s/%s-%s' "$(basename "$(dirname "$1")")" "$(basename "$1")" "$2")"

  local queued
  queued="$(tsp | grep -c ' queued ')"

  if [[ $res -eq 0 ]]; then
    _notify -c success "*[Q${queued}]* ${build//_/\\_}"
  else
    local log
    log="$(tsp | grep "x $(readlink -f "$1")/ $2" | awk '{print $3}')"

    _notify -c error "*[Q${queued}]* ${build//_/\\_}" -h "string:document:$log"
  fi
}

qbu_execute() {
  if [[ ! -f PKGBUILD ]]; then
    error "PKGBUILD does not exist."
    exit "$EXIT_FAILURE"
  fi

  trap '_build_exit "$1" "$2"' EXIT

  local res

  # clean the librechroot before building
  sudo librechroot -A "$2" -n "qbu-$2" clean-pkgs
  res=$?

  if [[ $res -ne 0 ]]; then
    msg "cleaning the chroot has failed -- attempt to recreate..."
    sudo librechroot -A "$2" -n "qbu-$2" delete
    sudo librechroot -A "$2" -n "qbu-$2" -l root delete
    sudo librechroot -A "$2" -n "qbu-$2" make || exit "$EXIT_FAILURE"
    sudo librechroot -A "$2" -n "qbu-$2" clean-pkgs || exit "$EXIT_FAILURE"
  fi

  # update the librechroot before building
  sudo librechroot -A "$2" -n "qbu-$2" update
  res=$?

  if [[ $res -ne 0 ]]; then
    msg "updating the chroot has failed -- attempt to recreate..."
    sudo librechroot -A "$2" -n "qbu-$2" delete
    sudo librechroot -A "$2" -n "qbu-$2" -l delete
    sudo librechroot -A "$2" -n "qbu-$2" make || exit "$EXIT_FAILURE"
    sudo librechroot -A "$2" -n "qbu-$2" update || exit "$EXIT_FAILURE"
  fi

  # clean the chroot pkg cache
  sudo librechroot -A "$2" -n "qbu-$2" run \
    find /var/cache/pacman/pkg -type f -delete

  # start the build
  sudo libremakepkg -n "qbu-$2" || exit "$EXIT_FAILURE"

  # clean the chroot after a successful build
  sudo librechroot -A "$2" -n "qbu-$2" clean-pkgs

  exit "$EXIT_SUCCESS"
}

main() {
  if [[ -w / ]]; then
    error "This program should be run as a regular user"
    return "$EXIT_NOPERMISSION"
  fi

  # set the socket to the qbu queue
  export TS_SOCKET="/var/run/user/$(id -u)/qbu.socket"

  # parse options
  local op=l
  local args=()

  while getopts 'h' arg; do
    case "$arg" in
      h) usage; return "$EXIT_SUCCESS";;
      *) args+=("$arg")
    esac
  done
  local shiftlen=$(( OPTIND - 1 ))
  shift $shiftlen

  if [ "$#" -gt 0 ]; then op="$1"; shift; fi

  case "$op" in
    l) if [ ${#args[@]} -gt 0 ]; then usage >&2; exit "$EXIT_INVALIDARGUMENT"; fi
       qbu_list "$@";;
    q) qbu_enqueue "${args[@]}" "$@";;
    u) if [ ${#args[@]} -gt 0 ]; then usage >&2; exit "$EXIT_INVALIDARGUMENT"; fi
       qbu_dequeue "$@";;
    c) if [ ${#args[@]} -gt 0 ]; then usage >&2; exit "$EXIT_INVALIDARGUMENT"; fi
       qbu_logcat "$@";;
    k) if [ ${#args[@]} -gt 0 ]; then usage >&2; exit "$EXIT_INVALIDARGUMENT"; fi
       qbu_kill "$@";;
    x) if [ ${#args[@]} -gt 0 ]; then usage >&2; exit "$EXIT_INVALIDARGUMENT"; fi
       qbu_execute "$@";;
    *) usage >&2; exit "$EXIT_INVALIDARGUMENT";;
  esac
}

main "$@"
