#!/bin/bash

# Build www-servers/apache with different settings.
# Remember to handle "normal" one too!

shopt -s nullglob
pkg=( /usr/portage/packages/www-servers/apache* )

if [[ -n ${pkg} ]]; then
	echo "There is already a tbz2. Check it!" >&2
	exit 1
fi

set -x
USE="threads apache2_modules_http2" APACHE2_MPMS="worker" \
	emerge -B www-servers/apache::sabayon || exit 1

ENTROPY_PROJECT_TAG="worker" eit inject /usr/portage/packages/www-servers/apache*
