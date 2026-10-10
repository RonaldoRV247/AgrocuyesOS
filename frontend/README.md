# frontend

Clientes (móvil y web) todavía **sin código**. El framework está por decidir
(Flutter / React Native / web + PWA): ver
[`../docs/07-roadmap.md`](../docs/07-roadmap.md), Fase 3.

Lo que ya les aplica hoy, independentemente del stack:

- El contrato del API está en [`../docs/04-api.md`](../docs/04-api.md).
- Las reglas del cliente offline (cola de cambios, `updated_at` local, manejo de
  `STALE` / `REJECTED_DELETED`, deriva de reloj contra `server_timestamp`) están
  en [`../docs/03-sincronizacion.md`](../docs/03-sincronizacion.md).
