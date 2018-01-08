#!/bin/sh
# This script will automatically be called after installation
export TITLE=example

# Call default script to add authorized_keys file to all user directories
$(dirname $0)/ssh_authorized_keys.sh || exit $?

exit 0
