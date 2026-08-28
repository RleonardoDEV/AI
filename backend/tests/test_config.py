from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.config import AppEnv, Settings


def _settings(**overrides: object) -> Settings:
    base: dict[str, object] = {"_env_file": None}
    return Settings(**{**base, **overrides})  # type: ignore[arg-type]


class TestGraphScopeGuard:
    """docs/04 §2: combinar Sites.Selected con un ámbito amplio lo anula.

    Es un fallo silencioso — todo sigue funcionando, solo que con acceso a todo
    el contenido del usuario — así que se rechaza al arrancar.
    """

    def test_sites_selected_alone_is_accepted(self) -> None:
        settings = _settings(graph_scopes="https://graph.microsoft.com/Sites.Selected")
        assert settings.graph_scope_list == ["https://graph.microsoft.com/Sites.Selected"]

    def test_broad_scopes_alone_are_accepted(self) -> None:
        scopes = "https://graph.microsoft.com/Files.Read.All https://graph.microsoft.com/Sites.Read.All"
        assert len(_settings(graph_scopes=scopes).graph_scope_list) == 2

    @pytest.mark.parametrize(
        "broad",
        ["Files.Read.All", "Sites.Read.All", "Files.ReadWrite.All", "Sites.ReadWrite.All"],
    )
    def test_mixing_is_rejected(self, broad: str) -> None:
        with pytest.raises(ValidationError, match="pierde su efecto restrictivo"):
            _settings(
                graph_scopes=f"https://graph.microsoft.com/Sites.Selected "
                f"https://graph.microsoft.com/{broad}"
            )

    def test_message_names_the_offending_scope(self) -> None:
        with pytest.raises(ValidationError, match="Files.Read.All"):
            _settings(graph_scopes="Sites.Selected Files.Read.All")


class TestContentLogging:
    def test_allowed_in_local(self) -> None:
        settings = _settings(app_env=AppEnv.LOCAL, log_document_content=True)
        settings.validate_runtime()

    def test_rejected_outside_local(self) -> None:
        settings = _settings(
            app_env=AppEnv.PRODUCTION,
            log_document_content=True,
            azure_tenant_id="t",
            azure_api_client_id="c",
        )
        with pytest.raises(ValueError, match="solo se admite en APP_ENV=local"):
            settings.validate_runtime()

    def test_default_is_off(self) -> None:
        assert _settings().log_document_content is False


class TestDerivedValues:
    def test_authority_and_audience(self) -> None:
        settings = _settings(azure_tenant_id="tid", azure_api_client_id="cid")
        assert settings.entra_authority == "https://login.microsoftonline.com/tid"
        assert settings.api_audience == "api://cid"
        assert settings.microsoft_configured is True

    def test_not_configured_without_ids(self) -> None:
        assert _settings().microsoft_configured is False

    def test_production_requires_microsoft_ids(self) -> None:
        with pytest.raises(ValueError, match="AZURE_TENANT_ID"):
            _settings(app_env=AppEnv.PRODUCTION).validate_runtime()
