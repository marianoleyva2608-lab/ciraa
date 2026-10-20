-- ============================================================
-- BASE DE DATOS COMPLETA DEL SISTEMA CIRA (estructura)
-- Orden: 1) usuarios y tablas base  2) productos, categorías, precios, inventario
--        3) cola de impresión  4) entradas y salidas del taller
-- Pegar todo en el SQL Editor de Supabase y presionar Run. Seguro de volver a correr.
-- No borra datos: solo crea lo que falta.
-- ============================================================


-- >>>>>>>>>>>>>>>>>>>> schema.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Esquema Postgres para la app "mantos" (Mantenimiento AD-PACK)
-- Ejecutar una sola vez en el SQL Editor de Supabase Studio.
-- Usa CREATE TABLE IF NOT EXISTS: es seguro volver a correrlo.
-- ============================================================

CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY,
    machine_id TEXT,
    fecha TEXT,
    data TEXT
);

CREATE TABLE IF NOT EXISTS app_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS respuestas_problemas (
    id SERIAL PRIMARY KEY,
    folio TEXT, fecha TEXT, equipo TEXT, seccion TEXT,
    descripcion_falla TEXT, hora_inicio TEXT,
    mttr_estimado TEXT, tiempo_real TEXT,
    areas_notificadas TEXT, acciones_tomadas TEXT,
    causa_raiz TEXT, tiempo_total_paro TEXT, elaboro TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS work_orders (
    id SERIAL PRIMARY KEY,
    numero TEXT NOT NULL, solicitante TEXT, fecha TEXT, equipo TEXT,
    planta TEXT, tipo TEXT, estatus TEXT, hora_inicio TEXT, hora_termino TEXT,
    tiempo_paro TEXT, descripcion_falla TEXT, actividad_realizada TEXT,
    refaccion TEXT, observaciones TEXT, firma_solicitante TEXT,
    firma_recibe TEXT, firma_liberacion TEXT, fotos TEXT DEFAULT '[]',
    created_at TEXT DEFAULT (to_char(now(), 'YYYY-MM-DD HH24:MI:SS'))
);

CREATE TABLE IF NOT EXISTS refacciones (
    id SERIAL PRIMARY KEY,
    nombre TEXT, descripcion TEXT, marca TEXT, modelo TEXT,
    categoria TEXT, criticidad TEXT DEFAULT 'MEDIA', seccion TEXT,
    cant_min INTEGER DEFAULT 1, stock_actual INTEGER DEFAULT 0,
    tiempo_entrega TEXT, proveedor TEXT, ubicacion TEXT,
    costo REAL DEFAULT 0, notas TEXT, foto_b64 TEXT,
    imagen_url TEXT DEFAULT '',
    numero_parte TEXT DEFAULT '',
    estante_nombre TEXT DEFAULT '',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    pin_hash TEXT NOT NULL,
    rol TEXT DEFAULT 'usuario',
    permisos TEXT DEFAULT '',
    created_at TEXT DEFAULT (to_char(now(), 'YYYY-MM-DD HH24:MI:SS'))
);

CREATE TABLE IF NOT EXISTS proveedores_extra (
    codigo TEXT PRIMARY KEY,
    nombre TEXT NOT NULL,
    created_at TEXT DEFAULT (to_char(now(), 'YYYY-MM-DD HH24:MI:SS'))
);

CREATE TABLE IF NOT EXISTS estantes (
    id SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL UNIQUE,
    created_at TEXT DEFAULT (to_char(now(), 'YYYY-MM-DD HH24:MI:SS'))
);
INSERT INTO estantes (nombre) VALUES ('Almacén Estante 2') ON CONFLICT (nombre) DO NOTHING;
INSERT INTO estantes (nombre) VALUES ('Estante de herramientas') ON CONFLICT (nombre) DO NOTHING;

CREATE TABLE IF NOT EXISTS requisiciones (
    id TEXT PRIMARY KEY,
    folio INTEGER,
    fecha TEXT,
    solicitante TEXT,
    planta TEXT,
    departamento TEXT,
    tipo TEXT,
    data TEXT,
    created_at TEXT DEFAULT (to_char(now(), 'YYYY-MM-DD HH24:MI:SS'))
);

-- Usuario administrador por defecto (mismo PIN que ya usan: 260881)
INSERT INTO users (nombre, email, pin_hash, rol, permisos)
VALUES (
    'Mariano Leyva',
    'marianoleyva2608@gmail.com',
    encode(sha256('260881'::bytea), 'hex'),
    'admin',
    'all'
)
ON CONFLICT (email) DO UPDATE SET rol = 'admin', permisos = 'all';


-- >>>>>>>>>>>>>>>>>>>> schema-cira.sql <<<<<<<<<<<<<<<<<<<<
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


-- >>>>>>>>>>>>>>>>>>>> schema-impresion.sql <<<<<<<<<<<<<<<<<<<<
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

-- Tipo de impresora (zpl = Zebra, ticket = térmica de 58 mm ESC/POS) y formato del trabajo
ALTER TABLE impresoras         ADD COLUMN IF NOT EXISTS tipo    TEXT DEFAULT 'zpl';
ALTER TABLE trabajos_impresion ADD COLUMN IF NOT EXISTS formato TEXT DEFAULT 'zpl';  -- zpl | escpos (base64)

ALTER TABLE impresoras         ENABLE ROW LEVEL SECURITY;
ALTER TABLE trabajos_impresion ENABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';


-- >>>>>>>>>>>>>>>>>>>> schema-movimientos.sql <<<<<<<<<<<<<<<<<<<<
-- ============================================================
-- Taller · Entradas y salidas (agrega datos al historial de movimientos)
-- Ejecutar en el SQL Editor de Supabase DESPUES de schema-cira.sql.
-- Seguro de volver a correr.
-- ============================================================

-- Cada registro de la página puede tener varios productos: comparten "grupo".
ALTER TABLE movimientos_inventario ADD COLUMN IF NOT EXISTS grupo      TEXT DEFAULT '';
ALTER TABLE movimientos_inventario ADD COLUMN IF NOT EXISTS referencia TEXT DEFAULT ''; -- proveedor, cliente o área
ALTER TABLE movimientos_inventario ADD COLUMN IF NOT EXISTS folio      TEXT DEFAULT ''; -- factura, remisión, vale
ALTER TABLE movimientos_inventario ADD COLUMN IF NOT EXISTS stock_despues INTEGER;   -- stock que quedó

CREATE INDEX IF NOT EXISTS idx_mov_grupo ON movimientos_inventario (grupo);
CREATE INDEX IF NOT EXISTS idx_mov_fecha ON movimientos_inventario (created_at DESC);

-- El stock se actualiza con el trigger trg_movimientos_stock (schema-cira.sql).
-- Aquí además se guarda en el movimiento cuánto stock quedó.
CREATE OR REPLACE FUNCTION aplicar_movimiento() RETURNS trigger AS $$
DECLARE nuevo INTEGER;
BEGIN
    IF NEW.tipo = 'entrada' THEN
        UPDATE productos SET stock = stock + NEW.cantidad WHERE id = NEW.producto_id RETURNING stock INTO nuevo;
    ELSIF NEW.tipo = 'salida' THEN
        UPDATE productos SET stock = stock - NEW.cantidad WHERE id = NEW.producto_id RETURNING stock INTO nuevo;
    ELSE
        UPDATE productos SET stock = NEW.cantidad WHERE id = NEW.producto_id RETURNING stock INTO nuevo;
    END IF;
    UPDATE movimientos_inventario SET stock_despues = nuevo WHERE id = NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

NOTIFY pgrst, 'reload schema';

-- Códigos de 2 dígitos de las categorías (para el código de barras)
ALTER TABLE categorias ADD COLUMN IF NOT EXISTS codigo TEXT UNIQUE;
INSERT INTO categorias (codigo, nombre) VALUES
('10','Cascos y accesorios'),
('11','Lentes y protección facial'),
('12','Protección respiratoria'),
('13','Protección auditiva'),
('14','Gorras, cofias y cubrepelo'),
('20','Guantes y mangas'),
('30','Botas'),
('31','Borceguíes'),
('32','Tenis'),
('33','Choclos y calzado'),
('34','Accesorios de calzado'),
('40','Batas'),
('41','Chalecos'),
('42','Pantalones'),
('43','Overoles'),
('44','Playeras'),
('45','Camisas, camisolas y filipinas'),
('46','Chamarras e impermeables'),
('47','Mandiles y trajes de protección'),
('48','Fajas y ergonomía'),
('49','Uniformes e identificación'),
('50','Trabajo en alturas'),
('60','Señalamientos'),
('61','Cintas y bandas de advertencia'),
('62','Control vial y estacionamiento'),
('70','Bloqueo LOTO y seguridad eléctrica'),
('80','Extintores y combate de incendio'),
('81','Primeros auxilios y emergencias'),
('82','Hidratación y cuidado personal'),
('83','Limpieza e higiene'),
('84','Derrames y almacenamiento'),
('90','Servicios de taller'),
('91','Servicios y cargos'),
('99','Otros')
ON CONFLICT (nombre) DO UPDATE SET codigo = EXCLUDED.codigo;
-- Quitar categorías provisionales sin código que ningún producto usa
DELETE FROM categorias c WHERE c.codigo IS NULL AND NOT EXISTS (SELECT 1 FROM productos p WHERE p.categoria_id = c.id);
NOTIFY pgrst, 'reload schema';


-- ===================== Checador de asistencia =====================
CREATE TABLE IF NOT EXISTS empleados (
    id             BIGSERIAL PRIMARY KEY,
    numero         TEXT UNIQUE NOT NULL,          -- número de empleado (lo teclea en el checador)
    nombre         TEXT NOT NULL,
    pin_hash       TEXT NOT NULL,                 -- sha256 del PIN
    puesto         TEXT DEFAULT '',
    sucursal       TEXT DEFAULT '',
    hora_entrada   TIME DEFAULT '09:00',
    hora_salida    TIME DEFAULT '18:00',
    tolerancia_min INTEGER DEFAULT 10,            -- minutos antes de contar retardo
    activo         BOOLEAN DEFAULT TRUE,
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW()
);

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
