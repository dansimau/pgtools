## pgclone.sh

### Description

Clones a new standby from the specified postgresql master.

### Usage

	-bash-3.2$ /tmp/pgclone.sh 
	
	Usage: /tmp/pgclone.sh <remote/master host> [options]
	
	Options:
	  --local-pgdata=PATH   Path to local data dir. Defaults to $PGDATA
	  --remote-pgdata=PATH  Path to remote data dir. Defaults to remote $PGDATA
	  --remote-pguser=USER  Username to use for psql on remote. Sets remote $PGUSER
	  --remote-pghost=HOST  Hostname to use for psql on remote. Sets remote $PGHOST
	  --remote-pgport=PORT  Port to use for psql on remote. Sets remote $PGPORT
	  --force | -f          Carry out operation without prompting
	
	-bash-3.2$

### Example

	-bash-3.2$ pgclone.sh pg01
	
	Ready to clone new standby:
	
	Remote/master  : pg01
	Slave          : pg03 (this host)
	
	Remote PGHOST  : 
	Remote PGPORT  : 
	Remote PGUSER  : postgres
	Remote PGDATA  : /var/lib/pgsql/9.1/data
	
	Local PGHOST   : 
	Local PGPORT   : 
	Local PGUSER   : 
	Local PGDATA   : /var/lib/pgsql/9.1/data
	
	Continue? (y/N) y
	
	[Tue 24 Jan 2012 04:04:28 PM UTC] pgclone.sh: Shutting down postgresql...
	[Tue 24 Jan 2012 04:04:29 PM UTC] pgclone.sh: Postgresql stopped.
	[Tue 24 Jan 2012 04:04:29 PM UTC] pgclone.sh: Initiating backup mode on master...
	[Tue 24 Jan 2012 04:04:30 PM UTC] pgclone.sh: Copying data files from master...
	receiving incremental file list
	backup_label
			 191 100%  186.52kB/s    0:00:00 (xfer#1, to-check=999/1002)
	base/12699/pg_internal.init
		  106804 100%    4.85MB/s    0:00:00 (xfer#2, to-check=282/1002)
	deleting global/pgstat.stat
	global/pg_control
			8192 100%  133.33kB/s    0:00:00 (xfer#3, to-check=10/1002)
	global/pg_internal.init
		   12456 100%  199.41kB/s    0:00:00 (xfer#4, to-check=8/1002)
	pg_stat_tmp/pgstat.stat
			6783 100%  106.84kB/s    0:00:00 (xfer#5, to-check=1/1002)
	
	sent 1349 bytes  received 128886 bytes  260470.00 bytes/sec
	total size is 25662931  speedup is 197.05
	[Tue 24 Jan 2012 04:04:30 PM UTC] pgclone.sh: Writing new recovery.conf...
	[Tue 24 Jan 2012 04:04:30 PM UTC] pgclone.sh: Stopping backup mode...
	[Tue 24 Jan 2012 04:04:30 PM UTC] pgclone.sh: Stopping backup mode on master...
	[Tue 24 Jan 2012 04:04:31 PM UTC] pgclone.sh: Starting postgresql...
	
	-bash-3.2$ 

Use the `-f` switch to bypass summary and prompt. Note that the script does a significant amount of checking beforehand to ensure the clone will be successful (for example, checking that you have SSH access and that you can execute psql remotely):

	[root@pg03 ~]# /tmp/pgclone.sh pg01 --force
	ERROR: No write access to local data dir: 
	HINT: Ensure you are running /tmp/pgclone.sh as the postgres user and that pgdata is set.
	[root@pg03 ~]# 


## pglag.sh

### Description

Shows the replication lag of standby nodes in a postgresql cluster.

### Usage

	[sysadmin@DBLB001 ~]$ ./pglag.sh 
	Usage: ./pglag.sh [--master <master host>] <slave host [...]>
	[sysadmin@DBLB001 ~]$ 

### Example

Set env variables if needed:

	[sysadmin@DBLB001 ~]$ export PGUSER=postgres
	[sysadmin@DBLB001 ~]$ 

Then:

	[sysadmin@DBLB001 ~]$ ./pglag.sh --master DB001 DB002 DB003 DB004
	
	Replication status (Mon 09 Jan 2012 11:52:13 GMT)
	-------------------------------------------------
	Master  DB001: 0/A866CEC0
	Slave   DB002: 0/A866CEC0 (0 bytes lag)
	Slave   DB003: 0/A866CEC0 (0 bytes lag)
	Slave   DB004: 0/A866CEC0 (0 bytes lag)
	
	[sysadmin@DBLB001 ~]$ 

Omit `--master` option and the script will attempt to detect the master automatically.
