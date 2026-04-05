import importlib

import config


def test_port_env_is_coerced_to_int(monkeypatch):
    monkeypatch.setenv('PORT', '3000')
    reloaded = importlib.reload(config)

    try:
        assert reloaded.PORT == 3000
        assert isinstance(reloaded.PORT, int)
    finally:
        monkeypatch.delenv('PORT', raising=False)
        importlib.reload(config)


def test_bind_host_env_is_applied(monkeypatch):
    monkeypatch.setenv('BIND_HOST', '127.0.0.1')
    reloaded = importlib.reload(config)

    try:
        assert reloaded.BIND_HOST == '127.0.0.1'
    finally:
        monkeypatch.delenv('BIND_HOST', raising=False)
        importlib.reload(config)
