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
  print "usage: %s [msg]" "${0##*/}"
  print "remove a package from the repos"
  echo
  prose "remove the current package from abslibre, create a matching commit
         with the given, or otherwise a generated message, and remove the
         package from the repo on winston."
}

main() {
  if [[ -w / ]]; then
    error "This program should be run as a regular user"
    return "$EXIT_NOPERMISSION"
  fi

  # parse options
  while getopts 'h' arg; do
    case $arg in
      h) usage; return "$EXIT_SUCCESS";;
      *) usage >&2; return "$EXIT_INVALIDARGUMENT";;
    esac
  done

  if ! [[ -e ./PKGBUILD ]]; then
    error "PKGBUILD not found"
    return "$EXIT_FAILURE"
  fi

  local repo
  repo="$(basename "$(dirname "$PWD")")"

  local pkgbase pkgname
  # load the PKGBUILD
  load_PKGBUILD

  local msg
  msg="$repo/$pkgbase"

  if [[ $# -gt 0 ]]; then
    msg="$msg: $1"
  else
    msg="$msg: removed."
  fi

  local dir
  dir="$(basename "$PWD")"

  cd ..
  git rm -r "$dir"
  git status .
  read -p " *** $msg *** Ok? [Y/n] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    git commit -m"$msg"
    ssh winston.parabola.nu db-repo-remove "$repo" any "${pkgname[@]}"
  else
    git reset -q HEAD "$dir"
    cd "$dir"
  fi
}

main "$@"
