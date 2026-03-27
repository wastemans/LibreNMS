FROM librenms/librenms:latest
RUN apt-get update \
 && apt-get install -y --no-install-recommends monitoring-plugins-basic \
 && rm -rf /var/lib/apt/lists/*
