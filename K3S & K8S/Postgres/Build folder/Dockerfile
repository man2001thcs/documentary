FROM postgres:15

ARG REPLICATOR_PASSWORD=123456
# Create plpython3u when the db starts. 
RUN echo 'CREATE EXTENSION IF NOT EXISTS plpython3u;' > /docker-entrypoint-initdb.d/py3.sql
# Installing last python and plpython3 for current version
RUN apt update && apt install python3 python3-pip postgresql-plpython3-${PG_MAJOR} -y

COPY ./change_replica_pass.sh ./change_replica_pass.sh
COPY ./00_init.sql ./docker-entrypoint-initdb.d/00_init.sql

USER root
# Check ownership and permissions
RUN ls -ld /var/lib/postgresql
# If necessary, adjust ownership and permissions
RUN chown -R postgres:postgres /var/lib/postgresql
RUN chmod 777 /var/lib/postgresql
RUN chmod 777 ./docker-entrypoint-initdb.d
RUN chmod +x ./change_replica_pass.sh
RUN chmod 777 ./change_replica_pass.sh

USER postgres
EXPOSE 5432
ENTRYPOINT ["./change_replica_pass.sh"]

# We set the default STOPSIGNAL to SIGINT, which corresponds to what PostgreSQL
# calls "Fast Shutdown mode" wherein new connections are disallowed and any
# in-progress transactions are aborted, allowing PostgreSQL to stop cleanly and
# flush tables to disk.
#
# See https://www.postgresql.org/docs/current/server-shutdown.html for more details
# about available PostgreSQL server shutdown signals.
#
# See also https://www.postgresql.org/docs/current/server-start.html for further
# justification of this as the default value, namely that the example (and
# shipped) systemd service files use the "Fast Shutdown mode" for service
# termination.
#
STOPSIGNAL SIGINT
#
# An additional setting that is recommended for all users regardless of this
# value is the runtime "--stop-timeout" (or your orchestrator/runtime's
# equivalent) for controlling how long to wait between sending the defined
# STOPSIGNAL and sending SIGKILL.
#
# The default in most runtimes (such as Docker) is 10 seconds, and the
# documentation at https://www.postgresql.org/docs/current/server-start.html notes
# that even 90 seconds may not be long enough in many instances.

EXPOSE 5432
CMD ["postgres"]