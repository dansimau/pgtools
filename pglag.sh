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
	pgfunc="pg_last_xlog_replay_location"

	if [ "$1" == "--master" ]; then
		pgfunc="pg_current_xlog_location"
		shift
	fi

	[ -n "$1" ] && psql_extra_opts="$psql_extra_opts -h $1"

	xlog_loc=$(psql $psql_extra_opts -Atc "SELECT $pgfunc();")
	if [ $? -gt 0 ]; then
		echo "ERROR: Failed getting xlog location from node $1" >&2
		return 1
	fi
	echo $xlog_loc
}

if [ $# -lt 1 ]; then
	echo "Usage: $0 [--master <master host>] <slave host [...]>" >&2
	exit 99
fi

if [ "$1" == "--master" ]; then
	shift
	master=$1
	shift
else
	master=""
fi

# Get master xlog location
master_xlog_loc=$(_get_xlog_loc --master $master) || exit $?

echo
echo "Replication status ($(date +%c))"
echo "-------------------------------------------------"
echo "Master  $master: $master_xlog_loc"

for slave in "$@"; do

	slave_xlog_loc=""
	slave_bytes_lag=""

	# Get slave xlog location
	slave_xlog_loc=$(_get_xlog_loc $slave) || exit $?

	# Calculate number of bytes behind
	slave_bytes_lag=$(($(_xlog_to_bytes $master_xlog_loc) - $(_xlog_to_bytes $slave_xlog_loc)))

	# Print
	echo "Slave   $slave: $slave_xlog_loc ($slave_bytes_lag bytes lag)"

done

echo
