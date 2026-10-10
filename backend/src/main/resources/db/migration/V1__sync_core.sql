-- =============================================================================
-- AgrocuyesOS :: V1 :: nucleo Offline-First + LWW
-- PostgreSQL 13+ (gen_random_uuid() es nativo desde esa version)
--
-- Convenciones de este esquema:
--   * PK uuid generadas por el CLIENTE. El default existe solo para altas
--     nacidas en el server (web / seeds); la app offline siempre manda su uuid.
--   * created_at / updated_at como BIGINT epoch-millis UTC. No TIMESTAMPTZ:
--     LWW necesita comparar en la misma unidad y formato que usa el dispositivo,
--     sin conversiones de zona horaria en el camino.
--   * deleted/deleted_at: tombstones. Borrar es un estado replicable.
--   * version: contador de ciclo de vida de JPA (transient vs detached con PK
--     asignada). NO participa en la resolucion de conflictos: ese es updated_at.
--   * metadata/detalles JSONB: catalogo dinamico, preparado para ingesta IA.
--   * FK DEFERRABLE: un lote de sync puede traer al hijo antes que al padre;
--     la restriccion se verifica al COMMIT del batch, no por sentencia.
-- =============================================================================

CREATE TABLE terreno (
    id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre        varchar(150) NOT NULL,
    area_m2       double precision,
    lat           double precision,
    lng           double precision,
    owner_id      uuid         NOT NULL,  -- FK a usuarios: llega con el modulo de auth
    created_at    bigint       NOT NULL,
    updated_at    bigint       NOT NULL,
    deleted       boolean      NOT NULL DEFAULT false,
    deleted_at    bigint,
    version       bigint       NOT NULL
);

CREATE TABLE plantilla_proceso (
    id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre        varchar(120) NOT NULL,
    metadata      jsonb        NOT NULL DEFAULT '{}'::jsonb,
    activo        boolean      NOT NULL DEFAULT true,
    created_at    bigint       NOT NULL,
    updated_at    bigint       NOT NULL,
    deleted       boolean      NOT NULL DEFAULT false,
    deleted_at    bigint,
    version       bigint       NOT NULL
);

CREATE TABLE registro_actividad (
    id               uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid      uuid      NOT NULL,
    terreno_id       uuid      NOT NULL,
    plantilla_id     uuid      NOT NULL,
    fecha_realizada  date      NOT NULL,
    metadata         jsonb     NOT NULL DEFAULT '{}'::jsonb,
    created_at       bigint    NOT NULL,
    updated_at       bigint    NOT NULL,
    deleted          boolean   NOT NULL DEFAULT false,
    deleted_at       bigint,
    version          bigint    NOT NULL,

    CONSTRAINT fk_registro_terreno
        FOREIGN KEY (terreno_id) REFERENCES terreno (id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_registro_plantilla
        FOREIGN KEY (plantilla_id) REFERENCES plantilla_proceso (id)
        DEFERRABLE INITIALLY DEFERRED,
    -- El uuid del dispositivo es la clave de idempotencia del sync.
    CONSTRAINT uq_registro_client_uuid UNIQUE (client_uuid)
);

CREATE TABLE galpon (
    id                uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre            varchar(150) NOT NULL,
    capacidad_maxima  integer,
    owner_id          uuid      NOT NULL,
    created_at        bigint    NOT NULL,
    updated_at        bigint    NOT NULL,
    deleted           boolean   NOT NULL DEFAULT false,
    deleted_at        bigint,
    version           bigint    NOT NULL
);

CREATE TABLE poza (
    id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    galpon_id   uuid          NOT NULL,
    codigo      varchar(40)   NOT NULL,
    hembras     integer,
    machos      integer,
    crias       integer,
    created_at  bigint        NOT NULL,
    updated_at  bigint        NOT NULL,
    deleted     boolean       NOT NULL DEFAULT false,
    deleted_at  bigint,
    version     bigint        NOT NULL,

    CONSTRAINT fk_poza_galpon
        FOREIGN KEY (galpon_id) REFERENCES galpon (id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE evento_poza (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    poza_id       uuid        NOT NULL,
    -- Catalogo dinamico: TEXT libre, nunca enum. Nuevos tipos (manuales o de IA)
    -- se insertan como datos, no como codigo.
    tipo_evento   varchar(80) NOT NULL,
    fecha_evento  date        NOT NULL,
    detalles      jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at    bigint      NOT NULL,
    updated_at    bigint      NOT NULL,
    deleted       boolean     NOT NULL DEFAULT false,
    deleted_at    bigint,
    version       bigint      NOT NULL,

    CONSTRAINT fk_evento_poza
        FOREIGN KEY (poza_id) REFERENCES poza (id)
        DEFERRABLE INITIALLY DEFERRED
);

-- ---------------------------------------------------------------------------------
-- Indices
-- ---------------------------------------------------------------------------------

-- Pull delta: traer todo lo cambiado desde el ultimo watermark del dispositivo.
CREATE INDEX idx_registro_updated_at ON registro_actividad (updated_at);
CREATE INDEX idx_evento_updated_at   ON evento_poza (updated_at);
CREATE INDEX idx_terreno_updated_at  ON terreno (updated_at);
CREATE INDEX idx_poza_updated_at     ON poza (updated_at);

-- Consultas de pantalla (filtro por terreno/instalacion, sin tombstones).
CREATE INDEX idx_registro_terreno ON registro_actividad (terreno_id, fecha_realizada DESC)
    WHERE deleted = false;
CREATE INDEX idx_evento_poza_por_tipo ON evento_poza (poza_id, tipo_evento, fecha_evento DESC)
    WHERE deleted = false;
CREATE INDEX idx_poza_por_galpon ON poza (galpon_id) WHERE deleted = false;

-- Busqueda dentro del JSONB (la que hacen los reportes dinamicos y la ingesta IA):
-- jsonb_path_ops es mas chico y rapido para el operador @> (contencion).
CREATE INDEX idx_registro_metadata_gin ON registro_actividad USING gin (metadata jsonb_path_ops);
CREATE INDEX idx_evento_detalles_gin   ON evento_poza   USING gin (detalles   jsonb_path_ops);
CREATE INDEX idx_plantilla_metadata_gin ON plantilla_proceso USING gin (metadata jsonb_path_ops);
