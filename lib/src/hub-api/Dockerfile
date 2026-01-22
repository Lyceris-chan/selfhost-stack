FROM python:3.11-alpine

# Install build dependencies and system tools
RUN apk add --no-cache --virtual .build-deps gcc musl-dev linux-headers python3-dev \
    && apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git bash iptables util-linux jq iproute2 \
    && pip install --upgrade pip

# Copy requirements first for cache efficiency
WORKDIR /app
COPY requirements.txt .

# Create user first
RUN addgroup -g 1000 hubgroup && \
    adduser -u 1000 -G hubgroup -s /bin/sh -D hubuser

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt \
    && apk del .build-deps

# Copy application code
COPY . .

# Permissions
RUN mkdir -p /app/data \
    && touch /app/deployment.log \
    && chown -R 1000:1000 /app

USER 1000

# Start Uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "55555"]
