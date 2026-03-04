FROM ossrs/srs:6

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/srs/objs/nginx/html /usr/local/srs/objs/logs
