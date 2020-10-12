import bz2
import os
import sys
sys.path.insert(0, "/usr/lib/entropy/lib")
import entropy.tools
from entropy.db.sqlite import EntropySQLiteRepository


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


if __name__ == "__main__":
    _repodir = sys.argv[1]
    if len(_repodir) == 0:
        print("Invalid repo dir")
        sys.exit(1)
    fixup_repository(_repodir)
    sys.exit(0)
