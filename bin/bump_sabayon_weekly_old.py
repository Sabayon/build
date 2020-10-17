#!/usr/bin/python
import bz2
import os
import shutil
import subprocess
import sys
import tempfile
import time
sys.path.insert(0, "/usr/lib/entropy/lib")
import entropy.tools
from entropy.db.sqlite import EntropySQLiteRepository
def notify_update(exit_st):
    proc = subprocess.Popen(
        ("/usr/bin/mail", "-s", "sabayon-weekly updated", "root"),
        stdin=subprocess.PIPE)
    proc.stdin.write("Hello boys and girls, sabayon-weekly has been "
                     "updated, exit: %d\n" % (exit_st,))
    proc.stdin.close()
    return proc.wait()
def fault_tolerant_exec(args):
    count = 3
    while count >= 0:
        proc = subprocess.Popen(args)
        exit_st = proc.wait()
        if exit_st == 0:
            return 0
        sys.stderr.write("%s failed. retry: %d\n" % (
                " ".join(args), exit_st))
        time.sleep(60.0)
    return 1
def fixup_repository(repository_dir):
    print("Repository fixup for %s" % (repository_dir,))
    bz2_path = os.path.join(repository_dir, "packages.db.bz2")
    db_path = entropy.tools.unpack_bzip2(bz2_path)
    repo = EntropySQLiteRepository(
        dbFile=db_path,
        name="sabayon-weekly",
        indexing=False,
        skipChecks=True)
    updates = repo.listAllTreeUpdatesActions()
    new_updates = []
    for idupdate, repository, command, branch, date in updates:
        if repository == "sabayonlinux.org":
            repository = "sabayon-weekly"
        new_updates.append(
            (idupdate, repository, command, branch, date))
    repo.bumpTreeUpdatesActions(new_updates)
    repo.clean()
    repo.dropAllIndexes()
    repo.dropContentSafety()
    repo.vacuum()
    repo.commit()
    # now close, amen
    repo.close()
    # update packages.db.bz2
    f_out = bz2.BZ2File(bz2_path + ".tmp", "wb")
    with open(db_path, "rb") as f_in:
        data = f_in.read(1024000)
        while data:
            f_out.write(data)
            data = f_in.read(1024000)
    f_out.close()
    os.rename(bz2_path + ".tmp", bz2_path)
    entropy.tools.create_md5_file(bz2_path)
    # update packages.db.light.bz2, reopen repo
    repo = EntropySQLiteRepository(
        dbFile=db_path,
        name="sabayon-weekly",
        indexing=False,
        skipChecks=True)
    repo.dropContent()
    repo.dropChangelog()
    repo.vacuum()
    repo.commit()
    # update packages.db.dumplight
    dumplight_path = os.path.join(repository_dir, "packages.db.dumplight.bz2")
    f_out = bz2.BZ2File(dumplight_path + ".tmp", "wb")
    repo.exportRepository(f_out)
    f_out.close()
    os.rename(dumplight_path + ".tmp", dumplight_path)
    entropy.tools.create_md5_file(dumplight_path)
    # now close, amen
    repo.close()
    light_path = os.path.join(repository_dir, "packages.db.light.bz2")
    f_out = bz2.BZ2File(light_path + ".tmp", "wb")
    with open(db_path, "rb") as f_in:
        data = f_in.read(1024000)
        while data:
            f_out.write(data)
            data = f_in.read(1024000)
    f_out.close()
    os.rename(light_path + ".tmp", light_path)
    entropy.tools.create_md5_file(light_path)
    os.remove(db_path)
    # add UPDATE_EAPI=2 to packages.db.webservices
    ws_path = os.path.join(repository_dir, "packages.db.webservices")
    if os.path.isfile(ws_path):
        with open(ws_path, "a+") as ws:
            ws.write("\n")
            ws.write("UPDATE_EAPI=2\n")
