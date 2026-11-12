#!/bin/bash
# One-shot root image build (README step 2) for hosts where sudo needs an
# interactive prompt: run the whole thing once as root, e.g.
#
#   sudo tools/mkroot-all.sh IPSW_DIR OUT_PREFIX [SIZE] [OWNER]
#
# IPSW_DIR holds the OS, SystemOS and AppOS .dmg of iPhone10,3 20H392
# (names from BuildManifest.plist: 087-86698-044 / 087-86593-047 / 087-86715-047).
# Produces OUT_PREFIX.img (raw HFS+) and OUT_PREFIX.simg (for fastboot), owned by OWNER.
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
[[ $# -ge 2 ]] || { sed -n '2,10p' "$0"; exit 2; }
dir=$1 out=$2 size=${3:-16G} owner=${4:-${SUDO_USER:-root}}
here=$(cd "$(dirname "$0")" && pwd)

# Resume: an existing OUT_PREFIX.img from an earlier run is reused (mkiosroot's
# final read-only fsck can report "Volume header needs minor repair" with the
# Linux fsck_hfs 540.1 even right after a successful -y repair -> exit 8).
if [[ -e $out.img ]]; then
	echo "reusing existing $out.img"
else
	"$here/mkiosroot.sh" "$dir/087-86698-044.dmg" "$dir/087-86593-047.dmg" "$dir/087-86715-047.dmg" "$out.img" "$size" || true
	[[ -e $out.img ]] || exit 1
fi
fsck.hfsplus -fy "$out.img" | tail -3
mnt=$(mktemp -d)
mount -t hfsplus -o loop,force "$out.img" "$mnt"
trap 'mountpoint -q "$mnt" && umount "$mnt"; rmdir "$mnt" 2>/dev/null || true' EXIT
python3 -I "$here/sweet-root-tweaks.py" "$mnt"
df -h "$mnt"
umount "$mnt"
fsck.hfsplus -fy "$out.img" | tail -3
img2simg "$out.img" "$out.simg"
chown "$owner": "$out.img" "$out.simg"
ls -l "$out.img" "$out.simg"
echo "MKROOT-ALL DONE"
