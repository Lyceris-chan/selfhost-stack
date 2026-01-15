#!/bin/bash
SUDO=""
SRC_DIR="/tmp/test_zima"
PORT_DASHBOARD_WEB="8080"
mkdir -p "${SRC_DIR}/dashboard"
cat <<EOF | ${SUDO} tee "${SRC_DIR}/dashboard/Dockerfile" >/dev/null
FROM nginx:alpine
RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run/nginx /var/lib/nginx /usr/share/nginx/html && \
    chown -R 1000:1000 /var/cache/nginx /var/log/nginx /var/run/nginx /var/lib/nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    sed -i 's/^user/#user/' /etc/nginx/nginx.conf && \
    sed -i 's|pid .*|pid /tmp/nginx.pid;|g' /etc/nginx/nginx.conf
USER 1000
COPY . /usr/share/nginx/html
EXPOSE ${PORT_DASHBOARD_WEB}
CMD ["nginx", "-g", "daemon off;"]
EOF
