abstract class BaseConfig {
  String get apiUrl;
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
}

class DevConfig implements BaseConfig {
  @override
  String get apiUrl => "http://localhost:3000/api";
}

class ProdConfig implements BaseConfig {
  @override
  String get apiUrl => "/api";
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
