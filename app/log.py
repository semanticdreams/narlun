import sys
import logging
import structlog

import config


timestamper = structlog.processors.TimeStamper(fmt="%Y-%m-%d %H:%M:%S")

shared_processors = [
    structlog.stdlib.add_log_level,
    structlog.stdlib.add_logger_name,
    timestamper,
]

structlog.configure(
    processors=shared_processors + [
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    cache_logger_on_first_use=True,
)

formatter = structlog.stdlib.ProcessorFormatter(
    processor=structlog.processors.JSONRenderer(),#structlog.dev.ConsoleRenderer()
    foreign_pre_chain=shared_processors,
)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
root_logger = logging.getLogger()
root_logger.addHandler(handler)
root_logger.setLevel(logging.DEBUG)

get_logger = structlog.get_logger
