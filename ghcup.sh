#!/bin/sh
#
# Copyright (c) 2018, Julian Ospald <hasufell@posteo.de>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the <ORGANIZATION> nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.



## global variables ##

VERSION=0.0.1
SCRIPT="$(basename "$0")"
VERBOSE=false
FORCE=false
INSTALL_BASE="$HOME/.ghcup"


## print help ##

usage() {
    (>&2 echo "ghcup ${VERSION}
GHC up toolchain installer

USAGE:
    ${SCRIPT} [FLAGS] <SUBCOMMAND>

FLAGS:
    -v, --verbose    Enable verbose output
    -h, --help       Prints help information
    -V, --version    Prints version information

SUBCOMMANDS:
    install          Install GHC
    show             Show current/installed GHC
    set              Set currently active GHC version
    self-update      Update this script in-place
")
    exit 1
}

install_usage() {
    (>&2 echo "ghcup-install
Install the specified GHC version

USAGE:
    ${SCRIPT} install [FLAGS] <VERSION>

FLAGS:
    -h, --help       Prints help information
    -f, --force      Overwrite already existing installation

ARGS:
    <VERSION>        E.g. \"8.4.3\" or \"8.6.1\"
")
    exit 1
}

set_usage() {
    (>&2 echo "ghcup-set
Set the currently active GHC to the specified version

USAGE:
    ${SCRIPT} set [FLAGS] <VERSION>

FLAGS:
    -h, --help       Prints help information

ARGS:
    <VERSION>        E.g. \"8.4.3\" or \"8.6.1\"
")
    exit 1
}

self_update_usage() {
    (>&2 echo "ghcup-self-update
Update the ghcup.sh script in-place

USAGE:
    ${SCRIPT} self-update [FLAGS] [TARGET-LOCATION]

FLAGS:
    -h, --help         Prints help information

ARGS:
    [TARGET-LOCATION]  Where to place the updated script (defaults to ~/.local/bin).
                       Must be an absolute path!
")
    exit 1
}


show_usage() {
    (>&2 echo "ghcup-show
Show the installed/current GHC versions

USAGE:
    ${SCRIPT} show [FLAGS]

FLAGS:
    -h, --help         Prints help information
    -i, --installed    Show installed GHC version only
")
    exit 1
}


## utilities ##

die() {
    (>&2 echo "$1")
    exit 2
}

edo()
{
    if ${VERBOSE} ; then
        echo "$@" 1>&2
    fi
    "$@" || exit 2
}

echov() {
    if ${VERBOSE} ; then
        echo "$1"
    else
        if [ -n "$2" ] ; then
            echov "$2"
        fi
    fi
}

printf_green() {
    printf "\\033[0;32m%s\\033[0m\\n" "$1"
}

get_distro_name() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        # shellcheck disable=SC1091
        . /etc/os-release
        printf "%s" "$NAME"
    elif command -V lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        printf "%s" "$(lsb_release -si)"
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        # shellcheck disable=SC1091
        . /etc/lsb-release
        printf "%s" "$DISTRIB_ID"
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        printf "Debian"
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        printf "%s" "$(uname -s)"
    fi
}

get_distro_ver() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        # shellcheck disable=SC1091
        . /etc/os-release
        printf "%s" "$VERSION_ID"
    elif command -V lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        printf "%s" "$(lsb_release -sr)"
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        # shellcheck disable=SC1091
        . /etc/lsb-release
        printf "%s" "$DISTRIB_RELEASE"
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        printf "%s" "$(cat /etc/debian_version)"
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        printf "%s" "$(uname -r)"
    fi
}


get_arch() {
    myarch=$(uname -m)

    case "${myarch}" in
    x86_64)
        printf "x86_64"  # or AMD64 or Intel64 or whatever
        ;;
    i*86)
        printf "i386"  # or IA32 or Intel32 or whatever
        ;;
    *)
        die "Cannot figure out architecture (was: ${myarch})"
        ;;
    esac

    unset myarch
}

