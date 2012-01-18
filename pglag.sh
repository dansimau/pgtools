#!/bin/bash
#
# Show replication lag for one or more postgresql slaves in streaming replication.
#
# dsimmons@squiz.co.uk
# 2012-01-09
#

psql="which psql"
psql_extra_opts=""
export PGCONNECT_TIMEOUT=5

#
# Converts specified xlog number to byte location
#
_xlog_to_bytes()
{
	logid="${1%%/*}"
	offset="${1##*/}"
	echo $((0xFFFFFF * 0x$logid + 0x$offset))
}

_get_xlog_loc()
{
	local pgfunc

	if _in_recovery $1; then
		pgfunc="pg_last_xlog_replay_location"
	else
		pgfunc="pg_current_xlog_location"
	fi

	xlog_loc=$(psql -h $1 -Atc "SELECT $pgfunc();")
	if [ $? -gt 0 ]; then
		echo "ERROR: Failed getting xlog location from node $1" >&2
		return 1
	fi
	echo $xlog_loc
}

_in_recovery()
{
	recovery=$(psql -h $1 -Atc "SELECT pg_is_in_recovery();")
	# If pg_is_in_recovery() returns false then we're a master
	if [ "$recovery" == "f" ]; then
		return 1
	else
		# Slave. or unable to detect
		return 0
	fi

}

if [ $# -lt 1 ]; then
	echo "Usage: $0 [--master <master host>] <slave host [...]>" >&2
	exit 99
fi

if [ "$1" == "--master" ]; then
	shift
	master=$1
	if _in_recovery $master; then
		echo "WARNING: Master specified ($master) is not a master:" >&2
		master=""
	fi
else
	# Try to automatically detect the master
	for s in "$@"; do
		if ! _in_recovery $s; then
			if [ -n "$master" ]; then
				echo "WARNING: There is more than one master. To get lag calculcation, specify a master with the --master switch" >&2
				master=""
				break
			fi
			master=$s
		fi
	done
fi

# Get master xlog location (if there is a master)
if [ -n "$master" ]; then
	master_xlog_loc=$(_get_xlog_loc $master) || exit $?
fi

echo
echo "Replication status ($(date +%c))"
echo "----------------------------------------------------"

for s in "$@"; do

	xlog_loc=""
	bytes_lag=""
	role=""

	# Get xlog location
	xlog_loc=$(_get_xlog_loc $s) || exit $?

	if _in_recovery $s; then
		role="Slave  "
	else
		role="Master "
	fi

	echo -n "$role $s: $xlog_loc"

	# Calculate number of bytes behind
	if [ -n "$master" ] && [ "$s" != "$master" ]; then
		bytes_lag=$(($(_xlog_to_bytes $master_xlog_loc) - $(_xlog_to_bytes $xlog_loc)))
		echo -n " ($bytes_lag bytes lag)"
	fi

	echo 
done

echo
