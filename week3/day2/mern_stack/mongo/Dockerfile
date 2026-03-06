FROM mongo:7

COPY keyfile /etc/mongo-keyfile
RUN chmod 400 /etc/mongo-keyfile && chown mongodb:mongodb /etc/mongo-keyfile