get_download_url() {
    myghcver=$1
    myarch=$(get_arch)
    mydistro=$(get_distro_name)
    mydistrover=$(get_distro_ver)
    baseurl="https://downloads.haskell.org/~ghc"

    # TODO: awkward, restructure
    case "${mydistro},${mydistrover},${myarch},${myghcver}" in
    Debian,7,i386,8.2.2)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb${mydistrover}-linux.tar.xz"
        ;;
    *,*,i386,*)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb8-linux.tar.xz"
        ;;
    Debian,*,*,8.2.2)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb8-linux.tar.xz"
        ;;
    Debian,8,*,*)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb8-linux.tar.xz"
        ;;
    Debian,*,*,*)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb9-linux.tar.xz"
        ;;
    Ubuntu,*,*,8.2.2)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb8-linux.tar.xz"
        ;;
    Ubuntu,*,*,*)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb9-linux.tar.xz"
        ;;
    *,*,*,8.2.2)
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-deb8-linux.tar.xz"
        ;;
    *,*,*,*) # this is our best guess
        printf "%s" "${baseurl}/${myghcver}/ghc-${myghcver}-${myarch}-fedora27-linux.tar.xz"
        ;;
    esac

    unset myghcver myarch mydistro mydistrover baseurl
}


## subcommand install ##

