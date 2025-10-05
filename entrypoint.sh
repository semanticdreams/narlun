#! /bin/sh

python -m alembic -c migrations/alembic.ini upgrade head
python -m app.app
