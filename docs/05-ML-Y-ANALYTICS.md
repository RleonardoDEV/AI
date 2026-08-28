# 05 — Project Health, Early Warning, Machine Learning y What-If

---

## 1. Project Health — motor de reglas, no LLM

Ocho dimensiones, cada una con estado `GREEN / YELLOW / ORANGE / RED / UNKNOWN` y **razones
explícitas con su evidencia**. `UNKNOWN` es un estado de primera clase: si no hay datos
fiables, el sistema lo dice; nunca pinta verde por ausencia de datos.

| Dimensión | Señales de entrada | Fuente |
| --- | --- | --- |
| Schedule | tareas críticas retrasadas, desviación de fechas, hitos en riesgo, holgura | `Project Plan.xlsx` |
| Budget | consumido vs. planificado, proyección a cierre, desviación de horas | `Budget.xlsx` |
| Resources | disponibilidad, sobreasignación, ausencias, dependencia de persona clave | `Resources.xlsx` |
| Scope | cambios de alcance abiertos, requisitos sin aprobar | `Requirements.docx`, registro de cambios |
| Quality | incidencias abiertas, reaperturas, defectos por entrega | registro de incidencias |
| Dependencies | dependencias externas bloqueadas y antigüedad del bloqueo | `Project Plan.xlsx` |
| Customer | decisiones pendientes del cliente y su antigüedad, aprobaciones vencidas | actas + registro |
| **Overall** | agregación ponderada, con **regla de peor caso acotada** | calculado |

**Agregación.** No es una media aritmética: una media convierte un `RED` en `YELLOW` cuando
todo lo demás va bien, y eso oculta exactamente lo que hay que ver. La regla es:

```
overall = max( media_ponderada , peor_dimension - 1 nivel )
```

Es decir, si `Schedule` está en `RED`, el `Overall` no puede bajar de `ORANGE`.

**Ejemplo de salida del motor** (formato real de la respuesta):

```
Overall Health: ORANGE          (reglas v1.3.0 · calculado 2026-08-28T07:02Z)

Schedule: RED
  · 7 tareas críticas retrasadas          → Project Plan.xlsx!Tasks (7 filas)     [FACT]
  · 2 dependencias externas bloqueadas    → Project Plan.xlsx!Dependencies        [FACT]
  · 21 % de desviación en horas           → Budget.xlsx!Hours (planned vs actual) [FACT]

Resources: YELLOW
  · Disponibilidad prevista del equipo 82 %  → Resources.xlsx!Availability        [FACT]
  · Un recurso clave ausente 5 días          → Resources.xlsx!Absences            [FACT]
```

Cada regla tiene identificador, versión y umbrales **configurables en YAML**, no incrustados
en el código. Cuando cambia un umbral, `health_result` guarda con qué versión se calculó, de
modo que los resultados históricos siguen siendo interpretables.

---

## 2. Early Warning — detección de tendencia sobre snapshots

Una alerta no debe dispararse porque un valor es alto, sino porque **está empeorando**. Eso
requiere la serie temporal de `project_snapshot` (ADR-007).

Para cada métrica vigilada se calculan tres cosas:

| Indicador | Cálculo | Para qué |
| --- | --- | --- |
| Nivel | valor actual | ¿es grave ahora? |
| Delta | valor(t) − valor(t−1) | ¿ha empeorado esta semana? |
| Tendencia | pendiente de regresión lineal sobre 4 semanas + EWMA | ¿lleva empeorando? |

**Condición de disparo** (las tres a la vez, para evitar ruido):

```
tendencia_creciente_sostenida (≥ 3 semanas)
  AND  incremento_acumulado ≥ umbral_de_la_regla
  AND  nivel_actual ≥ umbral_mínimo_de_relevancia
```

Con la serie del encargo (20 % → 27 % → 41 % → 63 %), el sistema produce:

```
⚠️ EARLY WARNING · Project X · severidad: HIGH

El riesgo de retraso ha aumentado de forma sostenida durante las últimas tres semanas
(20 % → 27 % → 41 % → 63 %; +43 puntos).

Contribuyen principalmente:
  · tareas bloqueadas          +35 %  (4 → 7)     → Project Plan.xlsx      [FACT]
  · horas reales vs estimadas  +19 %              → Budget.xlsx            [FACT]
  · dependencia sin resolver   8 días             → Project Plan.xlsx      [FACT]

Origen del porcentaje: modelo baseline v0.4 (reglas calibradas)              [PREDICTION]
```