def sync(source_dir, dest_dir, ssh_id):
    ionice_args = ["/usr/bin/ionice", "-c", "3"]
    rsync_path = "/usr/bin/rsync"
    ionice_rsync_path = " ".join(ionice_args) + " " + rsync_path
    minimal_rsync_args = [rsync_path, "-avP", "--delay-updates"]
    ssh_minimal_args = ["/usr/bin/ssh", "-i", ssh_id,
                        "-p", "2222"]
    remote_host = "entropy@sabayon.org"
    remote_dir = "~/standard/sabayon-weekly"
    ssh_args = ssh_minimal_args + [remote_host]
    base_rsync_params = [
        "--exclude", "packages*/*",
        "--exclude", "*.asc",
        "--delete", "--delete-during",
        "--delete-excluded"]
    temp_dest_dir = None
    try:
        # rsync to a staging dir, to fix treeupdates
        temp_dest_dir = tempfile.mkdtemp(prefix="update_sabayon_weekly_repo")
        args = ionice_args + minimal_rsync_args + [
            source_dir + "/", temp_dest_dir + "/"] + base_rsync_params
        exit_st = fault_tolerant_exec(args)
        if exit_st != 0:
            return exit_st
        # recreate:
        # - packages.db.bz2
        # - packages.db.dumplight.bz2
        # - packages.db.light.bz2
        db_dir = os.path.join(temp_dest_dir, "database")
        for arch in os.listdir(db_dir):
            arch_dir = os.path.join(db_dir, arch)
            if not os.path.isdir(arch_dir):
                continue
            for branch in os.listdir(arch_dir):
                branch_dir = os.path.join(arch_dir, branch)
                if not os.path.isdir(branch_dir):
                    continue
                fixup_repository(branch_dir)
        # rsync from the staging directory to the final
        args = ionice_args + minimal_rsync_args + [
            temp_dest_dir + "/", dest_dir + "/"]
        exit_st = fault_tolerant_exec(args)
        if exit_st != 0:
            return exit_st
        # create remote directory
        args = ssh_args + ["mkdir", "-p", remote_dir]
        exit_st = fault_tolerant_exec(args)
        if exit_st != 0:
            return exit_st
        # push the repo to packages.sabayon.org
        args = minimal_rsync_args + [
            "--rsync-path=%s" % (ionice_rsync_path,),
            "--rsh=%s" % (" ".join(ssh_minimal_args),),
            dest_dir + "/", remote_host + ":" + remote_dir + "/"]
        exit_st = fault_tolerant_exec(args)
        if exit_st != 0:
            return exit_st
        db_dir = os.path.join(dest_dir, "database")
        for arch in os.listdir(db_dir):
            arch_dir = os.path.join(db_dir, arch)
            if not os.path.isdir(arch_dir):
                continue
            for branch in os.listdir(arch_dir):
                branch_dir = os.path.join(arch_dir, branch)
                if not os.path.isdir(branch_dir):
                    continue
                weekly_db = os.path.join(
                    temp_dest_dir, "database", arch,
                    branch, "packages.db.bz2")
                print(
                    "Doing %s, arch: %s, branch: %s" % (
                        weekly_db, arch, branch))
                remote_weekly_dir = os.path.join(
                    remote_dir, "database", arch, branch)
                remote_weekly_db = os.path.join(
                    remote_weekly_dir, "packages.db.bz2")
                args = minimal_rsync_args + [
                    "--rsync-path=%s" % (ionice_rsync_path,),
                    "--rsh=%s" % (" ".join(ssh_minimal_args),),
                    weekly_db, remote_host + ":" + remote_weekly_db]
                exit_st = fault_tolerant_exec(args)
                if exit_st != 0:
                    return exit_st
                # final touch to notify the web service
                remote_weekly_eapi3_upd = os.path.join(
                    remote_weekly_dir, "packages.db.eapi3_updates")
                args = ssh_args + ["touch", remote_weekly_eapi3_upd]
                exit_st = fault_tolerant_exec(args)
                if exit_st != 0:
                    return exit_st
    finally:
        if temp_dest_dir is not None:
            shutil.rmtree(temp_dest_dir, True)
    return 0
if __name__ == "__main__":
    _base_dir = "/sabayon/rsync/rsync.sabayon.org/entropy/standard"
    _source_dir = os.path.join(_base_dir, "sabayonlinux.org")
    _dest_dir = os.path.join(_base_dir, "sabayon-weekly")
    _ssh_id = "/sabayon/conf/ssh/id_rsa"
    _exit_st = sync(_source_dir, _dest_dir, _ssh_id)
    notify_update(_exit_st)
    raise SystemExit(_exit_st)
