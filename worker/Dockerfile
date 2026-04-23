# Small, official Python base image
FROM python:3.12-slim

# Prevent Python from writing .pyc files and buffering stdout
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install system deps needed by Pillow (JPEG, PNG support)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg62-turbo \
    zlib1g \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy worker code
COPY worker.py processor.py config.py ./

# Run as non-root
RUN useradd --create-home --shell /bin/bash worker && chown -R worker:worker /app
USER worker

CMD ["python", "worker.py"]
