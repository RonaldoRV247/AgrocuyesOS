# 08 · Cliente móvil (Flutter)

App de campo para productores: luz solar directa, manos ocupadas, señal
intermitente y sesiones que no se cierran. Vive en [`frontend/mobile/`](../frontend/mobile/).

> **Estado honesto**: el código está escrito y es coherente con el contrato del
> backend, pero **no se compiló todavía** — la máquina donde se redactó no tiene
> toolchain de Flutter/Dart. Hay que correr `flutter pub get`,
> `dart run build_runner build` (genera `app_database.g.dart`) y
> `flutter analyze` antes de dar nada por bueno. Sin ese paso el proyecto **no
> compila**, porque Drift necesita su codegen.

## Stack y por qué

| Elección | Motivo | Alternativa descartada |
|---|---|---|
| **Drift** (SQLite) | Tipos generados desde el esquema, `watch()` reactivo, transacciones reales. Es el espejo natural del modelo relacional del server. | Isar/Realm: más rápidos, pero sin SQL para expresar el outbox y sin equivalencia con el DDL de Flyway. |
| **Riverpod** | La reactividad nace de los streams de BD, no de `setState`: escribir un registro actualiza la lista sin recargar nada. Los providers hacen la inyección explícita y testeable. | BLoC para un CRUD de dos pantallas: más boilerplate por evento. Provider/e_state: sin composición entre streams de BD y casos de uso. |
| **Dio** | Interceptor para el `Bearer` resuelto por request (un refresh en vuelo se ve en la siguiente subida). | `http`: habría que rehacer el manejo de tokens y timeouts. |
| **Feature-first + capas adentro** | `features/x/domain` no importa Flutter ni Drift; `data/` es el único que toca SQLite/HTTP. Es la misma regla de dependencia del backend (ver [01](01-arquitectura.md)). | Capas horizontales (`lib/models`, `lib/services`): al tercer módulo nadie sabe qué puede importar qué. |

## Estructura

```
frontend/mobile/
├── pubspec.yaml                  # drift, riverpod, uuid, google_sign_in, secure_storage, dio, connectivity_plus
├── analysis_options.yaml
├── test/tarea_config_test.dart   # contrato dinámico: se puede correr sin codegen
└── lib/
    ├── main.dart                 # ProviderScope + bootstrap + navegación de pulgar
    ├── core/                     # transversal, sin dominio
    │   ├── demo/semilla.dart         # catalogo de arranque (mismo formato que el pull)
    │   ├── theme/campo_theme.dart    # contraste + CONSTANTES de 60/72/112dp
    │   ├── theme/iconos_campo.dart   # "aporque" -> IconData (el dominio no importa Flutter)
    │   ├── utils/tiempo.dart         # UUIDv4 + RelojCampo (epoch-millis con deriva)
    │   └── widgets/                  # StepperCampo, EstadoVacio
    ├── shared/
    │   ├── di/inyeccion.dart         # baseDeDatosProvider, relojProvider, cola
    │   ├── di/config.dart            # kBaseUrl (--dart-define), margen de refresco
    │   └── data/local/
    │       ├── tablas.dart           # esquema Drift (spec de columnas)
    │       └── app_database.dart     # queries + escritura de negocio + outbox
    └── features/
        ├── tareas/
        │   ├── domain/   tarea_config.dart · actividad.dart · tareas_repositorio.dart   ← PUERTO
        │   ├── data/     tareas_repositorio_local.dart                                   ← ADAPTADOR Drift
        │   ├── application/ tareas_providers.dart
        │   └── presentation/ boton_tarea_gigante.dart · cuadrilla_tareas.dart · hoja_tarea.dart
        ├── crianza/  {domain-less: data/ + application/ + presentation/vista_pozas.dart}
        ├── sync/     data/api_sync.dart · application/sync_worker.dart · sync_providers.dart
        └── auth/     data/auth_repositorio.dart · application/auth_providers.dart
```

Regla que sostiene el conjunto: un `features/*/presentation` solo conoce
`application` (providers) y `domain`. Drift, Dio y `google_sign_in` aparecen
únicamente en `data/` y `shared/data/`.

## Esquema local ↔ server

`tablas.dart` es espejo de `V1__sync_core.sql`, con tres diferencias deliberadas:

| Aspecto | PostgreSQL | Drift/SQLite | Por qué |
|---|---|---|---|
| Nombres | snake_case | Dart camelCase + `.named('snake_case')` | El payload del SyncWorker sale del snapshot: no hay mapa de traducción que se oxide |
| `metadata` | `jsonb` + GIN | TEXT con JSON | SQLite no indexa por contenido; la búsqueda por clave la hace el server y la pantalla de campo filtra por terreno/fecha |
| FK | `DEFERRABLE INITIALLY DEFERRED` | **sin** restricción, referencia lógica | En el dispositivo el padre puede llegar después que el hijo (pull delta aún no existe) |
| `client_uuid` | columna aparte con UNIQUE | no se duplica: `id` es el client_uuid | `RegistroActividad.crear` ya hace `clientUuid = getId()` |
| — | — | `cambio_pendiente` (outbox) | cola local, no sincronizable |
| — | — | `estado_sync` (watermark, device_id, deriva) | estado del protocolo |

