# 07 — Qué necesita IT y qué necesito yo

Respuesta directa a las preguntas del apartado 20 del encargo.

---

## 1. Respuestas rápidas

| Pregunta | Respuesta para el PoC |
| --- | --- |
| ¿Necesito Azure? | **No.** El PoC funciona entero en tu portátil. Azure es necesario en Fase 3 (multiusuario) |
| ¿Necesito una App Registration? | **Sí. Dos**: una para el frontend (SPA) y otra para el backend (API) |
| ¿Necesito permisos de administrador? | **Tú no. IT sí**, para dar consentimiento a los permisos de Graph y conceder el sitio |
| ¿Necesito base de datos? | **Sí**: PostgreSQL con pgvector, en Docker, en tu máquina |
| ¿Dónde se almacenan los embeddings? | En esa misma base de datos (extensión `pgvector`). Si se usa la Retrieval API, **no se almacena nada** |
| ¿Dónde se ejecuta el backend? | `localhost:8000` (contenedor Docker en tu portátil) |
| ¿Dónde se ejecuta el frontend? | `localhost:3000` (contenedor Docker en tu portátil) |
| ¿Salen datos corporativos de mi equipo? | Solo los **extractos** enviados al modelo de lenguaje. Nada más. Los ficheros no se copian a ningún sitio externo |

---

## 2. Lo que necesito pedir a IT

Lista lista para enviar por correo o abrir como ticket.

### 2.1 · App Registrations en Microsoft Entra ID

**Registro A — `AI PM Assistant – Web` (frontend)**
- Tipo: **Single-page application (SPA)**
- Redirect URI: `http://localhost:3000` *(en producción, la URL real)*
- Sin secreto de cliente (un SPA no debe tenerlo)
- Cuentas admitidas: **solo este directorio organizativo** (single tenant)

**Registro B — `AI PM Assistant – API` (backend)**
- Tipo: **Web / API** (cliente confidencial)
- *Expose an API*: URI `api://<client-id-de-B>`, con el scope `access_as_user`
- *Authorized client applications*: añadir el **client-id del Registro A** para el scope
  `access_as_user` (esto es lo que permite el consentimiento combinado del flujo OBO)
- Credencial: **certificado preferido**; secreto de cliente aceptable para el PoC, con
  caducidad ≤ 6 meses
- Cuentas admitidas: **solo este directorio organizativo**

### 2.2 · Permisos de Microsoft Graph y consentimiento de administrador

Elegir **una** de las dos opciones (son excluyentes, ver `docs/04` §2):

**Opción 1 — recomendada para empezar**

| Permiso | Tipo | ¿Consentimiento admin? |
| --- | --- | --- |
| `User.Read` | Delegado | No |
| `offline_access` | Delegado | No |
| `Sites.Selected` | Delegado | **Sí** |

Y además, la concesión explícita del sitio del PoC:

```http
POST https://graph.microsoft.com/v1.0/sites/{siteId}/permissions
{ "roles": ["read"],
  "grantedToIdentities": [{ "application": { "id": "<client-id-de-B>",
                                             "displayName": "AI PM Assistant – API" } }] }
```

**Opción 2 — solo si se va a usar la Retrieval API de Copilot**

| Permiso | Tipo | ¿Consentimiento admin? |
| --- | --- | --- |
| `User.Read`, `offline_access` | Delegado | No |
| `Files.Read.All` | Delegado | **Sí** |
| `Sites.Read.All` | Delegado | **Sí** |

> ⚠️ **No pedir las dos opciones a la vez.** `Files.Read.All` anula el efecto restrictivo de
> `Sites.Selected`.

**Nunca se solicitan** permisos de aplicación, ni `*.ReadWrite*`, ni `Sites.FullControl.All`.

### 2.3 · Confirmaciones que necesito de IT

1. **Licenciamiento de Copilot**: ¿Microsoft 365 Copilot (de pago) o solo Copilot Chat?
   Determina si podemos usar la Retrieval API.
2. **Acceso Condicional**: ¿hay políticas que exijan dispositivo conforme o MFA para
   SharePoint? Determina si hay que implementar `claims challenge` (P11).
