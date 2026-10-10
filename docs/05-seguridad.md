# 05 · Autenticación (diseño · **no implementado**)

> Estado: este documento es el diseño cerrado por requisito, pero **todavía no
> hay código**. El endpoint `/api/v1/sync/changes` está abierto y `device_id` es
> autodeclarado. No exponer a producción hasta implementar este módulo.
> En `backend/pom.xml` las dependencias de OAuth2 están declaradas pero
> comentadas a propósito, para que arrancar la app no exija un client-id real.

## Objetivo

Login con Google que emite **nuestros** JWT, con dos políticas de token según el
cliente:

| Cliente | Access token | Refresh token |
|---|---|---|
| Móvil (campo, conectividad intermitente) | 15 min | **~90 días, rotativo** → sesión perpetua |
| Web | 15 min | corto, con re-login razonable |

Un único `user_id` (UUID) es el dueño de los datos: `owner_id` de `terreno` y
`galpon` pasa a ser FK real contra la tabla `usuario`.

## Flujo

```
App ──(Google OAuth2 / id_token)──► Backend callback
Backend: verifica el id_token contra los JWKS de Google (iss, aud, exp, nonce)
        └─ upsert usuario por sub+email ─► emite par propio: access + refresh
App guarda ambos en almacenamiento seguro (Keychain / Keystore / flutter_secure_storage)
Requests a la API: Authorization: Bearer <access>
Access vencido ──► POST /auth/refresh <refresh>  (rotación: el usado se revoca)
```

Stack: `spring-boot-starter-oauth2-client` (login) +
`spring-boot-starter-oauth2-resource-server` (verificación de JWT propios).
Firmas RS256 con par propio; la clave pública se expone en `/oauth2/jwks` para
que en el futuro otros servicios validen sin llamar al server.

## Tablas propuestas

```sql
CREATE TABLE usuario (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         varchar(254) NOT NULL UNIQUE,
    nombre        varchar(150) NOT NULL,
    google_sub    varchar(120) UNIQUE,        -- subject estable de Google
    rol           varchar(30)  NOT NULL,      -- 'productor' | 'tecnico' | 'admin'
    created_at    bigint NOT NULL,
    updated_at    bigint NOT NULL,
    deleted       boolean NOT NULL DEFAULT false,
    deleted_at    bigint,
    version       bigint NOT NULL
);

CREATE TABLE refresh_token (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id     uuid NOT NULL REFERENCES usuario(id),
    token_hash     char(64) NOT NULL UNIQUE,  -- SHA-256: nunca el token en claro
    device_id      varchar(80) NOT NULL,      -- el refresh va ATADO al dispositivo
    expires_at     bigint NOT NULL,           -- epoch-millis
    revoked_at     bigint,
    replaced_by    uuid,                      -- cadena de rotación
    last_used_at   bigint,
    created_at     bigint NOT NULL,
    updated_at     bigint NOT NULL
);
CREATE INDEX idx_refresh_usuario ON refresh_token (usuario_id, expires_at);
```

`refresh_token` es **transaccional**, así que replica las convenciones del resto
del modelo (`created_at`/`updated_at` en millis, `version`). No es una entidad
sincronizable: vive solo en el servidor.

## Reglas de seguridad que hay que cumplir al implementarlo

1. **Rotación con detección de reuso.** Cada refresh emite un token nuevo y
   revoca el anterior. Si aparece un token ya revocado → robo probable: revocar
   toda la familia del `device_id` y forzar re-login con Google.
2. **Hash, no texto.** Se almacena SHA-256 del token. Una filtración de la tabla
   no debe permitir reproducir requests.
3. **`device_id` autodeclarado ya no vale.** Debe coincidir con el `device_id`
   del refresh token (o con una claim del access token). Mientras no se
   implemente, el sync endpoint acepta cualquier identidad: **no exponer**.
4. **El sync escribe en nombre del usuario del token.** `owner_id` se deriva del
   JWT, nunca del payload, para que un cliente no pueda plantar filas ajenas.
5. **TTL largo ≠ sin control.** El refresh de 90 días se corta con
   `revoked_at` en cambio de contraseña/cierre de sesión, y con expiración
   absoluta aunque el dispositivo siga en línea.
6. **Los tokens van en headers, nunca en query string** (quedan en logs). El
   `client_uuid` de una app offline no es secreto: sí lo es el refresh.

## Criterio de aceptación para cerrar este módulo

- Login Google → `POST /auth/token` devuelve `access_token` + `refresh_token`.
- `POST /auth/refresh` rota el token y revoca el usado.
- Reuso de un refresh revocado revoca la familia completa.
- `/api/v1/sync/**` responde `401` sin token y `owner_id` se deriva del JWT.
- Prueba de integración con `google-oauth2` mock (no contra cuentas reales).
