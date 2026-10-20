-- ============================================================
-- CIRA · Checador de asistencia
-- Ejecutar en el SQL Editor de Supabase. Seguro de volver a correr.
-- ============================================================

CREATE TABLE IF NOT EXISTS empleados (
    id             BIGSERIAL PRIMARY KEY,
    numero         TEXT UNIQUE NOT NULL,          -- número de empleado (lo teclea en el checador)
    nombre         TEXT NOT NULL,
    pin_hash       TEXT DEFAULT '',               -- sin uso: se checa solo con el número
    puesto         TEXT DEFAULT '',
    sucursal       TEXT DEFAULT '',
    hora_entrada   TIME DEFAULT '09:00',
    hora_salida    TIME DEFAULT '18:00',
    tolerancia_min INTEGER DEFAULT 10,            -- minutos antes de contar retardo
    activo         BOOLEAN DEFAULT TRUE,
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE empleados ALTER COLUMN pin_hash DROP NOT NULL;
ALTER TABLE empleados ALTER COLUMN pin_hash SET DEFAULT '';

CREATE TABLE IF NOT EXISTS checadas (
    id           BIGSERIAL PRIMARY KEY,
    empleado_id  BIGINT NOT NULL REFERENCES empleados(id) ON DELETE CASCADE,
    tipo         TEXT NOT NULL CHECK (tipo IN ('entrada', 'salida')),
    fecha        DATE NOT NULL,                   -- día local (America/Mexico_City)
    hora         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    retardo_min  INTEGER DEFAULT 0,
    sucursal     TEXT DEFAULT '',
    dispositivo  TEXT DEFAULT '',
    nota         TEXT DEFAULT '',
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checadas_emp_fecha ON checadas (empleado_id, fecha);
CREATE INDEX IF NOT EXISTS idx_checadas_fecha     ON checadas (fecha DESC);

ALTER TABLE empleados ENABLE ROW LEVEL SECURITY;
ALTER TABLE checadas  ENABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';