### Gobierno de alertas (evitar el spam)

| Mecanismo | Regla |
| --- | --- |
| **Umbrales** | Por regla y por severidad, en YAML versionado |
| **Severidad** | `INFO` (informativa) · `WARNING` (revisar esta semana) · `CRITICAL` (actuar ya) |
| **Deduplicación** | Clave `(project_id, rule_id, iso_week)`. Una alerta por regla y semana |
| **Cooldown** | 7 días por regla y proyecto. Solo se rompe si la severidad **sube** de banda |
| **Bandas de reactivación** | Se re-alerta al cruzar 40 % / 60 % / 80 %, no en cada punto porcentual |
| **Agregación** | Un solo resumen diario por proyecto, no un correo por señal |
| **Silenciado** | El PM puede silenciar una regla, con motivo y caducidad. Queda auditado |
| **Historial** | `alert_history` registra emitida / vista / reconocida / silenciada |

En Fase 1 las alertas solo se muestran en el dashboard. El envío a Outlook/Teams llega en
Fase 2, cuando ya se sepa la tasa de falsos positivos real.

---

## 3. Machine Learning — estrategia por fases

### 3.1 · Elección de modelo según los datos disponibles

La pregunta correcta no es "¿qué modelo es mejor?" sino "¿qué modelo es honesto con N
proyectos?".

| Proyectos cerrados y limpios | Enfoque | Modelo | Por qué |
| --- | --- | --- | --- |
| **< 50** | **Nada de ML** | Reglas calibradas por expertos | Cualquier modelo memoriza el nombre del PM. Un modelo con AUC 0,95 en 30 muestras es un modelo roto |
| **50 – 300** | ML simple | **Regresión logística regularizada (L2)** con 5–10 features + calibración | Pocos parámetros, coeficientes interpretables, funciona con N pequeño, se puede auditar coeficiente a coeficiente |
| **300 – 2.000** | Gradient boosting | **LightGBM** + **SHAP** | Captura no linealidades e interacciones; maneja categóricas nativamente; rápido de entrenar y reentrenar |
| **> 2.000** | Boosting afinado | LightGBM / XGBoost, con búsqueda de hiperparámetros | El volumen ya justifica el ajuste fino |
| Cualquier N | **Redes neuronales / Deep Learning** | ❌ **No** | Datos tabulares con N pequeño-medio: el boosting gana consistentemente, es más barato, más rápido y explicable. Deep learning aquí añadiría opacidad y coste sin ganancia |

**Por qué LightGBM antes que XGBoost o Random Forest**, cuando llegue el momento:
entrenamiento más rápido, menor consumo de memoria, soporte nativo de variables categóricas
(cliente, tecnología, PM) sin one-hot, y buen comportamiento con datos desbalanceados. Random
Forest sería una alternativa razonable y más robusta con muy poco ajuste, pero calibra peor
las probabilidades, y aquí la probabilidad *es* el producto.

**Y esto es lo importante:** la elección real para los próximos meses es la primera fila.
Con la información disponible, lo más probable es que no haya 50 proyectos históricos limpios.
Diseñamos para empezar sin ML y que el ML entre cuando los datos lo permitan, sin reescribir.

### 3.2 · Las cinco fases

| Fase | Qué produce | Datos que hace falta tener | Cómo se valida |
| --- | --- | --- | --- |
| **1 · Reglas + KPIs** | Health por dimensión, risk score determinista | Excel del proyecto actual bien mapeados | Revisión de un PM experto: ¿coincide con su juicio? |
| **2 · Analytics histórico** | Comparación con proyectos anteriores, distribuciones, líneas base por cliente y tecnología | ≥ 10–15 proyectos cerrados con fechas reales | ¿Las líneas base son estables? |
| **3 · ML supervisado** | Probabilidad de retraso aprendida | ≥ 50 proyectos cerrados **o** ≥ 500 snapshots semanales etiquetados | AUC, Brier, calibración vs. baseline de reglas |
| **4 · ML predictivo** | Rango de días de retraso + factores SHAP | Los anteriores + `actual_end` fiable | MAE/RMSE, cobertura del intervalo |
| **5 · Aprendizaje continuo** | Reentrenamiento y monitorización de deriva | Snapshots continuos + resultados reales | Deriva de features, degradación de métricas, reentrenar |

