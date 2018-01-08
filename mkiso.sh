#!/bin/bash

function cleanup() {
	[ -n "$DEBUG" ] && {
		echo "Debug enabled - skipping cleanup"
		return
	}
	echo "Cleaning up..."
	sudo umount ${CDDIR} > /dev/null 2>&1 || true
	sudo umount $CDMOUNT >/dev/null 2>&1 || true
	[ -d "$TMPBASE" ] && sudo rm -rf ${TMPBASE} || true
}

function abort() {
	echo "ERROR: $*" >&2
	cleanup
	exit 1
}

function handle_error() {
	echo
	echo "FAILED: line $1, exit code $2"
	cleanup
	exit 1
}

function createdir() {
	[ -d "$1" ] && return
	mkdir -p $1 || abort "Could not create ${ISODOWN} directory"
}

# Replace a %VARNAME% with the ${VARNAME} value in a file
function replFile {
	# Make sure escaping is done correctly
	ESC_VAL=$(eval printf "%q" \"\$${2}\")
	
	# Catch empty escaped strings
	[ "$ESC_VAL" == "''" ] && ESC_VAL=
	
	#echo "---- Escaped value for '$2' = '$ESC_VAL'"
	sudo sed -i -e "s@%$2%@$ESC_VAL@g" "$1"
}

# Replace all variables in a specified file
function replVars {
	[ -f "$1" ] || {
		echo "### WARN: File $1 not found"
		return
	}
	VARS=(
		BOOT_TIMEOUT
		KEYBOARD_LAYOUT_CODE
		KEYBOARD_LAYOUT
		KEYBOARD_LAYOUT_VARIANT
		SETUP_LANGUAGE
		SETUP_LOCALE
		TITLE
		TITLE_LC
		UBUNTU_ARCH
		UBUNTU_VERSION
		UBUNTU_SUBREL
		COUNTRY
		TIMEZONE
		NTP_SERVER
		NTP_ENABLED
		NET_DEF_IP
		NET_DEF_GW
		NET_DEF_MASK
		NET_DEF_DNS
		NET_DEF_HOST
		NET_DEF_DOMAIN
		INSTALL_TASKSEL
		INSTALL_PACKAGES
		USER_NAME
		USER_PASSWORD
		USER_PASSWORD_ENC
	)
	for V in ${VARS[@]}; do
		replFile "$1" $V
	done
}

# Ensure all provided packages are installed. Test for the package's existence by checking if a file/directory exist.
# dpkg -l isn't reliable, it faile on the 'whois' package
function instPkgs {
	INST_PKGS=
	for P in $*; do
		[ ! -e ${P%%:*} ] && INST_PKGS="${INST_PKGS} ${P#*:}"
	done
	if [ ! -z "$INST_PKGS" ]; then
		echo "- Installing required packages: $INST_PKGS"
		sudo apt-get install -y $INST_PKGS || abort "Could not install $INST_PKGS packages"
		# Make sure we load the aufs module after installing some packages
		sudo modprobe aufs
	fi
}

echo "Loading settings..."
DEBUG=
RAMDISKMAX=
DATE=$(date --iso-8601)
DATE_SHORT=$(date +%Y%m%d)

CONFIGFILE=
CONFIGDIR=
BASEDIR=$(readlink -f "$(dirname $0)")
if [ ! -z "${1}" ] && [ -d "${1}" ]; then
	[ -z "${CONFIGFILE}" ] && [ -f "${1}/$(basename ${1}).cfg" ] && CONFIGFILE="${1}/$(basename "${1}").cfg"
	[ -z "${CONFIGFILE}" ] && [ -f "${1}/iso.cfg" ] && CONFIGFILE="${1}/iso.cfg"
	CONFIGDIR="${1}"
elif [ ! -z "${1}" ] && [ -f "${1}" ]; then
	CONFIGFILE="${1}"
	CONFIGDIR=$(dirname "${CONFIGFILE}")
fi


[ -z "${CONFIGFILE}" ] && echo "WARNING: No configuration found or specified"
if [ -z "${CONFIGDIR}" ]; then
	echo "WARNING: No configuration directory found"
	CONFIGDIR=${BASEDIR}
fi
CONFIGDIR=$(readlink -f "${CONFIGDIR}")

# Include config file

if [ -n "${CONFIGFILE}" ]; then
	CONFIGFILE=$(readlink -f "${CONFIGFILE}")
	echo "- Loading config file ${CONFIGFILE}"
	. "${CONFIGFILE}"
fi


# Ensure all dependencies are installed
instPkgs \
	/sbin/mount.aufs:aufs-tools \
	/usr/bin/mkisofs:genisoimage \
	/usr/share/doc/linux-image-extra-$(uname -r):linux-image-extra-$(uname -r) \
	/usr/bin/rsync:rsync \
	/usr/bin/pwgen:pwgen \
	/usr/bin/mkpasswd:whois


# Settings that can be overridden in the default.cfg or file specified on the cli
## Determine title
TITLE=${TITLE:-"Custom"}
[ -z "${TITLE_LC}" ] && TITLE_LC=$(echo "$TITLE"|tr A-Z a-z|sed -e "s/ /-/g")
TITLE_LC=$(echo "$TITLE_LC"|tr A-Z a-z|sed -e "s/ /-/g")

## Ubuntu version and architecture
UBUNTU_ARCH=${UBUNTU_ARCH:-"amd64"}
UBUNTU_VERSION=${UBUNTU_VERSION:-"16.04"}
UBUNTU_SUBREL=${UBUNTU_SUBREL:-".3"}
## Source ISO settings
### Where the source ISO will be searched for/downloaded to
ISODOWN=${ISODOWN:-$(readlink -f $(dirname $0)/isodown)}
### ISO source URL, default = ubuntu, can be overridden, but you're on your own
ISOURL="${ISOURL:-"http://releases.ubuntu.com/${UBUNTU_VERSION}/ubuntu-${UBUNTU_VERSION}${UBUNTU_SUBREL}-server-${UBUNTU_ARCH}.iso"}"
ISOFILE="${ISODOWN}/$(echo "${ISOURL}"|sed -e 's#.*/\(.*\)$#\1#')"
OUTIMAGE="$(echo "${ISOURL}"|sed -e 's#.*/\(.*\)\.iso$#\1#')-${TITLE_LC}-${DATE}.iso"

## Keyboard layout, language, locale...
KEYBOARD_LAYOUT_CODE=${KEYBOARD_LAYOUT_CODE:-"us"}
KEYBOARD_LAYOUT=${KEYBOARD_LAYOUT:-"English (US)"}
KEYBOARD_LAYOUT_VARIANT=${KEYBOARD_LAYOUT_VARIANT:-"English (US)"}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-"10"}
SETUP_LANGUAGE=${SETUP_LANGUAGE:-"en"}
SETUP_LOCALE=${SETUP_LOCALE:-"en_US.UTF-8"}
COUNTRY=${COUNTRY:-"BE"}
TIMEZONE=${TIMEZONE:-"Europe/Brussels"}

