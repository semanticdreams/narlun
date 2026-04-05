CLIENT_SESSION_HEADER = 'X-Narlun-Client-Session-ID'


def client_ip(req):
    forwarded = req.headers.get('X-Forwarded-For', '')
    if forwarded:
        first = forwarded.split(',', 1)[0].strip()
        if first:
            return first
    return req.remote or '-'


def request_log_context(req, **extra):
    request_data = getattr(req, 'data', None)
    body_client_session_id = None
    if isinstance(request_data, dict):
        candidate = request_data.get('client_session_id')
        if isinstance(candidate, str) and candidate.strip():
            body_client_session_id = candidate.strip()

    context = {
        'request_id': getattr(req, 'request_id', None),
        'method': req.method,
        'path': req.path_qs,
        'remote_ip': client_ip(req),
        'client_session_id': (
            req.headers.get(CLIENT_SESSION_HEADER)
            or req.query.get('client_session_id')
            or body_client_session_id
        ),
        'client_id': req.query.get('client_id'),
    }
    user = getattr(req, 'user', None)
    if isinstance(user, dict) and user.get('authenticated') is True:
        context['user_id'] = user.get('id')
    for key, value in extra.items():
        if value is not None:
            context[key] = value
    return context


def sample_values(values, *, limit=10):
    return list(values)[:limit]
