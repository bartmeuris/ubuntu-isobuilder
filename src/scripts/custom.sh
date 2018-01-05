#!/bin/sh

export VENDOR=custom

# Add authorized_keys file to all user directories
$(dirname $0)/ssh_authorized_keys.sh || exit $?

exit 0