`registro_actividad` lleva además `plantilla_nombre` (desnormalizado: la lista de
hoy tiene que decir "Aporque" aunque el catálogo cambie) y `sincronizado_en`
(null ⇒ badge ámbar "sin sincronizar"; no participa en el arbitraje).

## Cola de cambios (outbox) y LWW del lado cliente

Se encola en la **misma transacción** que la fila de negocio: no puede existir un
registro guardado que no esté en cola. El payload es el **snapshot del momento
del encolado**, por eso la cola es una tabla aparte y no un flag en cada fila:
si el productor edita mientras hay una subida en vuelo, la respuesta del server
no puede confundirse con lo que ya se envió. Reencolar el mismo registro
reemplaza el cambio anterior (el server reemplaza el payload completo, no lo
parchea).

Qué hace el `SyncWorker` con cada status (ver [04](04-api.md)):

| Status | Acción del cliente |
|---|---|
| `INSERTED` / `APPLIED` / `TOMBSTONED` / `DUPLICATE` | sale de la cola + `sincronizado_en = server_updated_at` |
| `STALE` / `REJECTED_DELETED` | sale de la cola **y adopta `server_payload`** en la fila local (descartar sin adoptar dejaría al cliente convergiendo a ciegas) |
| `REJECTED` | se queda pendiente, se registra el estado; tras 8 intentos se abandona y se avisa (reintentar un payload inválido igual es gastar batería) |
| `DioException` sin respuesta | la cola no se toca, `SIN_RED`, backoff exponencial 15s → 10min |

Cada respuesta con `server_timestamp` recalibra `RelojCampo`: todos los
`updated_at` de la app salen de esa instancia, nunca de `DateTime.now()`, para
que un reloj adelantado no gane todos los LWW (el server rechaza más de
`max-clock-skew-ms` = 5 min).

## Autenticación

Google Sign-In con sesión persistente estilo WhatsApp: se guarda el par
access/refresh en Keychain/Keystore (`flutter_secure_storage`), al abrir la app
`restaurarSesion()` reusa lo guardado y solo refresca si el access está a
<2 min de vencer. **Si el refresh falla por falta de red, la sesión se conserva
y la captura de datos sigue funcionando**: auth es requisito del *sync*, no del
registro en campo.

⚠️ El backend aún no implementa `/auth/token` ni `/auth/refresh`
([05](05-seguridad.md)); el cliente responde `AuthSinImplementarException` y
sigue operando offline. No exponer `/api/v1/sync/changes` hasta cerrar ese módulo.

## Reglas de UI de rural (no negociables en review)

* **Piso táctil de 60dp** (`kTouchMin`); default real **72dp**, botón de tarea
  **112dp**. No existe widget háptico por debajo del piso.
* **Cero teclado**: `entero`/`decimal` → stepper con aceleración por mantenido;
  `seleccion` → tokens de 60dp; `booleano` → SI/NO gigantes. `texto` es la
  excepción declarada por el catálogo, no el camino.
* **Contraste calculado, no elegido**: el server manda colores arbitrarios y el
  foreground se decide por luminancia (`computeLuminance() > 0.45` ⇒ texto
  oscuro). Así cualquier plantilla nueva sale legible bajo el sol.
* **Feedback háptico en cada paso** (`lightImpact` al contar, `heavyImpact` al
  guardar): el productor no mira la pantalla para saber si registró.
* **El ámbar nunca es error**: "sin sincronizar" es estado normal en campo; rojo
  se reserva a mortandad y rechazos del server.

## Correrlo

```bash
cd frontend/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # genera app_database.g.dart
flutter test                                                # contrato dinámico
flutter analyze
flutter run -d <device> --dart-define=AGROCUYES_API=http://192.168.x.x:8080
```

Para Google Sign-In hacen falta `google-services.json` (Android) y
`GoogleService-Info.plist` (iOS) + el client-id en `application.properties` del
backend; hoy la app funciona sin eso (modo offline puro con semilla local).

## Pendiente del cliente

- [ ] Verificar build real (`pub get` + codegen + analyze) y cerrar lints.
- [ ] `GET /sync/changes?since=` en cuanto el backend lo publique: el cliente ya
      tiene watermark en `estado_sync` y el outbox listo.
- [ ] Pruebas de contrato del SyncWorker contra un server en memoria (status por
      status, incluida la adopción de `server_payload`).
- [ ] Plantillas con `dominio: crianza` renderizadas en la vista de poza (hoy el
      repositorio tiene `registrarEvento` genérico, la UI todavía no lo usa).
- [ ] Prueba de campo en 3G/2G real y a plena luz (fotografiar la pantalla y
      medir legibilidad, no confiar en el ratio teórico).
