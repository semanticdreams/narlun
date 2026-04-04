.PHONY: test run lint cov secret-key provision deploy

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

provision:
	$(MAKE) -C ansible provision

deploy:
	NARLUN_REPO_ROOT=$(CURDIR) $(MAKE) -C ansible deploy
