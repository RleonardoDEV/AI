# AI Project Manager Assistant

> Plataforma empresarial de inteligencia artificial para Project Management que utiliza la
> identidad corporativa del usuario para acceder de forma segura a la información autorizada
> de Microsoft 365, analiza documentos y datos de proyectos, proporciona un copiloto
> conversacional, calcula Project Health, predice riesgos de retraso, detecta Early Warnings
> y proporciona recomendaciones accionables basadas en evidencia.

**Estado actual: sprint 1 en curso.** La Fase 0 (análisis y diseño) está cerrada y las
decisiones bloqueantes, tomadas — quedan registradas en
[`docs/08`](docs/08-PREGUNTAS-ABIERTAS.md) §F.

Ya funciona, sin credenciales de Microsoft ni base de datos:

```bash
cd backend && python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/python -m app.cli demo     # ingesta → validación → Project Health con evidencias
.venv/bin/python -m pytest -q        # 91 tests
```

Ver [`docs/SETUP.md`](docs/SETUP.md).

---

## Qué es y qué no es

| Es | No es |
| --- | --- |
| Un **sistema de inteligencia de proyecto**: cálculo determinista + ML + RAG con trazabilidad | Un chatbot genérico sobre documentos |
| Un motor que **calcula** Health y probabilidad de retraso con código y modelos | Un LLM al que se le pide que "estime" un porcentaje |
| Un sistema que **respeta los permisos del usuario** en Microsoft 365 | Un índice global con acceso indiscriminado al tenant |
| Un complemento a Microsoft 365 Copilot | Un sustituto de Microsoft 365 Copilot |

## Principio rector

```
SEGURIDAD  >  CONTROL DE ACCESO  >  FIABILIDAD  >  TRAZABILIDAD  >  FUNCIONALIDAD  >  COMPLEJIDAD
```

Tres reglas que no se negocian en ninguna fase:

1. **La autorización nunca pasa por el LLM.** El filtrado por permisos ocurre en código,
   antes de construir el prompt. El modelo nunca decide a qué proyecto puede acceder.
2. **Los documentos son DATOS, no INSTRUCCIONES.** Ningún texto recuperado puede alterar
   el comportamiento del sistema.
3. **Ningún número sin procedencia.** Cada dato mostrado se etiqueta como
   `FACT` / `PREDICTION` / `INFERENCE` / `RECOMMENDATION` y lleva su evidencia asociada.

## Índice de documentación

| Documento | Contenido |
| --- | --- |
| [`docs/00-ANALISIS.md`](docs/00-ANALISIS.md) | Análisis de requisitos y **problemas técnicos reales detectados** |
| [`docs/01-COPILOT-VS-APP-PROPIA.md`](docs/01-COPILOT-VS-APP-PROPIA.md) | Comparación objetiva Copilot / app propia / extensión / híbrido |
| [`docs/02-ARQUITECTURA.md`](docs/02-ARQUITECTURA.md) | Arquitectura de referencia, flujos y componentes |
| [`docs/03-STACK-Y-DECISIONES.md`](docs/03-STACK-Y-DECISIONES.md) | Stack tecnológico y registro de decisiones (ADR) |
| [`docs/04-SEGURIDAD-Y-PERMISOS.md`](docs/04-SEGURIDAD-Y-PERMISOS.md) | Modelo de identidad, permisos mínimos de Graph, amenazas y controles |
| [`docs/05-ML-Y-ANALYTICS.md`](docs/05-ML-Y-ANALYTICS.md) | Health, Early Warning, ML por fases, What-If, explicabilidad, KPIs |
| [`docs/06-MVP-Y-ROADMAP.md`](docs/06-MVP-Y-ROADMAP.md) | Alcance del MVP y roadmap MVP / Future / Optional |
| [`docs/07-INSTALACION-IT-Y-DEV.md`](docs/07-INSTALACION-IT-Y-DEV.md) | Qué necesita IT, qué necesito yo, paso a paso |
| [`docs/08-PREGUNTAS-ABIERTAS.md`](docs/08-PREGUNTAS-ABIERTAS.md) | Decisiones bloqueantes, decisiones cerradas y contrato de datos canónico |
| [`docs/SETUP.md`](docs/SETUP.md) | Cómo ejecutar lo que ya está construido |

## Nota sobre fuentes

Todo lo relativo a Microsoft Graph, Microsoft Entra ID, SharePoint y Microsoft 365 Copilot
está contrastado contra documentación oficial de Microsoft Learn (agosto de 2026) y las URLs
están citadas en cada documento. Lo que **no** se ha podido verificar contra fuente oficial
está marcado explícitamente como `[VERIFICAR]`.
