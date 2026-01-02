FROM dhi.io/python:3.11-alpine3.22-dev
RUN apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git gcc musl-dev linux-headers python3-dev
RUN pip install psutil
WORKDIR /app
CMD ["python", "server.py"]