**Regla de oro entre fases:** el modelo de la fase N+1 solo sustituye al de la fase N si
**supera al baseline en datos que no ha visto**. Si LightGBM no mejora a las reglas, se sigue
con las reglas. Esto se evalúa, no se asume.

### 3.3 · Definición del objetivo (crítica)

Predecir "¿este proyecto se retrasará al cierre?" da **una muestra por proyecto**. Con 60
proyectos, 60 filas. Insuficiente.

Objetivo elegido: **"¿el próximo hito se entregará con más de N días de retraso?"**, evaluado
sobre cada snapshot semanal. Con 60 proyectos × 20 semanas se obtienen ~1.200 filas, es más
accionable para el PM, y es la pregunta que realmente importa cada lunes.

### 3.4 · Prevención de fuga de información (leakage)

Es el error que arruina estos modelos, y en el listado de features del encargo está presente:

| Feature del encargo | Problema | Cómo se usa correctamente |
| --- | --- | --- |
| `actual duration` | Solo se conoce al cerrar | Excluida de features; se usa para construir la etiqueta |
| `actual hours` | Válida "as-of" | Solo horas imputadas **hasta la semana t** |
| `delayed tasks` | Válida "as-of" | Retrasos conocidos **en la semana t** |
| `previous delays` | Válida | Retrasos de proyectos **anteriores** del mismo PM/cliente, cerrados antes de t |

Y en la validación:

- **Corte temporal**: entrenar con proyectos anteriores a una fecha, validar con posteriores.
- **`GroupKFold` por `project_id`**: los snapshots del mismo proyecto están muy
  correlacionados; si caen a los dos lados del split, la métrica sube y el modelo no sirve.
- **Baseline obligatorio**: siempre se compara contra la regla determinista y contra la tasa
  base. Un modelo que no bate a "el 40 % de los proyectos se retrasan" no se despliega.

### 3.5 · Datos sintéticos

Para probar el pipeline antes de tener histórico, se generará un dataset **sintético**
etiquetado sin ambigüedad:

- Fichero en `ml/data/synthetic/`, con `README` que empieza por
  **"DATOS SINTÉTICOS — NO SON DATOS REALES DE PROYECTOS"**.
- Columna `is_synthetic = true` en toda fila cargada en base de datos.
- El dashboard muestra un distintivo visible cuando hay datos sintéticos en juego.
- Los modelos entrenados con datos sintéticos llevan `model_version` con sufijo `-synthetic`
  y **no pueden desplegarse** en el modo de producción.

Los datos sintéticos sirven para validar que el código funciona. No sirven para afirmar nada
sobre proyectos reales, y el sistema no debe permitir confundir ambas cosas.

---

## 4. Explicabilidad

Un porcentaje sin explicación no se usa. Dos niveles:

**Fase 1–2 (reglas):** la explicación es la propia regla. La contribución de cada factor es
su peso configurado × su valor normalizado. Trivial de auditar.

**Fase 3–4 (ML):** **SHAP** (`TreeExplainer` sobre LightGBM), que reparte la predicción entre
las features de forma aditiva y con base teórica sólida.

```
Risk = 73 %                                     [PREDICTION · modelo v1.2.0]

Factores que más contribuyen (SHAP):
  · tareas bloqueadas          +18 pts
  · desviación de calendario   +21 pts
  · disponibilidad de recursos +12 pts
  · retraso de dependencia     +15 pts
  · (base del modelo)           38 %
```

Reglas de presentación, no negociables:
- Siempre se muestran el valor base y las 4–6 contribuciones principales.
- La contribución se expresa en la misma unidad que la salida (puntos de probabilidad), no en
  log-odds.
- Se muestran `model_version` y fecha de entrenamiento.
- Si la confianza del modelo es baja (pocos datos parecidos en el entrenamiento), se dice.

---

## 5. What-If — simulación, no predicción

**Qué NO se hace:** meter el escenario modificado en el modelo de ML y presentar el resultado
como predicción. El modelo no está entrenado para razonar sobre intervenciones; sería una
correlación disfrazada de causalidad.

**Qué se hace:** un simulador determinista sobre el plan.

