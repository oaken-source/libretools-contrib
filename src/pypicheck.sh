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
  print "usage: %s [pkg]" "${0##*/}"
  print "compare the version of a python version against pypi"
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

  local _pkgname pkgver
  load_PKGBUILD

  if [[ $# -gt 0 ]]; then
    _pkgname="$1"
  fi

  if [ -z "$_pkgname" ]; then
    error "unable to determine pypi package name"
    exit "$EXIT_FAILURE"
  fi

  local latest
  latest="$(curl -s https://pypi.org/pypi/"$_pkgname"/json | jq -r '.info.version')"

  if [[ "$pkgver" != "$latest" ]]; then
    warning "%s: pypi version has changed: %s ==> %s" "$_pkgname" "$pkgver" "$latest"
  fi
}

main "$@"
