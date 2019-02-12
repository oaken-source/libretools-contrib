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
  print "Usage: %s [msg]" "${0##*/}"
  print "Commit the changes to the package build recipes."
  echo
  prose "The commit messages is generated, unless explicitly given."
}

main() {
  if [[ -w / ]]; then
    error "This program should be run as a regular user"
    return $EXIT_NOPERMISSION
  fi

  # parse options
  while getopts 'h' arg; do
    case $arg in
      h) usage; return $EXIT_SUCCESS;;
      *) usage >&2; return $EXIT_INVALIDARGUMENT;;
    esac
  done

  if ! [[ -e ./PKGBUILD ]]; then
    error "PKGBUILD not found"
    return $EXIT_FAILURE
  fi

  local repo
  repo="$(basename "$(dirname "$PWD")")"

  # load the PKGBUILD
  load_PKGBUILD

  local msg
  msg="$repo/$pkgbase"

  if [[ $# -gt 0 ]]; then
    msg="$msg: $1"
  else
    local new_pkgver new_pkgrel
    new_pkgver="$pkgver"
    new_pkgrel="$pkgrel"
    unset pkgver pkgrel

    # load the old PKGBUILD
    touch .librecommit-keep
    git stash push -k -u -q -- ./PKGBUILD >/dev/null
    if [[ -f ./PKGBUILD ]]; then
      load_PKGBUILD
    fi
    git stash pop -q >/dev/null
    rm -f .librecommit-keep

    if [[ -z "${pkgver:-}" ]]; then
      msg="$msg: added"
    elif [[ "$pkgver" != "$new_pkgver" ]]; then
      msg="$msg: updated to $new_pkgver"
    else
      msg="$msg: rebuilt"
    fi
  fi

  git add .
  git status .
  read -p " *** $msg *** Ok? [Y/n] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    git commit -m"$msg"
  else
    git reset -q HEAD .
  fi
}

main "$@"
