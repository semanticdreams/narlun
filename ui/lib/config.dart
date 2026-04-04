abstract class BaseConfig {
  String get apiUrl;
  String get sentryDsn;
}

class OverrideConfig implements BaseConfig {
  final BaseConfig delegate;
  final String? apiUrlOverride;

  OverrideConfig(this.delegate, this.apiUrlOverride);

  @override
  String get apiUrl {
    if (apiUrlOverride != null && apiUrlOverride!.isNotEmpty) {
      return apiUrlOverride!;
    }
    return delegate.apiUrl;
  }

  @override
  String get sentryDsn => delegate.sentryDsn;
}

class DevConfig implements BaseConfig {
  @override
  String get apiUrl => "http://localhost:3000/api";
  @override
  String get sentryDsn => "";
}

class ProdConfig implements BaseConfig {
  @override
  String get apiUrl => "https://narlun.com/api";
  @override
  String get sentryDsn =>
      "https://110dcdf879bb4c0184543ef262562aff@o176309.ingest.sentry.io/6520711";
}

class Environment {
  factory Environment() {
    return _singleton;
  }

  Environment._internal();

  static final Environment _singleton = Environment._internal();

  static const String DEV = 'DEV';
  static const String PROD = 'PROD';

  BaseConfig config = ProdConfig();

  void initConfig(String environment, {String? apiUrlOverride}) {
    config = OverrideConfig(_getConfig(environment), apiUrlOverride);
  }

  BaseConfig _getConfig(String environment) {
    switch (environment) {
      case Environment.DEV:
        return DevConfig();
      default:
        return ProdConfig();
    }
  }
}
