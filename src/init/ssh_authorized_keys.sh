#!/bin/sh

[ -f "$(dirname $0)/env" ] && . "$(dirname $0)/env"

TARGET=
TGTPREFIX=

[ -d "/target" ] && TARGET="/target"
[ -n "${TARGET}" ] && TGTPREFIX="in-target"

if [ -z "${AUTHORIZED_KEYS_FILE}" ] || [ ! -f "${AUTHORIZED_KEYS_FILE}" ];  then
	[ -n "${TITLE_LC}" ] && AUTHORIZED_KEYS_FILE="$(dirname $0)/authorized_keys.${TITLE_LC}"

	if [ -z "${AUTHORIZED_KEYS_FILE}" ] || [ ! -f "${AUTHORIZED_KEYS_FILE}" ]; then
		AUTHORIZED_KEYS_FILE="$(dirname $0)/authorized_keys"
	fi
fi
if [ ! -f "${AUTHORIZED_KEYS_FILE}" ]; then
	echo "No authorized keys file found"
	exit 0
fi

for U in ${TARGET}/root ${TARGET}/home/*; do
	[ ! -d "${U}" ] && continue
	CUSER=$(echo ${U}|sed -e 's#.*/\(.*\)$#\1#')
	UDIR=$U
	[ -n "${TARGET}" ] && UDIR=$(echo ${U}|sed -e "s@^${TARGET}\(/.*\)@\1@")
	echo "User ${CUSER}: Adding ssh authorized_keys file from ${AUTHORIZED_KEYS_FILE}"
	# Set up SSH keys
	mkdir -p ${U}/.ssh/
	cp ${AUTHORIZED_KEYS_FILE} $U/.ssh/authorized_keys
	chmod 700 ${U}/.ssh
	chmod 600 ${U}/.ssh/authorized_keys
	# Change the ownership of all files to the user:group
	for F in .ssh .ssh/authorized_keys; do
		${TGTPREFIX} /bin/chown ${CUSER}:${CUSER} ${UDIR}/${F}
	done
done
exit 0
