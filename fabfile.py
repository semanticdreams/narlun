from fabric import task


@task
def lint(c):
    c.run('poetry run flake8 app tests --extend-ignore=E501')


@task
def test(c):
    c.run('poetry run python -m pytest -svx')
