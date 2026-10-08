FROM python:3.13-alpine
RUN apk add --no-cache tzdata
WORKDIR /app
COPY monitor.py .
CMD ["python", "-u", "monitor.py"]
