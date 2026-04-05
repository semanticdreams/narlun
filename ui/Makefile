.PHONY: web
.PHONY: build-web
.PHONY: browser-e2e
.PHONY: hotreload
.PHONY: sync-icons

web:
	flutter run --dart-define=ENV=dev -d chrome --web-port=8080 --pid-file /tmp/flutter.pid

build-web:
	./tool/build_web.sh

sync-icons:
	uv run python ./tool/sync_web_icons.py

browser-e2e:
	npm run test:e2e

hotreload:
	find lib/ -name '*.dart' | \
		entr -p kill -USR1 $$(cat /tmp/flutter.pid)
