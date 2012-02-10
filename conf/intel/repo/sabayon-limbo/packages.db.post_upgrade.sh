#!/bin/sh

[ -z "$4" ] && echo "not enough parameters" && exit 1

REPO_ID=$1
ROOT=$2
OLD_BRANCH=$3
NEW_BRANCH=$4

echo -e "
>> requirements for this branch:
   app-admin/eselect-python
   sys-devel/base-gcc:<latest>
>> Entropy post-upgrade migration script
>> Repository: "${REPO_ID}"
>> Root: "${ROOT}"
>> Old branch: "${OLD_BRANCH}"
>> New branch: "${NEW_BRANCH}"

>> ATTENTION ATTENTION ATTENTION
>> - If you are upgrading from a previous branch (say, 4)
>>   and you are a NetworkManager user, make sure to have
>>   your users inside the "netdev" group.
>> - If you compile stuff manually, it is strongly
>>   suggested to install "lafilefixer" and execute:
>>     # lafilefixer --justfixit
>> ATTENTION ATTENTION ATTENTION

"

### CUT HERE ###

fix_lib64_symlinks() {
	if [ -L ${ROOT}/lib64 ] ; then
		echo "removing /lib64 symlink and moving lib to lib64..."
		echo "dont hit ctrl-c until this is done"
		rm ${ROOT}/lib64
		# now that lib64 is gone, nothing will run without calling ld.so
		# directly. luckily the window of brokenness is almost non-existant
		/lib/ld-linux-x86-64.so.2 /bin/mv ${ROOT}/lib ${ROOT}/lib64
		# all better :)
		ldconfig
		ln -s lib64 ${ROOT}/lib
		echo "done! :-)"
		echo "fixed broken lib64/lib symlink in ${ROOT}"
	fi
	if [ -L ${ROOT}/usr/lib64 ] ; then
		rm ${ROOT}/usr/lib64
		mv ${ROOT}/usr/lib ${ROOT}/usr/lib64
		ln -s lib64 ${ROOT}/usr/lib
		echo "fixed broken lib64/lib symlink in ${ROOT}/usr"
	fi
	if [ -L ${ROOT}/usr/X11R6/lib64 ] ; then
		rm ${ROOT}/usr/X11R6/lib64
		mv ${ROOT}/usr/X11R6/lib ${ROOT}/usr/X11R6/lib64
		ln -s lib64 ${ROOT}/usr/X11R6/lib
		echo "fixed broken lib64/lib symlink in ${ROOT}/usr/X11R6"
	fi
}

three_four_to_five() {

    local rc=0

    # switch Python to latest available, 2.7
    eselect python update --ignore 3.0 --ignore 3.1 --ignore 3.2 --ignore 3.3 --ignore 3.4
    [ "${?}" != "0" ] && echo "eselect-python not available" && rc=1

    # configure correct binutils
    # new profile needs to be configured
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

    # set proper eselect esd engine
    if [ -f "${ROOT}/usr/bin/esdcompat" ]; then
        eselect esd list | grep PulseAudio | cut -d"[" -f 2 | \
            cut -d"]" -f 1 | xargs eselect esd set &> /dev/null
    fi

    # make sure working eselect boost is selected
    e_boost_mod="${ROOT}/usr/share/eselect/modules/boost.eselect"
    if [ -f "${e_boost_mod}" ]; then
        eselect boost update &> /dev/null
    fi

    # move alsa conf to new location
    [ -f "${ROOT}/etc/modprobe.d/alsa" ] && \
        mv "${ROOT}/etc/modprobe.d/alsa" "${ROOT}/etc/modprobe.d/alsa.conf"

    # try to mount /boot, ignore all the possible bullshit
    # [ "${ROOT}" = "/" ] && mount /boot &> /dev/null
    # setup grub.conf, if found
    [ -f "${ROOT}boot/grub/grub.conf" ] && \
        sed -i 's/CONSOLE=\/dev\/tty1/console=tty1/g' "${ROOT}/boot/grub/grub.conf"

    # setup grub.conf, if found, change nox into gentoo=nox
    [ -f "${ROOT}boot/grub/grub.conf" ] && \
        sed -i 's/ nox / gentoo=nox /g' "${ROOT}/boot/grub/grub.conf"

    # setup /etc/localtime correctly
    if [ -f "${ROOT}etc/timezone" ]; then
        tzdata=$(cat "${ROOT}etc/timezone")
        rm -f "${ROOT}etc/localtime" && ln -sf "/usr/share/zoneinfo/${tzdata}" "${ROOT}etc/localtime"
    fi

    # always add udev to sysinit
    rc-update add udev sysinit &> /dev/null
    exit ${rc}
}

# run this in any case, it will fix symlinks setup
if [ "$(uname -m)" = "x86_64" ]; then
	fix_lib64_symlinks
fi

# migration script from branch 4 to 5
[ "${OLD_BRANCH}" = "4" ] && [ "${NEW_BRANCH}" = "5" ] && three_four_to_five

# migration script from branch 3.5 to 5
[ "${OLD_BRANCH}" = "3.5" ] && [ "${NEW_BRANCH}" = "5" ] && three_four_to_five

echo "migration switch not found"
exit 1

