FROM python:3.11-alpine

# Install build dependencies and system tools
RUN apk add --no-cache --virtual .build-deps gcc musl-dev linux-headers python3-dev \
    && apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git bash \
    && pip install --upgrade pip

# Copy requirements first for cache efficiency
WORKDIR /app
COPY requirements.txt .

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
