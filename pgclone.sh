#/bin/sh -x
#
# Restores a slave node from the specified master and sets up recovery.conf
# with streaming replication.
#
# dsimmons@squiz.co.uk
# 2012-01-24
#

if [ -z "$1" -o "$1" == "--help" ]; then
	echo
	echo "Usage: $0 <master host> [options]" >&2
	echo
	echo "Options:"
	echo "  --local-pgdata=PATH   Path to local data dir. Defaults to \$PGDATA" >&2
	echo "  --remote-pgdata=PATH  Path to remote data dir. Defaults to remote \$PGDATA" >&2
	echo "  --remote-pguser=USER  Username to use for psql on remote. Sets remote \$PGUSER" >&2
	echo "  --remote-pghost=HOST  Hostname to use for psql on remote. Sets remote \$PGHOST" >&2
	echo "  --remote-pgport=PORT  Port to use for psql on remote. Sets remote \$PGPORT" >&2
	echo "  --force | -f          Carry out operation without prompting" >&2
	echo
	exit 99
fi


#
# Converts string to uppercase
#
_to_upper()
{
	echo "$@" | tr '[a-z]' '[A-Z]'
}

#
# Runs command on the remote server (via SSH)
#
_ssh_cmd()
{
	local host=$1
	shift
	local envdec

	# Build a list of env var declarations for the remote side
	for envvar in $(env |grep '^REMOTE_'); do
		envdec="${envdec}export ${envvar#REMOTE_}"$'\n'
	done

	# Cat the commands to SSH
	cat <<EOF | ssh -T $host
$envdec
$@
EOF

	return $?
}

