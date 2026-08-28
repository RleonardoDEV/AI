"""Conversión de valores de celda a tipos canónicos.

Principio (docs/00, P4): si un valor no se puede convertir con certeza, se
devuelve un error. Nunca se adivina ni se sustituye por un valor por defecto.
"""

from __future__ import annotations

import datetime as dt
import re
from typing import Any

from app.schemas.domain import Level, RiskStatus, TaskStatus


class CoercionError(ValueError):
    """El valor no se pudo convertir. `reason` es el motivo de cuarentena."""

    def __init__(self, reason: str, value: Any) -> None:
        super().__init__(f"{reason}: {value!r}")
        self.reason = reason
        self.value = value


# Excel guarda las fechas como número de días desde 1899-12-30 (sistema 1900).
_EXCEL_EPOCH = dt.date(1899, 12, 30)
_EXCEL_SERIAL_MIN = 1
_EXCEL_SERIAL_MAX = 60000  # ~2064; por encima casi seguro no es una fecha

_DATE_FORMATS = (
    "%d/%m/%Y",
    "%d/%m/%y",
    "%Y-%m-%d",
    "%d-%m-%Y",
    "%d.%m.%Y",
    "%Y/%m/%d",
)

_TRUE_VALUES = frozenset({"true", "yes", "y", "sí", "si", "x", "1", "verdadero", "vrai"})
_FALSE_VALUES = frozenset({"false", "no", "n", "0", "falso", "-", ""})

_STATUS_SYNONYMS: dict[str, TaskStatus] = {
    # NOT_STARTED
    "not started": TaskStatus.NOT_STARTED,
    "notstarted": TaskStatus.NOT_STARTED,
    "pending": TaskStatus.NOT_STARTED,
    "to do": TaskStatus.NOT_STARTED,
    "todo": TaskStatus.NOT_STARTED,
    "new": TaskStatus.NOT_STARTED,
    "open": TaskStatus.NOT_STARTED,
    "pendiente": TaskStatus.NOT_STARTED,
    "no iniciada": TaskStatus.NOT_STARTED,
    "no iniciado": TaskStatus.NOT_STARTED,
    "sin empezar": TaskStatus.NOT_STARTED,
    # IN_PROGRESS
    "in progress": TaskStatus.IN_PROGRESS,
    "inprogress": TaskStatus.IN_PROGRESS,
    "wip": TaskStatus.IN_PROGRESS,
    "ongoing": TaskStatus.IN_PROGRESS,
    "started": TaskStatus.IN_PROGRESS,
    "active": TaskStatus.IN_PROGRESS,
    "en curso": TaskStatus.IN_PROGRESS,
    "en progreso": TaskStatus.IN_PROGRESS,
    "iniciada": TaskStatus.IN_PROGRESS,
    # BLOCKED
    "blocked": TaskStatus.BLOCKED,
    "on hold": TaskStatus.BLOCKED,
    "onhold": TaskStatus.BLOCKED,
    "waiting": TaskStatus.BLOCKED,
    "impediment": TaskStatus.BLOCKED,
    "bloqueada": TaskStatus.BLOCKED,
    "bloqueado": TaskStatus.BLOCKED,
    "en espera": TaskStatus.BLOCKED,
    # DONE
    "done": TaskStatus.DONE,
    "completed": TaskStatus.DONE,
    "complete": TaskStatus.DONE,
    "closed": TaskStatus.DONE,
    "finished": TaskStatus.DONE,
    "completada": TaskStatus.DONE,
    "completado": TaskStatus.DONE,
    "cerrada": TaskStatus.DONE,
    "finalizada": TaskStatus.DONE,
    "terminada": TaskStatus.DONE,
    # CANCELLED
    "cancelled": TaskStatus.CANCELLED,
    "canceled": TaskStatus.CANCELLED,
    "dropped": TaskStatus.CANCELLED,
    "descartada": TaskStatus.CANCELLED,
    "cancelada": TaskStatus.CANCELLED,
}

_RISK_STATUS_SYNONYMS: dict[str, RiskStatus] = {
    "open": RiskStatus.OPEN,
    "new": RiskStatus.OPEN,
    "identified": RiskStatus.OPEN,
    "abierto": RiskStatus.OPEN,
    "abierta": RiskStatus.OPEN,
    "mitigating": RiskStatus.MITIGATING,
    "in progress": RiskStatus.MITIGATING,
    "monitoring": RiskStatus.MITIGATING,
    "mitigando": RiskStatus.MITIGATING,
    "en mitigacion": RiskStatus.MITIGATING,
    "closed": RiskStatus.CLOSED,
    "resolved": RiskStatus.CLOSED,
    "cerrado": RiskStatus.CLOSED,
    "cerrada": RiskStatus.CLOSED,
    "accepted": RiskStatus.ACCEPTED,
    "aceptado": RiskStatus.ACCEPTED,
    "aceptada": RiskStatus.ACCEPTED,
}