## NTP configuration
NTP_SERVER=${NTP_SERVER:-"$(echo $COUNTRY|tr A-Z a-z).pool.ntp.org"}
NTP_ENABLED=${NTP_ENABLED:-"true"}

## Network configuration
NET_DEF_IP=${NET_DEF_IP:-""}
NET_DEF_GW=${NET_DEF_GW:-""}
NET_DEF_MASK=${NET_DEF_MASK:-"255.255.255.0"}
NET_DEF_DNS=${NET_DEF_DNS:-"8.8.8.8 8.8.4.4"}
NET_DEF_HOST=${NET_DEF_HOST:-"host"}
NET_DEF_DOMAIN=${NET_DEF_DOMAIN:-"default.domain"}

## Package selection
INSTALL_TASKSEL=${INSTALL_TASKSEL:-"standard, ssh-server"}
INSTALL_PACKAGES=${INSTALL_PACKAGES:-"openssh-server openssh-client python-minimal vim tree htop wget curl ntp netcat pv socat"}

## Username/password config
USER_NAME=${USER_NAME:-"ubuntu"}
HASH_ALGO=${HASH_ALGO:-"sha-512"}

### Set the default password
if [ -z "$USER_PASSWORD_ENC" ] && [ -z "${USER_PASSWORD}" ]; then
	USER_PASSWORD="ubuntu"
	echo "- !! WARNING!!! Setting default password for user '${USER_NAME}'."
fi
### If no hashed password was provided, hash the password now.
if [ -z "$USER_PASSWORD_ENC" ] && [ -n "${USER_PASSWORD}" ]; then
	echo "- Hashing insecure password with ${HASH_ALGO} for user '${USER_NAME}'"
	USER_PASSWORD_ENC=$(echo -e "${USER_PASSWORD}" | /usr/bin/mkpasswd --stdin -m ${HASH_ALGO} -S $(/usr/bin/pwgen -ns 16 1))
	echo "- Hashed password: '${USER_PASSWORD_ENC}'"
fi

# Internal/temporary directory locations
TMPBASE="/tmp/isobuild.$$"
[ -n "$DEBUG" ] && TMPBASE="/tmp/isobuild"
CDMOUNT="${TMPBASE}/mount"
CDDIR="${TMPBASE}/cddir"
OVERLAY="${TMPBASE}/overlay"

