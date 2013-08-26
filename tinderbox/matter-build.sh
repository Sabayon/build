#!/bin/bash

show_help() {
	echo "${0} <schedule> <pre-chroot (linux32, linux64)> <chroot dir> <chroot name>"
}

ARGS="${@}"
schedule="${1}"
if [ "${schedule}" != "weekly" ] && [ "${schedule}" != "monthly" ] && [ "${schedule}" != "daily" ]; then
	echo "schedule is invalid, must be either weekly, monthly, daily"
	show_help
	exit 1
fi
PRE_CHROOT="${2}"
if [ "${PRE_CHROOT}" != "linux32" ] && [ "${PRE_CHROOT}" != "linux64" ]; then
	echo "pre-chroot is invalid, must be either linux32, linux64"
	show_help
	exit 1
fi
CHROOT_DIR="${3}"
if [ -z "${CHROOT_DIR}" ] || [ ! -d "${CHROOT_DIR}" ]; then
	echo "chroot dir is invalid"
	show_help
	exit 1
fi
CHROOT_NAME="${4:-unknown}"
shift 4

LOCK_FILE="${CHROOT_DIR}/.matter-build.lock"
LVM_LOCK_FILE="/entropy_LOCKS/vg_chroots-lv_chroots-snapshot.lock"
LOG_FILE=/var/log/particles/$(basename "${CHROOT_DIR}")-${schedule}-$(date +%Y%m%d).log

# Make sure th have these directories in place
mkdir -p /var/log/particles /entropy_LOCKS || exit 1

echo "CHROOT_DIR: ${CHROOT_DIR}"
echo "PRE_CHROOT: ${PRE_CHROOT}"
echo "LOG_FILE: ${LOG_FILE}.bz2"

echo "Acquiring locks at ${LOCK_FILE} and ${LVM_LOCK_FILE} in blocking mode, waiting until we're ready"
(
	flock -s --timeout=$((3600 * 12)) 10
	if [ "${?}" != "0" ]; then
		echo "Tried to acquire the LVM lock in shared mode." >&2
		echo "After 12 hours, I give up. This is really wrong," >&2
		echo "since the backup script should not hold the lock for" >&2
		echo "this long." >&2
		exit 1
	fi

	flock -x --timeout=36000 9
	rc="${?}"
	if [ "${rc}" != "0" ]; then
		echo "CANNOT ACQUIRE LOCK, QUITTING" >&2
	else
		echo "Lock acquired, let's go"
		echo "Starting matter-scheduler at $(date)..."
		export ETP_NO_COLOR="1"

		pre_post="--pre /particles/hooks/pre.sh --post /particles/hooks/post.sh"
		# Place standard outout and standard error together to make
		# tee happy. Filter out stdout because it gets to mail
		PARTICLES_DIR="/particles/${schedule}" \
		MATTER_ARGS="--commit --blocking --gentle --disable-preserved-libs ${pre_post} ${@}" "${PRE_CHROOT}" \
			/build/tinderbox/matter-scheduler "${CHROOT_DIR}" 2>&1 3>&1 | tee "${LOG_FILE}" > /dev/null
		rc=${?}
		echo "Completed matter-scheduler at $(date) with exit status: ${rc}"
	fi

	bzip2 -f -k "${LOG_FILE}"
	# send mail
	echo "Hello boys and girls,
this is orion.sabayon.org informing you that a new matter run has been
eventually executed.

Call : ${ARGS}
Exit : ${rc}
Log  : ${LOG_FILE}.bz2

Do not forget to check logs before touching repositories.
Thanks for reading." | mutt -s "${schedule} matter run, $(basename ${LOG_FILE})" -a "${LOG_FILE}.bz2" -- entropy-team@lists.sabayon.org

	# spawn AntiMatter and ignore any failures
	/build/tinderbox/antimatter-scheduler "${CHROOT_DIR}" "${CHROOT_NAME}" "${PRE_CHROOT}" > /dev/null

	exit ${rc}

) 9> "${LOCK_FILE}" 10> "${LVM_LOCK_FILE}"
