#!/bin/bash
echo "Loading settings..."
DEBUG=
RAMDISKMAX=

if [ ! -z "$1" ] && [ -f "$1" ]; then
	. "$1"
elif [ -f "$(dirname $0)/vendor.cfg" ]; then
	. "$(dirname $0)/vendor.cfg"
fi

KEYBOARD_LAYOUT_CODE=${KEYBOARD_LAYOUT_CODE:-"us"}
KEYBOARD_LAYOUT=${KEYBOARD_LAYOUT:-"English (US)"}
KEYBOARD_LAYOUT_VARIANT=${KEYBOARD_LAYOUT_VARIANT:-"English (US)"}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-"10"}
SETUP_LANGUAGE=${SETUP_LANGUAGE:-"en"}
SETUP_LOCALE=${SETUP_LOCALE:-"en_US.UTF-8"}

VENDOR=${VENDOR:-"Custom"}
VENDOR_LC=$(echo "$VENDOR"|tr A-Z a-z|sed -e "s/ /-/g")

UBUNTU_ARCH=${UBUNTU_ARCH:-"amd64"}
UBUNTU_VERSION=${UBUNTU_VERSION:-"16.04"}
UBUNTU_SUBREL=${UBUNTU_SUBREL:-".3"}

COUNTRY=${COUNTRY:-"BE"}
TIMEZONE=${TIMEZONE:-"Europe/Brussels"}
NTP_SERVER=${NTP_SERVER:-"$(echo $COUNTRY|tr A-Z a-z).pool.ntp.org"}
NTP_ENABLED=${NTP_ENABLED:-"true"}

NET_DEF_IP=${NET_DEF_IP:-""}
NET_DEF_GW=${NET_DEF_GW:-""}
NET_DEF_MASK=${NET_DEF_MASK:-"255.255.255.0"}
NET_DEF_DNS=${NET_DEF_DNS:-"8.8.8.8 8.8.4.4"}
NET_DEF_HOST=${NET_DEF_HOST:-"host"}
NET_DEF_DOMAIN=${NET_DEF_DOMAIN:-"default.domain"}

INSTALL_TASKSEL=${INSTALL_TASKSEL:-"standard, ssh-server"}
INSTALL_PACKAGES=${INSTALL_PACKAGES:-"openssh-server openssh-client python-minimal vim tree htop wget curl ntp netcat pv socat"}


USER_NAME=${USER_NAME:-"ubuntu"}
HASH_ALGO=${HASH_ALGO:-"sha-512"}

#mkpasswd -m sha-512 -S $(pwgen -ns 16 1)
if [ -z "$USER_PASSWORD_ENC" ] && [ -z "${USER_PASSWORD}" ]; then
	USER_PASSWORD="ubuntu"
	echo "- !! WARNING!!! Setting default password for user '${USER_NAME}'."
fi
if [ -z "$USER_PASSWORD_ENC" ] && [ -n "${USER_PASSWORD}" ]; then
	echo "- Hashing insecure password with ${HASH_ALGO} for user '${USER_NAME}'"
	USER_PASSWORD_ENC=$(echo -e "${USER_PASSWORD}" | mkpasswd --stdin -m ${HASH_ALGO} -S $(pwgen -ns 16 1))
	echo "- Hashed password: '${USER_PASSWORD_ENC}'"
fi

