from fabric import task


@task
def db_migrate(c):
    c.run('poetry run alembic -c migrations/alembic.ini revision --autogenerate')


@task
def db_upgrade(c):
    c.run('poetry run alembic -c migrations/alembic.ini upgrade head')


@task
def lint(c):
    c.run('poetry run flake8 app tests --extend-ignore=E501')