_LEVEL_SYNONYMS: dict[str, Level] = {
    "low": Level.LOW,
    "l": Level.LOW,
    "1": Level.LOW,
    "baja": Level.LOW,
    "bajo": Level.LOW,
    "medium": Level.MEDIUM,
    "med": Level.MEDIUM,
    "m": Level.MEDIUM,
    "2": Level.MEDIUM,
    "media": Level.MEDIUM,
    "medio": Level.MEDIUM,
    "high": Level.HIGH,
    "h": Level.HIGH,
    "3": Level.HIGH,
    "alta": Level.HIGH,
    "alto": Level.HIGH,
}


def normalize_key(value: Any) -> str:
    """Normaliza para comparar: minúsculas, sin acentos, espacios colapsados."""
    text = str(value).strip().lower()
    for accented, plain in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ú", "u"), ("ñ", "n")):
        text = text.replace(accented, plain)
    return re.sub(r"[\s_\-]+", " ", text).strip()


def is_blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def to_text(value: Any) -> str | None:
    if is_blank(value):
        return None
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value).strip()


def to_date(value: Any) -> dt.date | None:
    """Fecha nativa, número de serie de Excel o texto en formato conocido."""
    if is_blank(value):
        return None
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, dt.date):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        serial = int(value)
        if not _EXCEL_SERIAL_MIN <= serial <= _EXCEL_SERIAL_MAX:
            raise CoercionError("unparseable_date", value)
        return _EXCEL_EPOCH + dt.timedelta(days=serial)

    text = str(value).strip()
    for fmt in _DATE_FORMATS:
        try:
            return dt.datetime.strptime(text, fmt).date()  # noqa: DTZ007
        except ValueError:
            continue
    raise CoercionError("unparseable_date", value)


def to_number(value: Any) -> float | None:
    """Número, admitiendo coma decimal, separador de miles y porcentaje."""
    if is_blank(value):
        return None
    if isinstance(value, bool):
        raise CoercionError("unparseable_number", value)
    if isinstance(value, (int, float)):
        return float(value)

    text = str(value).strip().replace("€", "").replace("$", "").replace("%", "").strip()
    # "1.234,56" (europeo) frente a "1,234.56" (anglosajón)
    if "," in text and "." in text:
        text = text.replace(".", "").replace(",", ".") if text.rindex(",") > text.rindex(".") \
            else text.replace(",", "")
    elif "," in text:
        text = text.replace(",", ".")
    try:
        return float(text)
    except ValueError as exc:
        raise CoercionError("unparseable_number", value) from exc


def to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if is_blank(value):
        return False
    key = normalize_key(value)
    if key in _TRUE_VALUES:
        return True
    if key in _FALSE_VALUES:
        return False
    raise CoercionError("unparseable_boolean", value)


def to_task_status(value: Any) -> TaskStatus:
    if is_blank(value):
        raise CoercionError("missing_status", value)
    key = normalize_key(value)
    if key in _STATUS_SYNONYMS:
        return _STATUS_SYNONYMS[key]
    upper = str(value).strip().upper().replace(" ", "_")
    if upper in TaskStatus.__members__:
        return TaskStatus[upper]
    raise CoercionError("unknown_status", value)


def to_risk_status(value: Any) -> RiskStatus:
    if is_blank(value):
        raise CoercionError("missing_status", value)
    key = normalize_key(value)
    if key in _RISK_STATUS_SYNONYMS:
        return _RISK_STATUS_SYNONYMS[key]
    upper = str(value).strip().upper()
    if upper in RiskStatus.__members__:
        return RiskStatus[upper]
    raise CoercionError("unknown_status", value)


def to_level(value: Any) -> Level | None:
    if is_blank(value):
        return None
    key = normalize_key(value)
    if key in _LEVEL_SYNONYMS:
        return _LEVEL_SYNONYMS[key]
    raise CoercionError("unknown_level", value)


def to_id_list(value: Any) -> tuple[str, ...]:
    """Lista de identificadores separados por coma, punto y coma o barra."""
    if is_blank(value):
        return ()
    parts = re.split(r"[,;/|]", str(value))
    return tuple(p.strip() for p in parts if p.strip())


COERCERS = {
    "text": to_text,
    "date": to_date,
    "number": to_number,
    "boolean": to_bool,
    "task_status": to_task_status,
    "risk_status": to_risk_status,
    "level": to_level,
    "id_list": to_id_list,
}