function replFile {
	# Make sure escaping is done correctly
	ESC_VAL=$(eval printf "%q" \"\$${2}\")
	
	# Catch empty escaped strings
	[ "$ESC_VAL" == "''" ] && ESC_VAL=
	
	#echo "---- Escaped value for '$2' = '$ESC_VAL'"
	sudo sed -i -e "s@%$2%@$ESC_VAL@g" "$1"
}

function replVars {
	[ -f "$1" ] || {
		echo "### WARN: File $1 not found"
		return
	}
	
	replFile "$1" BOOT_TIMEOUT
	replFile "$1" KEYBOARD_LAYOUT_CODE
	replFile "$1" KEYBOARD_LAYOUT
	replFile "$1" KEYBOARD_LAYOUT_VARIANT
	replFile "$1" SETUP_LANGUAGE
	replFile "$1" SETUP_LOCALE
	replFile "$1" VENDOR
	replFile "$1" VENDOR_LC
	replFile "$1" UBUNTU_ARCH
	replFile "$1" UBUNTU_VERSION
	replFile "$1" UBUNTU_SUBREL
	replFile "$1" COUNTRY
	replFile "$1" TIMEZONE
	replFile "$1" NTP_SERVER
	replFile "$1" NTP_ENABLED
	replFile "$1" NET_DEF_IP
	replFile "$1" NET_DEF_GW
	replFile "$1" NET_DEF_MASK
	replFile "$1" NET_DEF_DNS
	replFile "$1" NET_DEF_HOST
	replFile "$1" NET_DEF_DOMAIN
	replFile "$1" INSTALL_TASKSEL
	replFile "$1" INSTALL_PACKAGES
	replFile "$1" USER_NAME
	replFile "$1" USER_PASSWORD
	replFile "$1" USER_PASSWORD_ENC
}

ISODOWN=${ISODOWN:-$(readlink -f $(dirname $0)/isodown)}
TMPBASE="/tmp/isobuild.$$"
[ -n "$DEBUG" ] && TMPBASE="/tmp/isobuild"
CDMOUNT="${TMPBASE}/mount"
CDDIR="${TMPBASE}/cddir"
OVERLAY="${TMPBASE}/overlay"

DATE=$(date --iso-8601)
DATE_SHORT=$(date +%Y%m%d)
VOLUME="${VENDOR} Ubuntu ${UBUNTU_VERSION}${UBUNTU_SUBREL} ${DATE}"

if [ ${#VOLUME} -gt 32 ]; then
	echo "Volume length too long for '${VOLUME}'"
	VOLUME="${VENDOR} Ubnt ${UBUNTU_VERSION}${UBUNTU_SUBREL} ${DATE_SHORT}"
	if [ ${#VOLUME} -gt 32 ]; then
		echo "Volume '$VOLUME' also not short enough, trimming vendor name..."
		BVOLUME=" Ubnt ${UBUNTU_VERSION}${UBUNTU_SUBREL} ${DATE_SHORT}"
		MLEN=$[32 - ${#BVOLUME}]
		VOLUME="${VENDOR::${MLEN}}${BVOLUME}"
	fi
	echo "New volume name: '${VOLUME}'"
fi

#RAMDISKMAX=1024

ISOURL="http://releases.ubuntu.com/${UBUNTU_VERSION}/ubuntu-${UBUNTU_VERSION}${UBUNTU_SUBREL}-server-${UBUNTU_ARCH}.iso"
ISOFILE="${ISODOWN}/$(echo $ISOURL|sed -e 's#.*/\(.*\)$#\1#')"
OUTIMAGE="$(echo $ISOURL|sed -e 's#.*/\(.*\)\.iso$#\1#')-${VENDOR_LC}-${DATE}.iso"

echo
echo "Generating $OUTIMAGE from $(basename ${ISOFILE}) for Ubuntu ${UBUNTU_VERSION}${UBUNTU_SUBREL}"
echo

cleanup() {
	[ -n "$DEBUG" ] && {
		echo "Debug enabled - skipping cleanup"
		return
	}
	echo "Cleaning up..."
	sudo umount ${CDDIR} > /dev/null 2>&1 || true
	sudo umount $CDMOUNT >/dev/null 2>&1 || true
	[ -d "$TMPBASE" ] && sudo rm -rf ${TMPBASE} || true
}

abort() {
	echo "ERROR: $*" >&2
	cleanup
	exit 1
}

handle_error() {
	echo
	echo "FAILED: line $1, exit code $2"
	cleanup
	exit 1
}

createdir() {
	[ -d "$1" ] && return
	mkdir -p $1 || abort "Could not create ${ISODOWN} directory"
}

INST_PKGS=
! dpkg -l genisoimage >/dev/null 2>&1 && INST_PKGS="${INST_PKGS} genisoimage"
! dpkg -l aufs-tools >/dev/null 2>&1 && INST_PKGS="${INST_PKGS} aufs-tools"
! dpkg -l linux-image-extra-$(uname -r) >/dev/null 2>&1 && INST_PKGS="${INST_PKGS} linux-image-extra-$(uname -r)"
! dpkg -l rsync >/dev/null 2>&1 && INST_PKGS="${INST_PKGS} rsync"

if [ ! -z "$INST_PKGS" ]; then
	echo "- Installing required packages: $INST_PKGS"
	sudo apt-get install -y $INST_PKGS || abort "Could not install $INST_PKGS packages"
	sudo modprobe aufs
fi

createdir "${ISODOWN}"
createdir "${CDMOUNT}"
createdir "${CDDIR}"
createdir "${OVERLAY}"

[ -b /dev/loop0 ] || abort "No loop device available, are we running in a container without privileged mode?"
if [ ! -f "$ISOFILE" ]; then
	echo "- ISO file ${ISOFILE} missing, downloading from ${ISOURL}"
	wget -O ${ISOFILE} ${ISOURL} || { rm ${ISOFILE} ; abort "Could not download Ubuntu ISO"; }
fi

# Trap every error and exit on any error
trap 'handle_error $LINENO $?' ERR 
set -e
# From now on, any error will result in a cleanup/unmount of everything

if [ -n "$(mount | grep "${CDDIR}")" ]; then
	echo "- ${CDDIR} still mounted, unmounting..."
	sudo umount ${CDDIR} >/dev/null 2>&1
fi
if [ -n "$(mount | grep "${CDMOUNT}")" ]; then
	echo "- ${CDMOUNT} still mounted, unmounting..."
	sudo umount ${CDMOUNT} >/dev/null 2>&1
fi

echo "- Mounting CDROM $ISOFILE  on '$CDMOUNT' ..."

sudo mount -o loop $ISOFILE $CDMOUNT >/dev/null 2>&1

DO_RSYNC=
# ${CDDIR} not mounted yet
# Attempt to mount with overlay/aufs:
echo "- Clear overlay directory"
sudo rm -rf ${OVERLAY}/*
echo "- Attempt to mount CD image with AUFS overlay"
sudo mount -t aufs -o br=${OVERLAY}:$CDMOUNT none ${CDDIR} || {
	# Failed, attempt to mount on ramdisk
	echo "- AUFS mount failed, attempting ramdisk"
	ISOSIZE=$(du -BM ${ISOFILE} | sed -e 's/^\([0-9]*\)*M.*/\1/')
	if [ -z "$RAMDISKMAX" ]; then
		echo "- Detecting maximum ramdisk size..."
		FREEMEM=$(free -tm | tail -n1 | awk '{print $4}')
		# reserve 150mb for various tools
		RAMDISKMAX=$[ ${FREEMEM} - 150 ]
		echo " - Autodetected maximu ramdisk size to $RAMDISKMAX"
	fi
	RAMDISK=$[ ${ISOSIZE} + 50 ]
	if [ "$RAMDISK" -lt "$RAMDISKMAX" ]; then
		echo "- Mounting ${CDDIR} with tmpfs (${RAMDISK}M RAM disk)"
		sudo mount -t tmpfs -o size="${RAMDISK}m" tmpfs ${CDDIR} >/dev/null 2>&1 || true
	else
		echo "- Maximum ramdisk size (${RAMDISKMAX}M) too small, need ${RAMDISK}M - skipping"
	fi
	DO_RSYNC=1
}

if [ -n "$DO_RSYNC" ]; then
	echo "- Require syncing ISO image on ${CDMOUNT} to ${CDDIR}..."
	sudo rsync -a -H --exclude=TRANS.TBL --del $CDMOUNT/ $CDDIR
fi

echo "- Preparing image..."
echo "  - Copying grub boot menu"
sudo cp src/grubmenu/txt.cfg $CDDIR/isolinux/txt.cfg
echo "  - updating variables in $CDDIR/isolinux/txt.cfg"
replVars $CDDIR/isolinux/txt.cfg

echo "  - Clean up unnecessary languages from boot menu"
ls ${CDDIR}/isolinux/*.hlp ${CDDIR}/isolinux/*.tr | grep -v "^en\." | sudo xargs rm

# Prevent language selection menu
echo "  - Patch /isolinux/bootlogo to always select language '${SETUP_LANGUAGE}' on boot"
OLDDIR=${PWD}
mkdir -p ${TMPBASE}/bootlogo
cd ${TMPBASE}/bootlogo
cat ${CDDIR}/isolinux/bootlogo | cpio --extract --make-directories --no-absolute-filenames 2>/dev/null
ls *.hlp *.tr | grep -v "^${SETUP_LANGUAGE}\." | sudo xargs rm
echo "${SETUP_LANGUAGE}" > langlist
echo "${SETUP_LANGUAGE}" > lang
find . 2>/dev/null| cpio -o > /tmp/bootlogo.new 2>/dev/null
sudo cp /tmp/bootlogo.new ${CDDIR}/isolinux/bootlogo
cd ${OLDDIR}

echo "  - Set boot timeout to ${BOOT_TIMEOUT} seconds"
sudo sed -i -e "s/timeout .*/timeout ${BOOT_TIMEOUT}0/" $CDDIR/isolinux/isolinux.cfg

# Preseed files
echo "  - copy preseed files from src/preseed/ to /preseed/"
sudo mkdir -p $CDDIR/preseed/
for F in src/preseed/*.seed; do
	echo "  - Copy preseed file $F to $CDDIR/preseed/"
	sudo cp $F $CDDIR/preseed/
	echo "  - updating variables in $F"
	replVars "$CDDIR/preseed/$(basename $F)"
done

# late_command scripts
echo "  - copy scripts from src/scripts/ to /scripts/ and set executable"
sudo mkdir -p $CDDIR/scripts
sudo cp -rp src/scripts/* $CDDIR/scripts/
sudo chmod a+x $CDDIR/scripts/*.sh

if [ -f "${CDDIR}/scripts/${VENDOR_LC}.sh" ]; then
	echo "  - Adding ${VENDOR_LC}.sh as preseed/late_command"
	echo "d-i preseed/late_command string /cdrom/scripts/${VENDOR_LC}.sh" | sudo tee -a $CDDIR/preseed/${VENDOR_LC}.seed > /dev/null
fi

echo "  - fix MD5 checksum file"
OLDDIR=$PWD
cd ${CDDIR}
sudo md5sum `find -follow -type f 2>/dev/null` | sudo tee md5sum.txt >/dev/null
cd ${OLDDIR}
echo "- Preparations done."
echo "- Building ISO image ${OUTIMAGE} from ${CDDIR} with Volume '${VOLUME::32}'..."
sudo mkisofs -quiet \
             -r -V "${VOLUME::32}" \
             -cache-inodes \
             -J -l -b isolinux/isolinux.bin \
             -c isolinux/boot.cat -no-emul-boot \
             -boot-load-size 4 -boot-info-table \
             -o $OUTIMAGE $CDDIR
echo "- Fixing ISO image permissions..."
sudo chown $USER:$(groups | awk '{print $1}') $OUTIMAGE

echo "- Cleaning up..."
cleanup
echo
echo "Done."
