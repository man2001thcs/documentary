#!/usr/bin/env bash
set -Eeo pipefail
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		printf >&2 'error: both %s and %s are set (but are exclusive)\n' "$var" "$fileVar"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# used to create initial postgres directories and if run as root, ensure ownership to the "postgres" user
docker_create_db_directories() {
	local user; user="$(id -u)"

	mkdir -p "$PGDATA"
	# ignore failure since there are cases where we can't chmod (and PostgreSQL might fail later anyhow - it's picky about permissions of this directory)
	chmod 00700 "$PGDATA" || :

	# ignore failure since it will be fine when using the image provided directory; see also https://github.com/docker-library/postgres/pull/289
	mkdir -p /var/run/postgresql || :
	chmod 03775 /var/run/postgresql || :

	# Create the transaction log directory before initdb is run so the directory is owned by the correct user
	if [ -n "${POSTGRES_INITDB_WALDIR:-}" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		if [ "$user" = '0' ]; then
			find "$POSTGRES_INITDB_WALDIR" \! -user postgres -exec chown postgres '{}' +
		fi
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	# allow the container to be started with `--user`
	if [ "$user" = '0' ]; then
		find "$PGDATA" \! -user postgres -exec chown postgres '{}' +
		find /var/run/postgresql \! -user postgres -exec chown postgres '{}' +
	fi
}

# initialize empty PGDATA directory with new database via 'initdb'
# arguments to `initdb` can be passed via POSTGRES_INITDB_ARGS or as arguments to this function
# `initdb` automatically creates the "postgres", "template0", and "template1" dbnames
# this is also where the database user is created, specified by `POSTGRES_USER` env
docker_init_database_dir() {
	# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
	# see https://github.com/docker-library/postgres/pull/253, https://github.com/docker-library/postgres/issues/359, https://cwrap.org/nss_wrapper.html
	local uid; uid="$(id -u)"
	if ! getent passwd "$uid" &> /dev/null; then
		# see if we can find a suitable "libnss_wrapper.so" (https://salsa.debian.org/sssd-team/nss-wrapper/-/commit/b9925a653a54e24d09d9b498a2d913729f7abb15)
		local wrapper
		for wrapper in {/usr,}/lib{/*,}/libnss_wrapper.so; do
			if [ -s "$wrapper" ]; then
				NSS_WRAPPER_PASSWD="$(mktemp)"
				NSS_WRAPPER_GROUP="$(mktemp)"
				export LD_PRELOAD="$wrapper" NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
				local gid; gid="$(id -g)"
				printf 'postgres:x:%s:%s:PostgreSQL:%s:/bin/false\n' "$uid" "$gid" "$PGDATA" > "$NSS_WRAPPER_PASSWD"
				printf 'postgres:x:%s:\n' "$gid" > "$NSS_WRAPPER_GROUP"
				break
			fi
		done
	fi

	if [ -n "${POSTGRES_INITDB_WALDIR:-}" ]; then
		set -- --waldir "$POSTGRES_INITDB_WALDIR" "$@"
	fi

	# --pwfile refuses to handle a properly-empty file (hence the "\n"): https://github.com/docker-library/postgres/issues/1025
	eval 'initdb --username="$POSTGRES_USER" --pwfile=<(printf "%s\n" "$POSTGRES_PASSWORD") '"$POSTGRES_INITDB_ARGS"' "$@"'

	# unset/cleanup "nss_wrapper" bits
	if [[ "${LD_PRELOAD:-}" == */libnss_wrapper.so ]]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi
}