3. **OpenAI empresarial**: organización y proyecto asignados, clave gestionada por IT,
   condiciones de retención (¿ZDR?) y región. O bien, si se prefiere **Azure OpenAI**, un
   recurso en la región adecuada.
4. **Etiquetas de sensibilidad**: nivel máximo que el sistema puede procesar.
5. **Sitio de SharePoint del PoC**: URL exacta y confirmación de que puedo usar sus datos.
6. **Registro de la aplicación** en el inventario corporativo, con propietario asignado.
7. **DPIA/EIPD**: ¿es necesaria? El sistema procesa nombres de empleados y asignaciones.

### 2.4 · Lo que IT NO tiene que hacer para el PoC

- No hace falta suscripción de Azure.
- No hace falta abrir puertos ni publicar nada en Internet.
- No hace falta modificar permisos de SharePoint existentes.
- No hace falta instalar nada en el servidor: todo corre en local.
- No hace falta conceder permisos administrativos a mi cuenta.

---

## 3. Lo que instalo yo, en mi portátil

| Software | Versión | Para qué |
| --- | --- | --- |
| **Python** | 3.12+ | Backend y ML |
| **uv** o **pip + venv** | reciente | Gestión de dependencias |
| **Node.js** | 20 LTS o 22 | Frontend Next.js |
| **Docker Desktop** | reciente | PostgreSQL + pgvector, y empaquetado de la app |
| **Git** | 2.40+ | Control de versiones |
| **VS Code** | reciente | Editor (extensiones Python, Pylance, ESLint) |
| **Azure CLI** *(opcional)* | reciente | Cómodo para consultar Entra ID |
| **Microsoft Graph Explorer** | web | Probar llamadas a Graph antes de programarlas |

Nada de esto requiere permisos de administrador si la empresa permite Docker Desktop. Si
Docker Desktop no está permitido, alternativas: PostgreSQL instalado nativamente con la
extensión `pgvector`, o Podman.

### Puesta en marcha (cuando exista el código)

```bash
git clone <repo> && cd ai-project-manager-assistant
cp .env.example .env          # rellenar con los IDs que dé IT — nunca se sube a Git
docker compose up -d db       # PostgreSQL 16 + pgvector
cd backend && uv sync && alembic upgrade head && uvicorn app.main:app --reload
cd frontend && npm install && npm run dev
# abrir http://localhost:3000
```

---

## 4. Dónde vive cada cosa

### PoC (ahora)

```
Tu portátil corporativo (cifrado)
├── Docker
│   ├── PostgreSQL + pgvector   ← datos de proyecto, chunks, embeddings, audit
│   ├── Backend FastAPI         ← :8000
│   └── Frontend Next.js        ← :3000
└── .env                        ← IDs de cliente y claves (fuera de Git)

Fuera de tu portátil salen únicamente:
  · Llamadas a Microsoft Graph  (datos corporativos, dentro del tenant)
  · Llamadas al proveedor LLM   (SOLO los extractos necesarios para la respuesta)
```

### Producción (Fase 3, cuando haya varios usuarios)

```
Azure Container Apps            ← backend + frontend, con identidad administrada
Azure Database for PostgreSQL   ← Flexible Server, con pgvector
Azure Key Vault                 ← secretos y claves
Azure Monitor / App Insights    ← logs y métricas (sin contenido de documentos)
Azure OpenAI (DataZone EU) o OpenAI Platform empresarial
```

---

## 5. Coste estimado del PoC

| Concepto | Coste |
| --- | --- |
| Infraestructura | **0 €** (todo local) |
| App Registration en Entra ID | **0 €** (incluido en M365) |
| Microsoft Graph | **0 €** (incluido; sujeto a límites de throttling) |
| Retrieval API de Copilot | Requiere licencia Copilot ya existente, **o** PAYG (consumo) |
| LLM (embeddings + generación) | **Decenas de euros/mes** con un usuario y unos pocos proyectos |
| Mi tiempo | 6 semanas a dedicación parcial |

El coste dominante del PoC es el tiempo, no la infraestructura. Ese es precisamente el motivo
de hacerlo local: para poder equivocarse barato antes de pedir presupuesto.
