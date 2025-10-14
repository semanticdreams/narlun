abstract class BaseConfig {
  String get apiUrl;
  String get sentryDsn;
}

class DevConfig implements BaseConfig {
  String get apiUrl => "http://localhost:3000/api";
  String get sentryDsn => "";
}

class ProdConfig implements BaseConfig {
  String get apiUrl => "https://narlun.com/api";
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

  initConfig(String environment) {
    config = _getConfig(environment);
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