# print large warning if POSTGRES_PASSWORD is long
# error if both POSTGRES_PASSWORD is empty and POSTGRES_HOST_AUTH_METHOD is not 'trust'
# print large warning if POSTGRES_HOST_AUTH_METHOD is set to 'trust'
# assumes database is not set up, ie: [ -z "$DATABASE_ALREADY_EXISTS" ]
docker_verify_minimum_env() {
	if [ -z "$POSTGRES_PASSWORD" ] && [ 'trust' != "$POSTGRES_HOST_AUTH_METHOD" ]; then
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOE'
			Error: Database is uninitialized and superuser password is not specified.
			       You must specify POSTGRES_PASSWORD to a non-empty value for the
			       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".

			       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
			       connections without a password. This is *not* recommended.

			       See PostgreSQL documentation about "trust":
			       https://www.postgresql.org/docs/current/auth-trust.html
		EOE
		exit 1
	fi
	if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOWARN'
			********************************************************************************
			WARNING: POSTGRES_HOST_AUTH_METHOD has been set to "trust". This will allow
			         anyone with access to the Postgres port to access your database without
			         a password, even if POSTGRES_PASSWORD is set. See PostgreSQL
			         documentation about "trust":
			         https://www.postgresql.org/docs/current/auth-trust.html
			         In Docker's default configuration, this is effectively any other
			         container on the same system.

			         It is not recommended to use POSTGRES_HOST_AUTH_METHOD=trust. Replace
			         it with "-e POSTGRES_PASSWORD=password" instead to set a password in
			         "docker run".
			********************************************************************************
		EOWARN
	fi
}

# usage: docker_process_init_files [file [file [...]]]
#    ie: docker_process_init_files /always-initdb.d/*
# process initializer files, based on file extensions and permissions
docker_process_init_files() {
	# psql here for backwards compatibility "${psql[@]}"
	psql=( docker_process_sql )

	printf '\n'
	local f
	for f; do
		case "$f" in
			*.sh)
				# https://github.com/docker-library/postgres/issues/450#issuecomment-393167936
				# https://github.com/docker-library/postgres/pull/452
				if [ -x "$f" ]; then
					printf '%s: running %s\n' "$0" "$f"
					"$f"
				else
					printf '%s: sourcing %s\n' "$0" "$f"
					. "$f"
				fi
				;;
			*.sql)     printf '%s: running %s\n' "$0" "$f"; docker_process_sql -f "$f"; printf '\n' ;;
			*.sql.gz)  printf '%s: running %s\n' "$0" "$f"; gunzip -c "$f" | docker_process_sql; printf '\n' ;;
			*.sql.xz)  printf '%s: running %s\n' "$0" "$f"; xzcat "$f" | docker_process_sql; printf '\n' ;;
			*.sql.zst) printf '%s: running %s\n' "$0" "$f"; zstd -dc "$f" | docker_process_sql; printf '\n' ;;
			*)         printf '%s: ignoring %s\n' "$0" "$f" ;;
		esac
		printf '\n'
	done
}

# Execute sql script, passed via stdin (or -f flag of pqsl)
# usage: docker_process_sql [psql-cli-args]
#    ie: docker_process_sql --dbname=mydb <<<'INSERT ...'
#    ie: docker_process_sql -f my-file.sql
#    ie: docker_process_sql <my-file.sql
docker_process_sql() {
	local query_runner=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password --no-psqlrc )
	if [ -n "$POSTGRES_DB" ]; then
		query_runner+=( --dbname "$POSTGRES_DB" )
	fi

	PGHOST= PGHOSTADDR= "${query_runner[@]}" "$@"
}

# create initial database
# uses environment variables for input: POSTGRES_DB
docker_setup_db() {
	local dbAlreadyExists
	dbAlreadyExists="$(
		POSTGRES_DB= docker_process_sql --dbname postgres --set db="$POSTGRES_DB" --tuples-only <<-'EOSQL'
			SELECT 1 FROM pg_database WHERE datname = :'db' ;
		EOSQL
	)"
	if [ -z "$dbAlreadyExists" ]; then
		POSTGRES_DB= docker_process_sql --dbname postgres --set db="$POSTGRES_DB" <<-'EOSQL'
			CREATE DATABASE :"db" ;
		EOSQL
		printf '\n'
	fi
}

# Loads various settings that are used elsewhere in the script
# This should be called before any other functions
docker_setup_env() {
	file_env 'POSTGRES_PASSWORD'

	file_env 'POSTGRES_USER' 'postgres'
	file_env 'POSTGRES_DB' "$POSTGRES_USER"
	file_env 'POSTGRES_INITDB_ARGS'
	: "${POSTGRES_HOST_AUTH_METHOD:=}"

	declare -g DATABASE_ALREADY_EXISTS
	: "${DATABASE_ALREADY_EXISTS:=}"
	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ -s "$PGDATA/PG_VERSION" ]; then
		DATABASE_ALREADY_EXISTS='true'
	fi
}

