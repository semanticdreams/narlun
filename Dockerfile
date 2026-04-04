FROM python:3.12-alpine

RUN apk update && apk add \
    python3-dev \
    musl-dev \
    gcc \
    g++ \
    libffi-dev \
    openssl-dev \
    cargo \
    make \
    zlib \
    cairo \
    cairo-dev \
    cairo-tools

ENV PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  PYTHONHASHSEED=random \
  PIP_NO_CACHE_DIR=off \
  PIP_DISABLE_PIP_VERSION_CHECK=on \
  PIP_DEFAULT_TIMEOUT=100

RUN pip install "uv>=0.7,<0.8"

WORKDIR /code
COPY uv.lock pyproject.toml /code/
RUN uv sync --frozen --no-dev

COPY . /code

EXPOSE 3000
CMD ["./entrypoint.sh"]
