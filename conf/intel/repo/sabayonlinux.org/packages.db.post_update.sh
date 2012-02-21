#!/bin/sh
# Entropy Framework 1.0
# Entropy Client post repository update (equo update <repoid>) script
# -- called every time repositories are updated --
#
# This is a sample file shipped with client repositories which contains
# per-repository post repository update hook. More precisely, this script is
# triggered when entropy updates repositories. As stated, this script is PER-
# repository and it's shipped with it.
# It MUST return 0, any different value will be considered as critical error.
#
# This script must be called with specific arguments explained here below:
#
#     # sh packages.db.post_upgrade.sh [REPOSITORY_ID] [ROOT] [ENTROPY_BRANCH]
#
# example:
#
#     # sh packages.db.post_branch.sh "sabayonlinux.org" "/" "5"
#
# PLEASE NOTE: this script is called automatically by entropy and, unless
# requested otherwise, it should be NEVER EVER called by user.

[ "$(id -u)" != "0" ] && echo && echo "Skipping update script, you are not root" && exit 0

[ -z "$3" ] && echo "not enough parameters" && exit 1

REPO_ID=$1
ROOT=$2
BRANCH=$3

configure_correct_binutils() {
    # configure correct binutils
    # new profile needs to be configured
    echo
    binutils_dir="${ROOT}/etc/env.d/binutils"
    if [ -d "${binutils_dir}" ]; then
        binutils_profile=$(find "${binutils_dir}" -name "$(uname -m)*" | \
            sort | tail -n 1 | xargs basename)
        echo "trying to set binutils profile ${binutils_profile}"
        binutils-config ${binutils_profile}
    else
        echo "binutils directory ${binutils_dir} not found"
        echo "cannot properly set binutils profile"
        rc=1
    fi
}

if [ ! -f "/usr/$(uname -m)-pc-linux-gnu/bin/ld" ]; then
	configure_correct_binutils
fi

autoconfl_file="${ROOT}/etc/env.d/00-entropy-autoconflict"
if [ -e "${autoconfl_file}" ]; then
	rm -f "${autoconfl_file}"
fi

exit 0

### CUT HERE ###
