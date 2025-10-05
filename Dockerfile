FROM python:3.10.4-alpine

RUN apk update && apk add \
    python3-dev \
    musl-dev \
    gcc \
    g++ \
    libffi-dev \
    openssl-dev \
    cargo \
    make \
    postgresql-dev \
    zlib \
    cairo \
    cairo-dev \
    cairo-tools

ENV PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  PYTHONHASHSEED=random \
  PIP_NO_CACHE_DIR=off \
  PIP_DISABLE_PIP_VERSION_CHECK=on \
  PIP_DEFAULT_TIMEOUT=100 \
  POETRY_VERSION=1.0.0

# System deps:
RUN pip install "poetry==$POETRY_VERSION"

# Copy only requirements to cache them in docker layer
WORKDIR /code
COPY poetry.lock pyproject.toml /code/

# Project initialization:
RUN poetry config virtualenvs.create false \
  && poetry install --no-dev --no-interaction --no-ansi

# Creating folders, and files for a project:
COPY . /code

EXPOSE 3000
CMD ["./entrypoint.sh"]