# Ensure the Volume length isn't longer than 32 characters
VOLUME="${TITLE} Ubuntu ${UBUNTU_VERSION}${UBUNTU_SUBREL} ${DATE}"
if [ ${#VOLUME} -gt 32 ]; then
	echo "Volume length too long for '${VOLUME}'"
	VOLUME="${TITLE} Ubnt ${UBUNTU_VERSION}${UBUNTU_SUBREL} ${DATE_SHORT}"
	if [ ${#VOLUME} -gt 32 ]; then
		echo "Volume '$VOLUME' also not short enough, trimming title name..."
		BVOLUME=" Ubnt ${UBUNTU_VERSION}${UBUNTU_SUBREL} ${DATE_SHORT}"
		MLEN=$[32 - ${#BVOLUME}]
		VOLUME="${TITLE::${MLEN}}${BVOLUME}"
	fi
	echo "New volume name: '${VOLUME}'"
fi

echo
echo "Generating $OUTIMAGE from $(basename ${ISOFILE}) for Ubuntu ${UBUNTU_VERSION}${UBUNTU_SUBREL}"
echo

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

# Make sure everything is unmounted before continuing
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
	sudo /usr/bin/rsync -a -H --exclude=TRANS.TBL --del $CDMOUNT/ $CDDIR
fi

function copyFileTo() {
	DEST=$1
	shift 1
	for F in $*; do
		SRC=
		if [ -f "${CONFIGDIR}/$F" ]; then
			SRC="${CONFIGDIR}/$F"
		elif [ -f "${BASEDIR}/src/$F" ]; then
			SRC="${BASEDIR}/src/$F"
		fi
		[ -z "${SRC}" ] && return 1
		sudo cp ${SRC} ${CDDIR}/${DEST}
	done
}

# Now start customizing the image in the ${CDIR} directory
echo "- Preparing image..."
echo "  - Copying grub boot menu"
copyFileTo /isolinux/txt.cfg txt.cfg
echo "  - updating variables in $CDDIR/isolinux/txt.cfg"
replVars $CDDIR/isolinux/txt.cfg

echo "  - Clean up unnecessary languages from boot menu"
find ${CDDIR}/isolinux/ -name "*.hlp" -or -name "*.tr" | grep -v "^${SETUP_LANGUAGE}\." | sudo xargs rm

# Prevent language selection menu
echo "  - Patch /isolinux/bootlogo to always select language '${SETUP_LANGUAGE}' on boot"
OLDDIR=${PWD}
mkdir -p ${TMPBASE}/bootlogo
cd ${TMPBASE}/bootlogo
cat ${CDDIR}/isolinux/bootlogo | cpio --extract --make-directories --no-absolute-filenames 2>/dev/null
find ${TMPBASE}/bootlogo -name "*.hlp" -or -name "*.tr" | grep -v "^${SETUP_LANGUAGE}\." | sudo xargs rm
echo "${SETUP_LANGUAGE}" > ${TMPBASE}/bootlogo/langlist
echo "${SETUP_LANGUAGE}" > ${TMPBASE}/bootlogo/lang
find . 2>/dev/null| cpio -o > /tmp/bootlogo.new 2>/dev/null
sudo cp /tmp/bootlogo.new ${CDDIR}/isolinux/bootlogo
cd ${OLDDIR}

echo "  - Set boot timeout to ${BOOT_TIMEOUT} seconds"
sudo sed -i -e "s/timeout .*/timeout ${BOOT_TIMEOUT}0/" $CDDIR/isolinux/isolinux.cfg

# Preseed files
echo "  - Copy preseed files from src/preseed/ to /preseed/"
sudo mkdir -p $CDDIR/preseed/
for F in ${BASEDIR}/src/*.seed ${CONFIGDIR}/*.seed; do
	[ ! -f "$F" ] && continue
	echo "   - Copy preseed file $F to $CDDIR/preseed/"
	sudo cp ${F} ${CDDIR}/preseed/
	echo "   - Updating variables in ${CDDIR}/preseed/$(basename $F)"
	replVars "${CDDIR}/preseed/$(basename $F)"
done

# late_command scripts
echo "  - Copy init files from src/init/ to /scripts/"
sudo mkdir -p $CDDIR/scripts
sudo cp -rp ${BASEDIR}/src/init/* $CDDIR/scripts/
echo "  - Copy init files from ${CONFIGDIR}/init/ to /scripts/"
sudo cp -rp ${CONFIGDIR}/init/* $CDDIR/scripts/ 2>/dev/null || true
echo "  - Set all scripts in /scripts/ to be executable"
sudo chmod a+x $CDDIR/scripts/*.sh

INITSCRIPT=
[ -z "${INITSCRIPT}" ] && [ -f "${CDDIR}/scripts/${TITLE_LC}.sh" ] && INITSCRIPT="${TITLE_LC}.sh"
[ -z "${INITSCRIPT}" ] && [ -f "${CDDIR}/scripts/custom.sh" ] && INITSCRIPT="custom.sh"

if [ -n "${INITSCRIPT}" ]; then
	echo "  - Adding ${INITSCRIPT} as preseed/late_command"
	echo "d-i preseed/late_command string /cdrom/scripts/${INITSCRIPT}" | sudo tee -a ${CDDIR}/preseed/${TITLE_LC}.seed > /dev/null
fi

echo "  - fix MD5 checksum file"
OLDDIR=$PWD
cd ${CDDIR}
sudo md5sum `find -follow -type f 2>/dev/null` | sudo tee md5sum.txt >/dev/null
cd ${OLDDIR}
echo "- Preparations done."

echo "- Building ISO image ${OUTIMAGE} from ${CDDIR} with Volume '${VOLUME::32}'..."
sudo /usr/bin/mkisofs -quiet \
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
