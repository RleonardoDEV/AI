# 01 — Microsoft Copilot vs. aplicación propia

> Objetivo: no duplicar lo que Microsoft ya resuelve bien, y no delegar en Microsoft lo que
> Microsoft no puede hacer.

---

## 1. Primero, una distinción que cambia toda la evaluación

En el encargo se dice "los usuarios tienen acceso a Microsoft Copilot". Eso puede significar
dos cosas **muy** distintas, y la decisión técnica depende de cuál sea:

| | **Microsoft Copilot Chat** | **Microsoft 365 Copilot** (licencia de pago) |
| --- | --- | --- |
| Cómo se obtiene | Incluido con cualquier suscripción Microsoft 365 | Licencia por usuario (add-on de E3/E5, o incluida en E7) |
| Grounding | **Solo web** | Web **y** datos de trabajo vía Microsoft Graph |
| Acceso a tus SharePoint/OneDrive | No, salvo que subas el fichero a mano | Sí, respetando permisos |
| ¿Habilita la Retrieval API? | No | **Sí** |

Fuente: [Overview of Microsoft Copilot Chat](https://learn.microsoft.com/copilot/overview#differences-between-copilot-chat-and-microsoft-365-copilot),
[Which Copilot is right for me or my organization?](https://learn.microsoft.com/microsoft-365/copilot/which-copilot-for-your-organization),
[Copilot Chat FAQ](https://learn.microsoft.com/copilot/faq#general).

Textualmente: *"If a user doesn't have a Microsoft 365 Copilot license, Copilot Chat can't
access the user's shared enterprise data, individual data, or external data indexed via
Microsoft Graph connectors."*

**Esta es la pregunta bloqueante nº 1 del proyecto** (ver `docs/08`). Con licencia completa
tenemos acceso a la Retrieval API y a la Chat API; sin ella, el RAG tiene que ser propio.

Existe una vía intermedia: la Retrieval API en modalidad **Pay-as-you-go** para usuarios sin
licencia Copilot. Se habilita en el Centro de administración de Microsoft 365 vinculando una
suscripción de Azure, y **solo cubre fuentes a nivel de tenant (SharePoint y Copilot
connectors); OneDrive queda excluido**
([Terms of Use, preview](https://learn.microsoft.com/legal/m365-retrieval-paygo-tou/paygo-retrieval-terms)).

---

## 2. Las cuatro opciones, evaluadas

### Opción A — Usar Microsoft 365 Copilot directamente

**Qué haría bien.** Resumir reuniones, buscar en correo y documentos, "¿qué pasó estas dos
semanas?", redactar. Es un producto maduro, con gobernanza, auditoría, Purview y respeto de
permisos incorporados. No hay que construir ni mantener nada.

**Qué no puede hacer, por diseño.**
- No calcula un Project Health reproducible. Preguntar dos veces puede dar dos respuestas.
- No entrena ni ejecuta modelos de ML sobre datos históricos propios.
- No mantiene series temporales semanales → no hay detección de tendencia ni Early Warning.
- No hay alertas proactivas (los agentes declarativos no soportan interacciones proactivas;
  [comparativa](https://learn.microsoft.com/microsoft-365/copilot/extensibility/agents-overview#choose-what-type-of-agent-to-build)).
- No hay dashboard de cartera de proyectos.
- No distingue `FACT` / `PREDICTION` / `INFERENCE` de forma estructurada y auditable.

**Veredicto:** imprescindible como herramienta, insuficiente como sistema. No cubre los
módulos 2, 3 y 4, que son el núcleo del encargo.

### Opción B — Aplicación propia (Microsoft Graph + OpenAI)

**Qué haría bien.** Todo lo que Copilot no hace: cálculo determinista, ML, snapshots,
tendencias, alertas, dashboard, trazabilidad estructurada, What-If, integración futura con
Jira/DevOps/Planon/TRIRIGA.

**Coste real.** Hay que construir y mantener autenticación, autorización, sincronización de
permisos, índice, ingesta, observabilidad y defensas contra inyección. Es donde está el 80 %
del riesgo del proyecto y el 100 % de la responsabilidad de seguridad: *"Must ensure your own
compliance, RAI practices, and security measures"*
([agents overview](https://learn.microsoft.com/microsoft-365/copilot/extensibility/agents-overview#choose-what-type-of-agent-to-build)).

**Veredicto:** necesaria. Es la única opción que cubre los módulos 2, 3 y 4.

### Opción C — Extensión de Copilot (agente declarativo / agente de SharePoint / connector)

**Qué haría bien.** Coste de construcción bajísimo. Hereda toda la seguridad, gobernanza y
cumplimiento de Microsoft 365. Se puede crear incluso sin código desde SharePoint o desde
Agent Builder ([herramientas](https://learn.microsoft.com/microsoft-365/copilot/extensibility/declarative-agent-tool-comparison)).

**Límites.** Está *"limited to Copilot's orchestrator and models"*: no puedes meter tu motor
de reglas, ni tu modelo de ML, ni tu simulador What-If dentro del agente declarativo. Sin
interacciones proactivas. Requiere licencia Copilot.

**Veredicto:** excelente **canal**, insuficiente como **motor**.

### Opción D — Ambos, con reparto explícito de responsabilidades ✅ RECOMENDADA

Construimos el motor (Opción B) y, cuando exista, lo exponemos también dentro de Copilot
(Opción C) como *custom engine agent* o agente declarativo con acción de API, para que el PM
pregunte desde Teams sin cambiar de herramienta.

---

## 3. Reparto de responsabilidades recomendado

| Tarea | Quién la hace | Por qué |
| --- | --- | --- |
| "Resume las últimas reuniones" | **Microsoft 365 Copilot** | Ya lee Teams/Outlook con permisos y gobernanza. Duplicarlo es tirar esfuerzo |
| "Redacta el correo al cliente sobre el retraso" | **Copilot** | Redacción en el contexto de Outlook |
| "Busca ese documento del que hablamos" | **Copilot** | Búsqueda empresarial madura |
| **Project Health por dimensión, con razones** | **App propia** | Requiere cálculo determinista y auditable sobre datos tabulares |
| **Probabilidad de retraso y días estimados** | **App propia** | Requiere modelo estadístico entrenado con histórico propio |
| **Early Warning y tendencia semanal** | **App propia** | Requiere serie temporal persistida. Copilot no la tiene |
| **Dashboard de cartera** | **App propia** | Copilot no es una herramienta de visualización |
| **What-If sobre el plan** | **App propia** | Requiere simulación sobre el modelo de datos |
| **Alertas proactivas a Outlook/Teams** | **App propia** | Los agentes declarativos no soportan proactividad |
| **Trazabilidad FACT/PREDICTION/INFERENCE** | **App propia** | Requiere contrato de salida estructurado y validado |
| **Recuperación de texto de documentos** | **Ambos** (`RetrievalProvider`) | Retrieval API si hay licencia; pgvector si no |

**Regla de oro:** si la respuesta correcta es *un número que debe ser el mismo mañana*, la
calcula la app propia. Si es *un texto que resume información dispersa*, puede hacerlo Copilot.

---

## 4. Consecuencia de diseño: `RetrievalProvider` como interfaz

Del análisis anterior sale una de las decisiones estructurales del proyecto
(ADR-003 en `docs/03`). El backend define **una** interfaz de recuperación:

```python
class RetrievalProvider(Protocol):
    async def search(
        self,
        *,
        user: UserPrincipal,        # identidad del llamante, siempre presente
        project: Project,           # ya validado como autorizado para este usuario
        query: str,
        top_k: int = 8,
    ) -> list[Evidence]: ...
```

Dos implementaciones intercambiables por variable de entorno:

- **`M365RetrievalProvider`** → `POST /v1.0/copilot/retrieval` con el token OBO del usuario,
  usando `filterExpression` (KQL) para acotar la búsqueda a la ruta del sitio del proyecto.
  Cero copia de datos, permisos y etiquetas de sensibilidad respetados por Microsoft.
  > Aviso de la documentación: *si el `filterExpression` tiene sintaxis KQL incorrecta, la
  > consulta se ejecuta **sin ningún filtro** en lugar de fallar*. Hay que validar el KQL en
  > el código antes de enviarlo — un error de sintaxis convertiría una búsqueda acotada a un
  > proyecto en una búsqueda sobre todo lo que el usuario puede ver.
- **`LocalVectorProvider`** → pgvector, con las mitigaciones de P1 (verificación de acceso en
  el momento de responder, delta sync, purga, filtrado por etiqueta).

Coste de la abstracción: bajo. Beneficio: la decisión de licencias deja de ser bloqueante
para empezar a construir, y el sistema puede migrar de una a otra sin reescribirse.

---

## 5. Camino futuro hacia la integración en Copilot (Fase 3+)

Cuando el motor esté validado, la interfaz natural para el resto de PMs no es "otra web más",
es Teams. Dos vías, ambas documentadas:

1. **Agente declarativo con acción de API**: expone endpoints del backend
   (`get_project_health`, `get_delay_prediction`, `list_early_warnings`) como acciones.
   Barato, hereda la gobernanza de Copilot. Requiere licencia Copilot.
2. **Custom engine agent** (Microsoft 365 Agents SDK): nuestra orquestación y nuestros
   modelos, publicado en Copilot/Teams. Más control, más responsabilidad de cumplimiento
   ([overview](https://learn.microsoft.com/microsoft-365/copilot/extensibility/overview-custom-engine-agent)).

No se implementa ahora. Pero el backend se diseña con endpoints limpios y tipados
precisamente para que esa integración sea un envoltorio, no una reescritura.
