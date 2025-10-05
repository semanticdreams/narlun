.PHONY: test run lint cov secret-key

run:
	#poetry run python -m app.app
	poetry run adev runserver app --port=5000

test:
	poetry run python -m pytest -svx

lint:
	flake8 app tests --extend-ignore=E501

cov:
	poetry run coverage run -m pytest -svx && poetry run coverage report -m

secret-key:
	python -c 'import secrets; secrets.token_hex(52)'