# Parse options
for opt in "$@"; do

	switch=${opt%%=*}
	value=${opt#*=}
	[ "$switch" == "$value" ] && value=""

	case "$switch" in
		--local*)
			# Set arbitrary local env var
			varname=$(_to_upper ${switch#--local-})
			eval export $varname=$value
			;;
		--remote*)
			# Set arbitrary REMOTE_ var which will be used later
			varname=$(_to_upper ${switch#--remote-})
			eval export REMOTE_$varname=$value
			;;
		--force|-f)
			force=yes
			;;
		*)
			if [ -z "$master" ]; then
				master=$switch
			else
				echo "WARNING: Unrecognised option: $switch" >&2
			fi
	esac
done

if [ -z "$master" ]; then
	echo "ERROR: Master not specified. See $0 --help" >&2
	exit 1
fi

#
# Run a lot of checks here to be safe...
#

# Check write access to local PGDATA
if ! [ -w "$PGDATA" ]; then
	echo "ERROR: No write access to local data dir: $PGDATA" >&2
	echo "HINT: Ensure you are running $0 as the postgres user and that pgdata is set." >&2
	exit 2
fi

# Check we can control postgres with pg_ctl
if ! pg_ctl status 2>&1 |grep -Eq '(server is running|no server running)'; then
	echo "ERROR: Unable to get postgres running status with pg_ctl" >&2
	echo "HINT: Ensure pg_ctl is in path and can be used to control posgres." >&2
	exit 2
fi

# Ensure rsync is installed
if ! which rsync >/dev/null; then
	echo "ERROR: Unable to find rsync" >&2
	echo "HINT: Check rsync is installed and is in PATH" >&2
	exit 2
fi

# Check SSH access to remote
if ! _ssh_cmd $master; then
	echo "ERROR: Unable to SSH to $master" >&2
	echo "HINT: Set up SSH keys to allow automatic connection between the hosts." >&2
	exit 2
fi

# Check psql works on remote
if ! _ssh_cmd $master "psql -c '\l'" >/dev/null; then
	echo "ERROR: Unable to execute remote psql" >&2
	echo "HINT: Examine error from above and ensure psql can be executed on the remote side." >&2
	exit 2
fi

# Check PGDATA on remote
if ! _ssh_cmd $master "[ -d \$PGDATA ]"; then
	echo "ERROR: Cannot access \$PGDATA remotely" >&2
	echo "HINT: PGDATA must be set on the master and contain the path to the data files" >&2
	exit 2
fi

# Check rsync is installed on remote
if ! _ssh_cmd $master "which rsync" >/dev/null; then
	echo "ERROR: Unable to find rsync on remote" >&2
	echo "HINT: Check rsync is installed on the remote and is in the PATH" >&2
	exit 2
fi

# We need to always set REMOTE_PGDATA, because rsync needs it to be provided on
# the command line locally. Therefore, if it's not already set, we need to
# to retrieve it from the remote side.
#
# Here, we retrieve all remote variables and re-set them so they'll be
# displayed in the summary below.
#
for remotevar in $(_ssh_cmd $master "env |grep PG"); do
	eval export REMOTE_$remotevar
done

# Display summary if -f not set
if [ "$force" != "yes" ]; then
	echo
	echo "Ready to clone new standby:"
	echo
	printf "%-15s: %s\n" "Remote/master" "$master"
	printf "%-15s: %s\n" "Slave" "$(hostname) (this host)"
	echo
	printf "%-15s: %s\n" "Remote PGHOST" "$REMOTE_PGHOST"
	printf "%-15s: %s\n" "Remote PGPORT" "$REMOTE_PGPORT"
	printf "%-15s: %s\n" "Remote PGUSER" "$REMOTE_PGUSER"
	printf "%-15s: %s\n" "Remote PGDATA" "$REMOTE_PGDATA"
	echo
	printf "%-15s: %s\n" "Local PGHOST" "$PGHOST"
	printf "%-15s: %s\n" "Local PGPORT" "$PGPORT"
	printf "%-15s: %s\n" "Local PGUSER" "$PGUSER"
	printf "%-15s: %s\n" "Local PGDATA" "$PGDATA"
	echo
	echo -n "Continue? (y/N) "
	trap echo 0
	read input
	if  [ "$input" != "y" ] && [ "$input" != "Y" ]; then
		echo
		echo "Aborting at user request"
		exit
	fi
fi

#
# Override echo to include timestamp
#
echo()
{
	builtin echo "[$(date +%c)] $0: $@"
}

#
# Function to try and stop the remote backup if something fails
#
_stop_remote_backup()
{
	echo "Stopping backup mode on master..."
	if ! _ssh_cmd $master "psql -q -c \"SELECT pg_stop_backup();\"" >/dev/null; then
		echo "WARNING: Unable to stop backup." >&2
		echo "WARNING: Please manually execute pg_stop_backup() on the master" >&2
	fi
}

#
# OK here we go...
#

# Check if postgresql is running
if pg_ctl status 2>&1 |grep -q 'server is running'; then

	# Stop local postgres
	echo "Shutting down postgresql..."
	if ! pg_ctl stop -m immediate -s -w -t10; then
		echo "ERROR: Unable to stop postgres. Aborting." >&2
		exit 1
	fi
fi

echo "Postgresql stopped."

# Start backup
echo "Initiating backup mode on master..."
if ! _ssh_cmd $master "psql -q -c \"SELECT pg_start_backup('Streaming replication', true)\"">/dev/null; then
	echo "ERROR: Initiating backup on the master failed" >&2
	exit 1
fi

# Trap signals from now, to ensure the backup is stopped if there is a problem
trap _stop_remote_backup 0

# Rsync the files
echo "Rsyncing data files from master..."
rsync -P -C -rlp -c --delete \
--exclude postgresql.conf \
--exclude postmaster.pid \
--exclude postmaster.opts \
--exclude pg_log \
--exclude pg_xlog \
--exclude recovery.conf \
--exclude recovery.done \
$master:$REMOTE_PGDATA/ $PGDATA/

if [ $? -gt 0 ]; then
	echo "Rsync failed." >&2
	exit 1 # Will trigger _pg_stop_backup()
fi

mkdir -p $PGDATA/pg_xlog
chmod 700 $PGDATA/pg_xlog
rm -f $PGDATA/recovery.done

# Create recovery.conf
echo "Writing new recovery.conf..."
cat <<EOF >$PGDATA/recovery.conf
standby_mode     = 'on'
primary_conninfo = 'host=$master application_name=$(hostname)'
EOF
chown postgres:postgres $PGDATA/recovery.conf

# Stop backup
echo "$0: Stopping backup mode..."
_stop_remote_backup

# Remove trap from earlier
trap "" 0

# Start postgres
echo "Starting postgresql..."
if ! pg_ctl start -s -w -t10; then
	echo "WARNING: Unable to start postgresql (check log file)"
fi
