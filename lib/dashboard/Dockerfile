FROM alpine:3.20
RUN apk add --no-cache nginx     && mkdir -p /usr/share/nginx/html     && chown -R 1000:1000 /var/lib/nginx /var/log/nginx /run/nginx /usr/share/nginx/html
USER 1000
COPY . /usr/share/nginx/html
CMD ["nginx", "-g", "daemon off;"]
