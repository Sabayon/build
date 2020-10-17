#!/bin/bash
# Author: Daniele Rondina, geaaru@sabayonlinux.org

set -xe

BASE_DIR="${BASE_DIR:-/sabayon/rsync/rsync.sabayon.org/entropy/standard}"
SOURCE_DIR=${SOURCE_DIR:-${BASE_DIR}/sabayonlinux.org}
DEST_DIR=${DEST_DIR:-${BASE_DIR}/sabayon-weekly}
SSH_KEY=${SSH_KEY:-/sabayon/conf/ssh/id_rsa}

RSYNC_BIN=${RSYNC_BIN:-/usr/bin/rsync}
RSYNC_ARGS=${RSYNC_ARGS:--avP --delay-updates}
RSYNC_BASE_PARAMS=${RSYNC_BASE_PARAMS:---exclude 'packages*/*' --exclude '*.asc' --delete --delete-during --delete-excluded}

SSH_BIN=${SSH_BIN:-/usr/bin/ssh}
SSH_ARGS=${SSH_ARGS:--i ${SSH_KEY} -p 9222}
REMOTE_HOST=${REMOTE_HOST:-entropy@pkg.sabayon.org}
REMOTE_DIR=${REMOTE_DIR:-~/standard/sabayon-weekly}

STAGING_DIR=${STAGING_DIR:-$(mktemp -u -d)}
FIXUP_REPO_SCRIPT=${FIXUP_REPO_SCRIPT:-fixup_repository.py}

main () {
  # Run local rsync to a staging dir to fix treeupdates

  # Clean previous staging dir if exists
  rm -rf ${STAGING_DIR} || true
  mkdir -p ${STAGING_DIR}

  local temp_dest_dir=${STAGING_DIR}/update_sabayon_weekly_repo
  mkdir -p ${temp_dest_dir}

  ${RSYNC_BIN} ${RSYNC_ARGS} ${SOURCE_DIR} ${temp_dest_dir} ${RSYNC_BASE_PARAMS}

  # recreate:
  # - packages.db.bz2
  # - packages.db.dumplight.bz2
  # - packages.db.light.bz2
  local dbdir=${temp_dest_dir}/database
  local archdir=${dbdir}/amd64
  local branchdir=${archdir}/5

  ${FIXUP_REPO_SCRIPT} ${branchdir}

  # rsync from the staging directory to the final
  ${RSYNC_BIN} ${RSYNC_ARGS} ${temp_dest_dir}/ ${DEST_DIR}/

  echo "check $DEST_DIR..."
  return 0

  # create remote directory
  ${SSH_BIN} ${SSH_ARGS} ${REMOTE_HOST} mkdir -p ${REMOTE_DIR} || true

  # push the repo to packages.sabayon.org
  ${RSYNC_BIN} ${RSYNC_ARGS} "--rsh=${SSH_ARGS}" ${DEST_DIR}/ ${REMOTE_HOST}:${REMOTE_DIR}/

  # WHY?????
  local weekly_db=${branchdir}/packages.db.bz2
  local remote_weekly_dir=${REMOTE_DIR}/database/amd64/5
  local remote_weekly_db=${remote_weekly_dir}/packages.db.bz2

  ${RSYNC_BIN} ${RSYNC_ARGS} "--rsh=${SSH_ARGS}" ${weekly_db} ${REMOTE_HOST}:${remote_weekly_db}

  # final touch to notify the web service
  local remote_weekly_eapi3_upd=${remote_weekly_dir}/packages.db.eapi3_updates
  ${SSH_BIN} ${SSH_ARGS} touch ${remote_weekly_eapi3_upd}

  rm -rf ${temp_dest_dir}

  return 0
}

main $@
exit $?
