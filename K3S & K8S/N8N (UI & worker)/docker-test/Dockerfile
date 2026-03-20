FROM docker.n8n.io/n8nio/n8n

USER root
RUN apk add --no-cache postgresql-client

# Copy Oracle Instant Client
RUN apk add --no-cache libaio libnsl libc6-compat gcompat
COPY instantclient_23_9 /opt/oracle/instantclient_23_9

# Configure environment for Oracle client + sqlplus
ENV LD_LIBRARY_PATH=/opt/oracle/instantclient_23_9:$LD_LIBRARY_PATH \
    PATH=/opt/oracle/instantclient_23_9:$PATH

USER node