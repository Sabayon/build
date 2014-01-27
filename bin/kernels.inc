kernels="$(for d in $(find /usr/src -maxdepth 1 -name "linux-*-sabayon" -type d -print); do d=$(basename $d); echo ${d/linux-}; done | sort)"

running_kernel="$(d=$(basename $(readlink /usr/src/linux)); echo ${d/linux-})"
