# agwatch: minimal watchdog for one AGR campaign.
# Talks to the host docker daemon through the mounted socket. It never scans
# processes (no CIM/WMI - the root cause of every duplicate-loop bug in the
# Windows era): container identity + heartbeat are the only signals.
FROM alpine:3.20

RUN apk add --no-cache docker-cli bash

COPY watchdog.sh /opt/agr/watchdog.sh
RUN chmod +x /opt/agr/watchdog.sh

ENTRYPOINT ["/opt/agr/watchdog.sh"]
