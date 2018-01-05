#!/bin/sh

TARGET=
TGTPREFIX=
[ -d "/target" ] && TARGET="/target"
[ -n "$TARGET" ] && TGTPREFIX="in-target"

if [ -z "$AUTHORIZED_KEYS_FILE" ] || [ ! -f "${AUTHORIZED_KEYS_FILE}" ];  then
	[ -n "$VENDOR" ] && AUTHORIZED_KEYS_FILE="$(dirname $0)/authorized_keys.${VENDOR}"

	if [ -z "${AUTHORIZED_KEYS_FILE}" ] || [ ! -f "${AUTHORIZED_KEYS_FILE}" ]; then
		AUTHORIZED_KEYS_FILE="$(dirname $0)/authorized_keys"
	fi
fi
if [ ! -f "$AUTHORIZED_KEYS_FILE" ]; then
	echo "No authorized keys file found"
	exit 0
fi

for U in $TARGET/root $TARGET/home/*; do
	[ ! -d "$U" ] && continue
	CUSER=$(echo $U|sed -e 's#.*/\(.*\)$#\1#')
	UDIR=$U
	[ -n "$TARGET" ] && UDIR=$(echo $U|sed -e "s#^$TARGET\(/.*\)#\1#")
	echo "User $CUSER: Adding ssh authorized_keys file from $AUTHORIZED_KEYS_FILE"
	# Set up SSH keys
	mkdir $U/.ssh
	cp $(dirname $0)/authorized_keys $U/.ssh/
	chmod 700 $U/.ssh
	chmod 600 $U/.ssh/authorized_keys
	# Change the ownership of all files to the user:group
	for F in .ssh .ssh/authorized_keys; do
		$TGTPREFIX /bin/chown $CUSER:$CUSER $UDIR/$F
	done
done
exit 0
