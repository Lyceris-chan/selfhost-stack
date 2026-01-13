FROM nginx:alpine
RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run/nginx /var/lib/nginx /usr/share/nginx/html && \
    chown -R 1000:1000 /var/cache/nginx /var/log/nginx /var/run/nginx /var/lib/nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    sed -i 's/^user/#user/' /etc/nginx/nginx.conf && \
    sed -i 's|pid .*|pid /tmp/nginx.pid;|g' /etc/nginx/nginx.conf
USER 1000
COPY . /usr/share/nginx/html
EXPOSE 8081
CMD ["nginx", "-g", "daemon off;"]
