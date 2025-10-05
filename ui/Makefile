.PHONY: linux 
.PHONY: web 
.PHONY: hotreload

linux:
	flutter run --dart-define=ENV=dev -d linux --pid-file /tmp/flutter.pid

chrome:
	flutter run --dart-define=ENV=dev -d chrome --web-port=8080 --pid-file /tmp/flutter.pid

hotreload:
	find lib/ -name '*.dart' | \
		entr -p kill -USR1 $$(cat /tmp/flutter.pid)