```
"¿Qué pasa si retiro un desarrollador durante dos semanas?"

 1. Copiar el estado actual del proyecto (tareas, asignaciones, calendario)
 2. Aplicar la modificación: capacidad del recurso R = 0 en las semanas s..s+1
 3. Replanificar: reasignar carga, recalcular holgura y fechas de hitos
    (planificación por capacidad con la ruta crítica simplificada del plan)
 4. Recalcular las reglas de Health con el estado simulado
 5. Recalcular el risk score con las features simuladas
 6. Presentar la DIFERENCIA respecto a la línea base
```

Y se presenta así, con los supuestos a la vista:

```
ESCENARIO (simulación · no es una predicción)

Cambio: −1 desarrollador durante 2 semanas (semanas 36–37)

                        Actual          Escenario        Δ
Hito "UAT start"        18 sep          25 sep – 2 oct   +7 a +14 días
Carga del equipo        82 %            97 %             +15 pts
Schedule health         RED             RED              =
Risk score              68 %            79 %             +11 pts

Supuestos utilizados:
  · La carga se reparte entre los recursos restantes con el mismo perfil
  · No hay tareas paralelizables adicionales
  · Las dependencias externas no se mueven
  · Rango basado en la variabilidad histórica de replanificación (±40 %)

Esto es una simulación sobre el plan actual. No es una predicción del resultado real.
```

El rango, los supuestos explícitos y la etiqueta "simulación" son parte del contrato de la
funcionalidad, no adornos.

---

## 6. KPIs — cómo saber si el sistema aporta valor

### 6.1 · Calidad de las predicciones

| Métrica | Qué mide | Objetivo inicial |
| --- | --- | --- |
| AUC-ROC | Capacidad de ordenar proyectos por riesgo | > 0,70 (batir al baseline) |
| **Brier score** | **Calidad de la probabilidad** | Menor que el baseline. *Más importante que el AUC*: si el sistema dice 70 %, debe acertar ~7 de cada 10 |
| Curva de calibración | Fiabilidad de las probabilidades | Desviación < 10 puntos por decil |
| Precision / Recall / F1 | En el umbral de alerta | Recall > 0,70 con precisión > 0,50 |
| MAE / RMSE | Error en días de retraso estimados | MAE < 5 días |
| Falsos positivos | Alertas que no se materializaron | < 30 % de las alertas emitidas |
| Falsos negativos | Retrasos no anticipados | **< 20 %**. Es el error caro |
| **Early warning lead time** | Días de antelación del primer aviso | **> 14 días.** Es el KPI que justifica el proyecto |

### 6.2 · Valor para el negocio

| Métrica | Cómo se mide | Objetivo |
| --- | --- | --- |
| Reducción del tiempo de reporting | Cronometrar el informe semanal antes/después | −50 % |
| Reducción del tiempo de análisis | Tiempo hasta "sé qué pasa en mi proyecto" | de ~30 min a < 5 min |
| Adopción | Días activos por semana | ≥ 3/5 en el PoC |
| Satisfacción | Encuesta breve mensual (1–5) | ≥ 4,0 |
| Confianza en el dato | % de respuestas que el PM verifica manualmente | Decreciente en el tiempo |
| **Tasa de alucinación** | % de afirmaciones descartadas por el validador | < 2 %, y monitorizada |

### 6.3 · Cómo evaluar el PoC (4 semanas de uso real)

1. **Semana 0 — línea base.** El PM registra cuánto tarda hoy en preparar el estado semanal y
   escribe su valoración de riesgo "a mano" para 3 proyectos.
2. **Semanas 1–4 — uso en paralelo.** El sistema calcula su valoración cada semana. Nadie
   cambia decisiones basándose solo en él.
3. **Comparación ciega.** ¿Coincide el Health del sistema con el juicio del PM? Cuando no
   coincide, ¿quién tenía razón?
4. **Evaluación del RAG.** 30 preguntas con respuesta conocida → medir exactitud, presencia de
   citas correctas y, especialmente, **cuántas veces responde "no lo sé" cuando debía**.
5. **Criterio de éxito del PoC** (definido *antes* de empezar):
   - ≥ 80 % de las respuestas fácticas correctas y con cita válida.
   - 0 casos de acceso a información no autorizada.
   - ≥ 1 problema real detectado antes de lo que se habría detectado sin el sistema.
   - Reducción medible del tiempo de reporting.
