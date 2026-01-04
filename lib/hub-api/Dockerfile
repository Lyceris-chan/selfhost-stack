FROM dhi.io/python:3.11-alpine3.22-dev
RUN apk add --no-cache --virtual .build-deps gcc musl-dev linux-headers python3-dev \
    && apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git \
    && pip install --no-cache-dir psutil \
    && apk del .build-deps
WORKDIR /app
COPY . .
CMD ["python", "server.py"]