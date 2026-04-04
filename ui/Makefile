.PHONY: web
.PHONY: build-web
.PHONY: browser-e2e
.PHONY: hotreload

web:
	flutter run --dart-define=ENV=dev -d chrome --web-port=8080 --pid-file /tmp/flutter.pid

build-web:
	flutter build web --release

browser-e2e:
	npm run test:e2e

hotreload:
	find lib/ -name '*.dart' | \
		entr -p kill -USR1 $$(cat /tmp/flutter.pid)
