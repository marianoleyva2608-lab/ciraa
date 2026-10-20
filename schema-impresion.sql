-- ============================================================
-- Cola de impresión CIRA (Zebras conectadas a Orange Pi)
-- Ejecutar en el SQL Editor de Supabase. Seguro de volver a correr.
-- ============================================================

-- Una fila por Orange Pi / Zebra. Se registra sola la primera vez que se conecta.
CREATE TABLE IF NOT EXISTS impresoras (
    nombre            TEXT PRIMARY KEY,          -- ej. matriz, taller, sucursal-norte
    descripcion       TEXT DEFAULT '',
    activa            BOOLEAN DEFAULT TRUE,
    ultima_conexion   TIMESTAMPTZ,
    version           TEXT DEFAULT '',
    created_at        TIMESTAMPTZ DEFAULT now()
);

-- Cada trabajo que manda la página de etiquetas.
CREATE TABLE IF NOT EXISTS trabajos_impresion (
    id          BIGSERIAL PRIMARY KEY,
    impresora   TEXT NOT NULL REFERENCES impresoras(nombre) ON UPDATE CASCADE,
    zpl         TEXT NOT NULL,
    estado      TEXT NOT NULL DEFAULT 'pendiente'
                CHECK (estado IN ('pendiente', 'enviado', 'impreso', 'error', 'cancelado')),
    error       TEXT DEFAULT '',
    detalle     JSONB DEFAULT '{}',              -- productos y hojas, para el historial
    usuario     TEXT DEFAULT '',
    created_at  TIMESTAMPTZ DEFAULT now(),
    tomado_at   TIMESTAMPTZ,
    impreso_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_trabajos_pendientes
    ON trabajos_impresion (impresora, created_at) WHERE estado = 'pendiente';

ALTER TABLE impresoras         ENABLE ROW LEVEL SECURITY;
ALTER TABLE trabajos_impresion ENABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';
