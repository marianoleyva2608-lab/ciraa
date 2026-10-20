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
