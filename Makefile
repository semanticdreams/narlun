.PHONY: test run lint cov secret-key

run:
	uv run python -m app.app

test:
	uv run python -m pytest -svx

lint:
	uv run flake8 app tests --extend-ignore=E501

cov:
	uv run coverage run -m pytest -svx && uv run coverage report -m

secret-key:
	python -c 'import secrets; secrets.token_hex(52)'
