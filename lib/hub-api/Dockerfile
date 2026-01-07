FROM python:3.11-alpine
RUN apk add --no-cache --virtual .build-deps gcc musl-dev linux-headers python3-dev \
    && apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git \
    && pip install --no-cache-dir psutil \
    && apk del .build-deps
WORKDIR /app
COPY . .
RUN chown -R 1000:1000 /app
USER 1000
CMD ["python", "server.py"]