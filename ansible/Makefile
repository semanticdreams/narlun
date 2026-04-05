.PHONY: provision deploy logs

provision:
	ansible-playbook provision.yml

deploy:
	ansible-playbook deploy.yml

logs:
	ansible-playbook logs.yml $(if $(SINCE),-e '{"log_since":"$(SINCE)"}',)
