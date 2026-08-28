from __future__ import annotations

import datetime as dt

import pytest

from app.ingestion.excel import coercion as c
from app.schemas.domain import Level, RiskStatus, TaskStatus


class TestDates:
    @pytest.mark.parametrize(
        ("value", "expected"),
        [
            (dt.datetime(2026, 8, 15, 10, 30), dt.date(2026, 8, 15)),  # noqa: DTZ001
            (dt.date(2026, 8, 15), dt.date(2026, 8, 15)),
            ("15/08/2026", dt.date(2026, 8, 15)),
            ("2026-08-15", dt.date(2026, 8, 15)),
            ("15-08-2026", dt.date(2026, 8, 15)),
            ("15.08.2026", dt.date(2026, 8, 15)),
            (46249, dt.date(2026, 8, 15)),  # número de serie de Excel
        ],
    )
    def test_accepted_formats(self, value: object, expected: dt.date) -> None:
        assert c.to_date(value) == expected

    def test_blank_is_none(self) -> None:
        assert c.to_date(None) is None
        assert c.to_date("   ") is None

    @pytest.mark.parametrize("value", ["cuando se pueda", "15 de agosto", "N/A", 999999])
    def test_unparseable_never_guesses(self, value: object) -> None:
        """Una fecha ambigua va a cuarentena; no se inventa un valor."""
        with pytest.raises(c.CoercionError) as exc:
            c.to_date(value)
        assert exc.value.reason == "unparseable_date"


class TestNumbers:
    @pytest.mark.parametrize(
        ("value", "expected"),
        [(42, 42.0), (3.5, 3.5), ("1.234,56", 1234.56), ("1,234.56", 1234.56),
         ("1234,5", 1234.5), ("85%", 85.0), ("12 000", None)],
    )
    def test_formats(self, value: object, expected: float | None) -> None:
        if expected is None:
            with pytest.raises(c.CoercionError):
                c.to_number(value)
        else:
            assert c.to_number(value) == pytest.approx(expected)


class TestStatus:
    @pytest.mark.parametrize(
        ("value", "expected"),
        [
            ("Blocked", TaskStatus.BLOCKED),
            ("on hold", TaskStatus.BLOCKED),
            ("Bloqueada", TaskStatus.BLOCKED),
            ("En curso", TaskStatus.IN_PROGRESS),
            ("WIP", TaskStatus.IN_PROGRESS),
            ("Completada", TaskStatus.DONE),
            ("DONE", TaskStatus.DONE),
            ("Pendiente", TaskStatus.NOT_STARTED),
        ],
    )
    def test_synonyms(self, value: str, expected: TaskStatus) -> None:
        assert c.to_task_status(value) == expected

    def test_unknown_status_is_quarantined_not_defaulted(self) -> None:
        """Regla explícita de docs/08 §G: nunca degradar a NOT_STARTED."""
        with pytest.raises(c.CoercionError) as exc:
            c.to_task_status("Semi-hecho")
        assert exc.value.reason == "unknown_status"

    def test_risk_and_level(self) -> None:
        assert c.to_risk_status("Mitigando") is RiskStatus.MITIGATING
        assert c.to_level("Alta") is Level.HIGH
        assert c.to_level(None) is None


class TestMisc:
    @pytest.mark.parametrize(
        ("value", "expected"),
        [("Sí", True), ("no", False), ("X", True), (1, True)],
    )
    def test_bool(self, value: object, expected: bool) -> None:
        assert c.to_bool(value) is expected

    def test_bool_rejects_garbage(self) -> None:
        with pytest.raises(c.CoercionError):
            c.to_bool("quizás")

    def test_id_list(self) -> None:
        assert c.to_id_list("T-001, T-002;T-003") == ("T-001", "T-002", "T-003")
        assert c.to_id_list(None) == ()

    def test_normalize_key_strips_accents(self) -> None:
        assert c.normalize_key("  Fin  Planificado ") == "fin planificado"
        assert c.normalize_key("Descripción") == "descripcion"
