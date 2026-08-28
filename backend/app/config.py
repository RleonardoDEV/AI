"""Configuración de la aplicación.

Toda la configuración llega por variables de entorno. Ningún secreto vive en el
código ni en el repositorio (ver docs/04, sección 5).
"""

from __future__ import annotations

from enum import StrEnum
from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class AppEnv(StrEnum):
    LOCAL = "local"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    """Configuración tipada. Falla al arrancar si algo obligatorio falta."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_env: AppEnv = AppEnv.LOCAL
    log_level: str = "INFO"

    # Registrar contenido de documentos solo se admite en depuración local.
    log_document_content: bool = False

    # ── Microsoft Entra ID ────────────────────────────────────────────
    azure_tenant_id: str = ""
    azure_api_client_id: str = ""
    azure_api_client_secret: str = ""
    azure_spa_client_id: str = ""
    graph_scopes: str = "https://graph.microsoft.com/Sites.Selected"

    # ── Recuperación y modelo ─────────────────────────────────────────
    retrieval_provider: Literal["local", "m365"] = "local"
    llm_provider: Literal["fake", "openai", "azure_openai"] = "fake"
    llm_api_key: str = ""
    llm_base_url: str = ""
    llm_model_synthesis: str = ""
    llm_model_extraction: str = ""
    llm_model_analysis: str = ""
    embedding_model: str = ""
    embedding_dimensions: int = 1536

    # ── Base de datos ─────────────────────────────────────────────────
    database_url: str = "postgresql+asyncpg://aipm:aipm@localhost:5432/aipm"

    # ── Retención y límites ───────────────────────────────────────────
    audit_retention_days: int = 365
    chunk_retention_days: int = 180
    max_evidence_per_answer: int = Field(default=12, ge=1, le=50)

    # Si la proporción de filas en cuarentena supera este umbral, el Health
    # del proyecto pasa a UNKNOWN en lugar de calcularse con datos dudosos.
    quarantine_ratio_unknown: float = Field(default=0.20, ge=0.0, le=1.0)

    @property
    def graph_scope_list(self) -> list[str]:
        return [s for s in self.graph_scopes.split() if s]

    @property
    def entra_authority(self) -> str:
        return f"https://login.microsoftonline.com/{self.azure_tenant_id}"

    @property
    def api_audience(self) -> str:
        return f"api://{self.azure_api_client_id}"

    @property
    def microsoft_configured(self) -> bool:
        """True si hay credenciales suficientes para hablar con Entra ID/Graph."""
        return bool(self.azure_tenant_id and self.azure_api_client_id)

    @field_validator("graph_scopes")
    @classmethod
    def _reject_broad_scopes_with_selected(cls, v: str) -> str:
        """Impide combinar Sites.Selected con ámbitos amplios.

        Files.Read.All o Sites.Read.All anulan el efecto restrictivo de
        Sites.Selected: los permisos de Graph son aditivos y prevalece el más
        permisivo (docs/04, aviso crítico). Configurar ambos a la vez es casi
        siempre un error, y silencioso, así que se rechaza al arrancar.
        """
        scopes = {s.rsplit("/", 1)[-1] for s in v.split() if s}
        broad = {"Files.Read.All", "Sites.Read.All", "Files.ReadWrite.All", "Sites.ReadWrite.All"}
        if "Sites.Selected" in scopes and (offenders := scopes & broad):
            raise ValueError(
                "Sites.Selected pierde su efecto restrictivo si se concede también "
                f"{sorted(offenders)}. Elige una de las dos opciones de docs/04 §2, no ambas."
            )
        return v

    def validate_runtime(self) -> None:
        """Comprobaciones que cruzan varios campos. Se llama al arrancar."""
        if self.log_document_content and self.app_env is not AppEnv.LOCAL:
            raise ValueError(
                "LOG_DOCUMENT_CONTENT=true solo se admite en APP_ENV=local. "
                "Registrar contenido de documentos corporativos fuera de local "
                "es una fuga de datos (docs/04 §4)."
            )
        if self.app_env is not AppEnv.LOCAL and not self.microsoft_configured:
            raise ValueError("Faltan AZURE_TENANT_ID / AZURE_API_CLIENT_ID fuera de local.")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    settings = Settings()
    settings.validate_runtime()
    return settings
