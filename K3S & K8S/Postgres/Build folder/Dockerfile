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
