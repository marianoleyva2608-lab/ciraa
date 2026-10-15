-- ============================================================
-- Esquema del sistema CIRA (productos, precios, etiquetas, inventario)
-- Ejecutar en el SQL Editor de Supabase Studio DESPUES de schema.sql
-- (schema.sql crea las tablas base de la app: users, etc.).
-- Es seguro volver a correrlo: usa IF NOT EXISTS.
-- ============================================================

-- ---------- Categorías ----------
CREATE TABLE IF NOT EXISTS categorias (
    id          SERIAL PRIMARY KEY,
    nombre      TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ DEFAULT now()
);

INSERT INTO categorias (nombre) VALUES
    ('Batas'), ('Chalecos'), ('Cascos'), ('Lentes'), ('Guantes'),
    ('Calzado'), ('Protección auditiva'), ('Protección respiratoria'),
    ('Ropa de trabajo'), ('Señalización'), ('Otros')
ON CONFLICT (nombre) DO NOTHING;

-- ---------- Productos ----------
CREATE TABLE IF NOT EXISTS productos (
    id              SERIAL PRIMARY KEY,
    sku             TEXT UNIQUE,
    nombre          TEXT NOT NULL,              -- Línea 1 de la etiqueta (ej. BATA)
    descripcion     TEXT DEFAULT '',            -- Línea 2 (ej. ANTIESTATICA REF.)
    categoria_id    INTEGER REFERENCES categorias(id) ON DELETE SET NULL,
    marca           TEXT DEFAULT '',
    talla           TEXT DEFAULT '',
    color           TEXT DEFAULT '',
    codigo_barras   TEXT UNIQUE,
    unidad          TEXT DEFAULT 'PZA',
    costo           NUMERIC(12,2) DEFAULT 0,
    precio_venta    NUMERIC(12,2) DEFAULT 0,
    precio_mayoreo  NUMERIC(12,2) DEFAULT 0,
    stock           INTEGER DEFAULT 0,
    stock_minimo    INTEGER DEFAULT 0,
    ubicacion       TEXT DEFAULT '',
    foto_url        TEXT DEFAULT '',
    activo          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_productos_nombre    ON productos (lower(nombre));
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos (categoria_id);

-- Producto de ejemplo (el de tu etiqueta)
INSERT INTO productos (sku, nombre, descripcion, categoria_id, talla, color, codigo_barras)
SELECT 'BAT-ANT-S-AZM', 'BATA', 'ANTIESTATICA REF.', c.id, 'CHICO (S)', 'Azul Marino', '092024003911'
FROM categorias c WHERE c.nombre = 'Batas'
ON CONFLICT (codigo_barras) DO NOTHING;

-- ---------- Historial de precios ----------
CREATE TABLE IF NOT EXISTS historial_precios (
    id               SERIAL PRIMARY KEY,
    producto_id      INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    campo            TEXT NOT NULL,             -- costo / precio_venta / precio_mayoreo
    precio_anterior  NUMERIC(12,2),
    precio_nuevo     NUMERIC(12,2),
    usuario          TEXT DEFAULT '',
    created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hist_precios_producto ON historial_precios (producto_id, created_at DESC);

-- ---------- Movimientos de inventario ----------
CREATE TABLE IF NOT EXISTS movimientos_inventario (
    id           SERIAL PRIMARY KEY,
    producto_id  INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    tipo         TEXT NOT NULL CHECK (tipo IN ('entrada', 'salida', 'ajuste')),
    cantidad     INTEGER NOT NULL,
    motivo       TEXT DEFAULT '',
    usuario      TEXT DEFAULT '',
    created_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mov_producto ON movimientos_inventario (producto_id, created_at DESC);

-- ---------- Impresiones de etiquetas ----------
CREATE TABLE IF NOT EXISTS impresiones (
    id          SERIAL PRIMARY KEY,
    tipo        TEXT NOT NULL DEFAULT 'producto',  -- producto / precio / anaquel
    detalle     JSONB NOT NULL DEFAULT '[]',        -- productos y cantidades impresas
    hojas       INTEGER DEFAULT 1,
    usuario     TEXT DEFAULT '',
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- ---------- Configuración general ----------
CREATE TABLE IF NOT EXISTS configuracion (
    clave  TEXT PRIMARY KEY,
    valor  TEXT
);
INSERT INTO configuracion (clave, valor) VALUES
    ('empresa_nombre', 'CIRA - Tu almacén de seguridad'),
    ('ip_raspberry',   '100.87.53.113')
ON CONFLICT (clave) DO NOTHING;

-- ---------- updated_at automático en productos ----------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_productos_updated ON productos;
CREATE TRIGGER trg_productos_updated
    BEFORE UPDATE ON productos
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------- Historial de precios automático ----------
CREATE OR REPLACE FUNCTION registrar_cambio_precio() RETURNS trigger AS $$
BEGIN
    IF NEW.costo IS DISTINCT FROM OLD.costo THEN
        INSERT INTO historial_precios (producto_id, campo, precio_anterior, precio_nuevo)
        VALUES (NEW.id, 'costo', OLD.costo, NEW.costo);
    END IF;
    IF NEW.precio_venta IS DISTINCT FROM OLD.precio_venta THEN
        INSERT INTO historial_precios (producto_id, campo, precio_anterior, precio_nuevo)
        VALUES (NEW.id, 'precio_venta', OLD.precio_venta, NEW.precio_venta);
    END IF;
    IF NEW.precio_mayoreo IS DISTINCT FROM OLD.precio_mayoreo THEN
        INSERT INTO historial_precios (producto_id, campo, precio_anterior, precio_nuevo)
        VALUES (NEW.id, 'precio_mayoreo', OLD.precio_mayoreo, NEW.precio_mayoreo);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_productos_precios ON productos;
CREATE TRIGGER trg_productos_precios
    AFTER UPDATE ON productos
    FOR EACH ROW EXECUTE FUNCTION registrar_cambio_precio();

-- ---------- Stock automático con cada movimiento ----------
CREATE OR REPLACE FUNCTION aplicar_movimiento() RETURNS trigger AS $$
BEGIN
    IF NEW.tipo = 'entrada' THEN
        UPDATE productos SET stock = stock + NEW.cantidad WHERE id = NEW.producto_id;
    ELSIF NEW.tipo = 'salida' THEN
        UPDATE productos SET stock = stock - NEW.cantidad WHERE id = NEW.producto_id;
    ELSE  -- ajuste: la cantidad es el nuevo stock
        UPDATE productos SET stock = NEW.cantidad WHERE id = NEW.producto_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_movimientos_stock ON movimientos_inventario;
CREATE TRIGGER trg_movimientos_stock
    AFTER INSERT ON movimientos_inventario
    FOR EACH ROW EXECUTE FUNCTION aplicar_movimiento();

-- ---------- Vista: productos bajo stock mínimo ----------
CREATE OR REPLACE VIEW productos_bajo_stock AS
SELECT p.id, p.sku, p.nombre, p.descripcion, p.talla, p.color, p.stock, p.stock_minimo
FROM productos p
WHERE p.activo AND p.stock <= p.stock_minimo;

-- ---------- Seguridad ----------
-- La app entra con la SERVICE_ROLE_KEY desde el servidor (Flask), que ignora RLS.
-- Activar RLS sin políticas bloquea el acceso público con la ANON_KEY.
ALTER TABLE categorias             ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos              ENABLE ROW LEVEL SECURITY;
ALTER TABLE historial_precios      ENABLE ROW LEVEL SECURITY;
ALTER TABLE movimientos_inventario ENABLE ROW LEVEL SECURITY;
ALTER TABLE impresiones            ENABLE ROW LEVEL SECURITY;
ALTER TABLE configuracion          ENABLE ROW LEVEL SECURITY;
