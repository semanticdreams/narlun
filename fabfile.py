from fabric import task


@task
def lint(c):
    c.run('uv run flake8 app tests --extend-ignore=E501')


@task
def test(c):
    c.run('uv run python -m pytest -svx')