# append POSTGRES_HOST_AUTH_METHOD to pg_hba.conf for "host" connections
# all arguments will be passed along as arguments to `postgres` for getting the value of 'password_encryption'
pg_setup_hba_conf() {
	# default authentication method is md5 on versions before 14
	# https://www.postgresql.org/about/news/postgresql-14-released-2318/
	if [ "$1" = 'postgres' ]; then
		shift
	fi
	local auth
	# check the default/configured encryption and use that as the auth method
	auth="$(postgres -C password_encryption "$@")"
	: "${POSTGRES_HOST_AUTH_METHOD:=$auth}"
	{
		printf '\n'
		if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
			printf '# warning trust is enabled for all connections\n'
			printf '# see https://www.postgresql.org/docs/12/auth-trust.html\n'
		fi
		printf 'host all all all %s\n' "$POSTGRES_HOST_AUTH_METHOD"
	} >> "$PGDATA/pg_hba.conf"
}

# start socket-only postgresql server for setting up or running scripts
# all arguments will be passed along as arguments to `postgres` (via pg_ctl)
docker_temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	# internal start of server in order to allow setup using psql client
	# does not listen on external TCP/IP and waits until start finishes
	set -- "$@" -c listen_addresses='' -p "${PGPORT:-5432}"

	PGUSER="${PGUSER:-$POSTGRES_USER}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

# stop postgresql server after done setting up user and running scripts
docker_temp_server_stop() {
	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" -m fast -w stop
}

# check arguments for an option that would cause postgres to stop
# return true if there is one
_pg_want_help() {
	local arg
	for arg; do
		case "$arg" in
			# postgres --help | grep 'then exit'
			# leaving out -C on purpose since it always fails and is unhelpful:
			# postgres: could not access the server configuration file "/var/lib/postgresql/data/postgresql.conf": No such file or directory
			-'?'|--help|--describe-config|-V|--version)
				return 0
				;;
		esac
	done
	return 1
}

