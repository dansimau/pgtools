#/bin/sh -x
#

if [ -z "$2" ]; then
	echo "Usage: $0 <master hostname> <pgdata dir>" >&2
	echo "  Eg.: $0 10.10.201.56 /var/lib/pgsql/9.1/data" >&2
	exit 99
fi

export PGHOST=$1
export PGDATA=$2

# Stop postgres
echo "$0: Shutting down postgresql..."
su -c "pg_ctl -D $PGDATA stop -m fast -w -t5" - postgres

# Start backup
echo "$0: Initiating backup mode on master..."
psql -q -c "SELECT pg_start_backup('Streaming Replication', true)" >/dev/null || exit

# Rsync the files
echo "$0: Copying data files from master..."
rsync -C -a -c --delete --exclude postgresql.conf --exclude postmaster.pid \
--exclude postmaster.opts --exclude pg_log \
--exclude recovery.conf --exclude recovery.done \
--exclude pg_xlog \
$PGHOST:$PGDATA/ $PGDATA/ || exit

mkdir -p $PGDATA/pg_xlog
chmod 700 $PGDATA/pg_xlog
rm -f $PGDATA/recovery.done

# Create recovery.conf
cat <<EOF >$PGDATA/recovery.conf
standby_mode     = 'on'
primary_conninfo = 'host=$PGHOST application_name=$(hostname)'
EOF
chown postgres:postgres $PGDATA/recovery.conf

# Stop backup
echo "$0: Stopping backup mode..."
psql -c "SELECT pg_stop_backup()"

# Start postgres
echo "$0: Starting postgresql..."
su -c "pg_ctl -D $PGDATA start -w -t20" - postgres