install_ghc() {
    myghcver=$1
    downloader=curl
    downloader_opts="--fail -O"
    inst_location=${INSTALL_BASE}/ghc/${myghcver}
    target_location=${INSTALL_BASE}/bin
    download_url=$(get_download_url "${myghcver}")
    download_tarball_name=$(basename "${download_url}")

    if [ -e "${inst_location}" ] ; then
        if ${FORCE} ; then
            echo "GHC already installed in ${inst_location}, overwriting!"
        else
            die "GHC already installed in ${inst_location}, use --force to overwrite"
        fi
    fi

    printf_green "Installing GHC for $(get_distro_name) on architecture $(get_arch)"
    tmp_dir=$(mktemp -d)
    [ -z "${tmp_dir}" ] && die "Failed to create temporary directory"
    (
        edo cd "${tmp_dir}"

        echov "Downloading ${download_url}"
        # shellcheck disable=SC2086
        edo ${downloader} ${downloader_opts} "${download_url}"

        edo tar -xf ghc-*-linux.tar.xz
        edo cd "ghc-${myghcver}"

        echov "Installing GHC into ${inst_location}"

        edo ./configure --prefix="${inst_location}"
        edo make install

        # clean up
        edo cd ..
        [ -e "${tmp_dir}/${download_tarball_name}" ] && rm "${tmp_dir}/${download_tarball_name}"
        [ -e "${tmp_dir}/ghc-${myghcver}" ] && rm -r "${tmp_dir}/ghc-${myghcver}"
    ) || {
        [ -e "${tmp_dir}/${download_tarball_name}" ] && rm "${tmp_dir}/${download_tarball_name}"
        [ -e "${tmp_dir}/ghc-${myghcver}" ] && rm -r "${tmp_dir}/ghc-${myghcver}"
        die "Failed to install"
    }

    [ -e "${target_location}" ] || mkdir "${target_location}"

    for f in "${inst_location}"/bin/*-"${myghcver}" ; do
        [ -e "${f}" ] || die "Something went wrong, ${f} does not exist!"
        fn=$(basename "${f}")
        # shellcheck disable=SC2046
        edo ln $(echov "-v") -sf ../ghc/"${myghcver}/bin/${fn}" "${target_location}/${fn}"
        unset fn
    done
    # shellcheck disable=SC2046
    edo ln $(echov "-v") -sf ../ghc/"${myghcver}"/bin/runhaskell "${target_location}/runhaskell-${myghcver}"

    printf_green "Done installing, run \"ghci-${myghcver}\" or set up your current GHC via: ${SCRIPT} set-ghc ${myghcver}"

    unset myghcver downloader downloader_opts inst_location target_location f download_url download_tarball_name
}


## subcommand set-ghc ##

set_ghc() {
    myghcver=$1
    target_location=${INSTALL_BASE}/bin
    inst_location=${INSTALL_BASE}/ghc/${myghcver}

    [ -e "${inst_location}" ] || die "GHC ${myghcver} not installed yet, use: ${SCRIPT} install ${myghcver}"
    [ -e "${target_location}" ] || edo mkdir "${target_location}"

    printf_green "Setting GHC to ${myghcver}"

    for f in "${inst_location}"/bin/*-"${myghcver}" ; do
        [ -e "${f}" ] || die "Something went wrong, ${f} does not exist!"
        source_fn=$(basename "${f}")
        target_fn=$(echo "${source_fn}" | sed "s#-${myghcver}##")
        # shellcheck disable=SC2046
        edo ln $(echov "-v") -sf ../ghc/"${myghcver}/bin/${source_fn}" "${target_location}/${target_fn}"
        unset source_fn target_fn
    done
    # shellcheck disable=SC2046
    edo ln $(echov "-v") -sf runghc "${target_location}"/runhaskell

    printf_green "Done, make sure \"${target_location}\" is in your PATH!"

    unset myghcver target_location inst_location f
}


## self-update subcommand ##

self_update() {
    target_location=$1
    source_url="https://raw.githubusercontent.com/hasufell/ghcup/master/ghcup.sh"
    downloader=curl
    downloader_opts="--fail -O"

    [ -e "${target_location}" ] || die "Destination \"${target_location}\" does not exist, cannot update script"

    printf_green "Updating ${SCRIPT}"

    (
        edo cd "$(mktemp -d)"

        echov "Downloading ${source_url}"
        # shellcheck disable=SC2086
        edo ${downloader} ${downloader_opts} "${source_url}"
        edo mv ghcup.sh "${target_location}"/ghcup.sh
        edo chmod +x "${target_location}"/ghcup.sh
    )

    printf_green "Done, make sure \"${target_location}\" is in your PATH!"

    unset target_location source_url downloader downloader_opts
}

## show subcommand ##

show_ghc() {
    ghc_location=${INSTALL_BASE}/ghc
    current_ghc=$(show_ghc_installed)

    echo "Installed GHCs:"
    for i in "${ghc_location}"/* ; do
        [ -e "${i}" ] || die "Something went wrong, ${i} does not exist!"
        echo "    $(basename "${i}")"
    done

    if [ -n "${current_ghc}" ] ; then
        echo
        echo "Current GHC"
        echo "    ${current_ghc}"
    fi

    unset target_location i
}

show_ghc_installed() {
    target_location=${INSTALL_BASE}/bin
    real_ghc=$(realpath "${target_location}/ghc")

    if [ -e "${real_ghc}" ] ; then
        real_ghc="$(basename "${real_ghc}" | sed 's#ghc-##')"
        printf "%s" "${real_ghc}"
    fi

    unset target_location real_ghc
}


## command line parsing and entry point ##

# sanity checks
if [ -z "$HOME" ] ; then
    die "HOME env not set, cannot operate"
fi

[ $# -lt 1 ] && usage

while [ $# -gt 0 ] ; do
    case $1 in
    -v|--verbose)
        VERBOSE=true
        shift 1;;
    -V|--version)
        printf "%s" "${VERSION}"
        exit 0;;
    -h|--help)
        usage;;
    *) case $1 in
       install)
           shift 1
           while [ $# -gt 0 ] ; do
               case $1 in
                   -h|--help) install_usage;;
                   -f|--force) FORCE=true
                       shift 1;;
                   *) GHC_VER=$1
                      break;;
               esac
           done
           [ "${GHC_VER}" ] || install_usage
           install_ghc "${GHC_VER}"
           break;;
       set)
           shift 1
           while [ $# -gt 0 ] ; do
               case $1 in
                   -h|--help) set_usage;;
                   *) GHC_VER=$1
                      break;;
               esac
           done
           [ "${GHC_VER}" ] || set_usage
           set_ghc "${GHC_VER}"
           break;;
       self-update)
           shift 1
           while [ $# -gt 0 ] ; do
               case $1 in
                   -h|--help) self_update_usage;;
                   *) TARGET_LOCATION=$1
                       break;;
               esac
           done
           if [ "${TARGET_LOCATION}" ] ; then
               self_update "${TARGET_LOCATION}"
           else
               self_update "${HOME}/.local/bin"
           fi
           break;;
       show)
           SHOW_INSTALLED=false
           shift 1
           while [ $# -gt 0 ] ; do
               case $1 in
                   -h|--help) show_usage;;
                   -i|--installed) SHOW_INSTALLED=true
                       break;;
                   *) show_usage;;
               esac
           done
           if ${SHOW_INSTALLED} ; then
               show_ghc_installed
           else
               show_ghc
           fi
           break;;
       *) usage;;
       esac
       break;;
    esac
done

