"""Logging estructurado.

Regla de docs/04 §4: los logs contienen identificadores, hashes y métricas.
Nunca contenido de documentos, prompts completos ni tokens.
"""

from __future__ import annotations

import logging
import re
import sys
from typing import Any

import structlog

# Claves cuyo valor jamás debe aparecer en un log.
_REDACTED_KEYS = frozenset(
    {
        "access_token",
        "refresh_token",
        "id_token",
        "authorization",
        "client_secret",
        "api_key",
        "llm_api_key",
        "password",
        "prompt",
        "content",
        "text",
        "chunk_text",
        "document_text",
    }
)

_BEARER = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE)


def _redact(
    _logger: Any, _method: str, event_dict: structlog.types.EventDict
) -> structlog.types.EventDict:
    for key in list(event_dict):
        if key.lower() in _REDACTED_KEYS:
            event_dict[key] = "[redacted]"
        elif isinstance(event_dict[key], str):
            event_dict[key] = _BEARER.sub(r"\1[redacted]", event_dict[key])
    return event_dict


def configure_logging(level: str = "INFO", *, json_output: bool = True) -> None:
    logging.basicConfig(format="%(message)s", stream=sys.stdout, level=level.upper())

    processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        _redact,
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]
    processors.append(
        structlog.processors.JSONRenderer() if json_output else structlog.dev.ConsoleRenderer()
    )

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.getLevelNamesMapping()[level.upper()]
        ),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    return structlog.get_logger(name)  # type: ignore[no-any-return]
