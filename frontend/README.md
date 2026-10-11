# frontend

Clientes de AgrocuyesOS.

| Cliente | Estado | Dónde |
|---|---|---|
| Móvil (Flutter) | **Andamiado**: escrito contra el contrato de sync, todavía **sin compilar** (falta toolchain y codegen de Drift) | [`mobile/`](mobile/) |
| Web | Sin código | — |

## Móvil

`Flutter · Riverpod · Drift (SQLite) · Dio · google_sign_in`, offline-first.
Arquitectura feature-first, esquema local, cola de cambios LWW y reglas de UI de
rural: [`../docs/08-cliente-movil.md`](../docs/08-cliente-movil.md).

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # genera app_database.g.dart
flutter test
flutter run --dart-define=AGROCUYES_API=http://<ip-del-server>:8080
```

## Reglas que ya aplicaban, independientes del stack

- El contrato del API está en [`../docs/04-api.md`](../docs/04-api.md).
- Las reglas del cliente offline (cola de cambios, `updated_at` local, manejo de
  `STALE` / `REJECTED_DELETED`, deriva de reloj contra `server_timestamp`) están
  en [`../docs/03-sincronizacion.md`](../docs/03-sincronizacion.md).
- El endpoint de sync **no está autenticado**: no exponer a producción hasta
  cerrar [`../docs/05-seguridad.md`](../docs/05-seguridad.md).
