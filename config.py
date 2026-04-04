import os
import sys
import importlib.util
from dotenv import load_dotenv


APP_NAME = 'narlun'

basedir = os.path.abspath(os.path.dirname(__file__))
load_dotenv(os.path.join(basedir, '.env'))

SENTRY_DSN = ''

SECRET_KEY = 'hellosecret'

PORT = 3000

REDIS_URL = 'redis://localhost:6379'

DOMAIN = 'https://narlun.com'

# load local config
if app_settings := os.environ.get('APP_SETTINGS'):
    localconfig = os.path.abspath(app_settings)
    spec = importlib.util.spec_from_file_location('config', localconfig)
    if spec:
        config = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(config)

        for key in dir(config):
            if not key.startswith('__'):
                setattr(sys.modules[__name__], key, getattr(config, key))

# now apply env vars
for k in list(globals().keys()):
    if v := os.environ.get(k):
        setattr(sys.modules[__name__], k, v)