_main() {
	# if first arg looks like a flag, assume we want to run postgres server
	if [ "${1:0:1}" = '-' ]; then
		set -- postgres "$@"
	fi

	if [ "$1" = 'postgres' ] && ! _pg_want_help "$@"; then
		docker_setup_env
		# setup data directories and permissions (when run as root)
		docker_create_db_directories
		if [ "$(id -u)" = '0' ]; then
			# then restart script as postgres user
			exec gosu postgres "$BASH_SOURCE" "$@"
		fi

		# only run initialization on an empty data directory
		if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
			docker_verify_minimum_env

			# check dir permissions to reduce likelihood of half-initialized database
			ls /docker-entrypoint-initdb.d/ > /dev/null

			docker_init_database_dir
			pg_setup_hba_conf "$@"

			# PGPASSWORD is required for psql when authentication is required for 'local' connections via pg_hba.conf and is otherwise harmless
			# e.g. when '--auth=md5' or '--auth-local=md5' is used in POSTGRES_INITDB_ARGS
			export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
			docker_temp_server_start "$@"

			docker_setup_db


			# Set the path to your SQL file
			SQL_FILE="./docker-entrypoint-initdb.d/00_init.sql"

			if [ -n "$REPLICATOR_PASSWORD" ]; then
			echo "$REPLICATOR_PASSWORD_ENV"
			echo "REPLICATOR_PASSWORD environment variable is set. Proceeding with further processing."
			sed -i "s/123456/${REPLICATOR_PASSWORD}/g" "$SQL_FILE"
			echo "Password in SQL file updated successfully."
			else
			echo "REPLICATOR_PASSWORD environment variable is not set. Deleting SQL file."
			rm -f "$SQL_FILE"
			fi

			docker_process_init_files /docker-entrypoint-initdb.d/*

			docker_temp_server_stop
			unset PGPASSWORD

			if [ "$PG_ROLE" = "PRIMARY" ]; then
				echo "host replication replicator 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf
				echo "host all postgres 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf          
			elif [ "$PG_ROLE" = "REPLICA" ]; then
				echo "Running in REPLICA mode. Checking health..."
        
				DATA_DIR="$PGDATA"
				TEMP_DIR="/var/lib/postgresql/temp_data"

				# --- Your Custom Health Check Logic ---
				
				echo "Starting pg_basebackup from $PRIMARY_DB_IP..."
				rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"
				
				export PGPASSWORD="${REPLICATOR_PASSWORD}"
				# Using -R to automatically create standby.signal and primary_conninfo
				if  PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}" && pg_basebackup \
					-d "postgres://replicator:${REPLICATOR_PASSWORD}@${PRIMARY_DB_IP}:${PRIMARY_DB_PORT:-5432}/postgres" \
					--pgdata="$TEMP_DIR" \
					-R \
					--slot="${REPLICATION_SLOT_NAME:-replication_slot}"; then					
					echo "Backup successful. Swapping data directories..."
					rm -rf "$DATA_DIR"/*
					cp -rT "$TEMP_DIR/" "$DATA_DIR/" # Using cp to avoid cross-device move issues
					rm -rf "$TEMP_DIR"
				else
					echo "ERROR: pg_basebackup failed. Exiting."
					exit 1
				fi				
			fi

			cat <<-'EOM'

				PostgreSQL init process complete; ready for start up.

			EOM
		else
			cat <<-'EOM'

				PostgreSQL Database directory appears to contain a database; Skipping initialization

			EOM
		fi

		# Start db

		if [ "$PG_ROLE" = "PRIMARY" ]; then
			exec postgres \
				-c wal_level=replica \
				-c hot_standby=on \
				-c max_wal_senders=10 \
				-c max_replication_slots=10 \
				-c wal_keep_size=5GB \
				-c max_slot_wal_keep_size=10GB \
				-c hot_standby_feedback=on

		elif [ "$PG_ROLE" = "REPLICA" ]; then
			DATA_DIR=/var/lib/postgresql/data
			TEMP_DIR=/var/lib/postgresql/temp_data

			check_replication() {
				# Primary reachable
				pg_isready -h $PRIMARY_DB_IP -p $PRIMARY_DB_PORT -U replicator >/dev/null 2>&1 || return 1

				# Local postgres responding
				psql -U postgres -tAc "SELECT 1" >/dev/null 2>&1 || return 1

				# Still a replica
				psql -U postgres -tAc "SELECT pg_is_in_recovery()" | grep -q t || return 1

				# WAL streaming active
				psql -U postgres -tAc "SELECT status FROM pg_stat_wal_receiver" | grep -q streaming || return 1

				return 0
			}

			echo "HARD_RESET=$HARD_RESET"

			NEED_REBUILD=false

			# 1. HARD RESET
			if [ "$HARD_RESET" = "true" ]; then
				echo "HARD RESET ENABLED → force rebuild"
				NEED_REBUILD=true

			# 2. First time (no data)
			elif [ ! -s "$DATA_DIR/PG_VERSION" ]; then
				echo "No data found → initial basebackup"
				NEED_REBUILD=true

			# 3. Replica broken
			elif ! check_replication; then
				echo "Replication unhealthy → rebuilding replica"
				NEED_REBUILD=true

			else
				echo "Replica healthy → skipping basebackup"
			fi

			if [ -s "$DATA_DIR/PG_VERSION" ] && [ "$HARD_RESET" = "false" ]; then
				NEED_REBUILD=false
			fi


			# 🔥 Rebuild logic (ONLY when needed)
			if [ "$NEED_REBUILD" = "true" ]; then
				if [ ! -f /var/lib/postgresql/data/postgresql.conf ]; then
				initdb -D /var/lib/postgresql/data
				fi

				echo "host replication replicator 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf
				echo "host all postgres 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf
				echo "Starting pg_basebackup..."

				rm -rf $TEMP_DIR
				mkdir -p $TEMP_DIR

				export PGPASSWORD="${REPLICATOR_PASSWORD}"

				if pg_basebackup \
				--pgdata=$TEMP_DIR \
				-R \
				--slot=replication_slot \
				--host=$PRIMARY_DB_IP \
				--port=$PRIMARY_DB_PORT; then

				echo "Backup done → replacing data directory"

				rm -rf $DATA_DIR/*
				mv $TEMP_DIR/* $DATA_DIR/
				rmdir $TEMP_DIR
				else
				echo "Basebackup FAILED"
				exit 1
				fi
			fi

			chmod 0700 $DATA_DIR

			exec postgres
		fi
		
	fi

	exec "$@"
}

if ! _is_sourced; then
	_main "$@"
fi