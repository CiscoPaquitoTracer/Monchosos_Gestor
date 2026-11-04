-- =====================================================================
-- El estado de una venta se calcula en la base de datos (no en cada teléfono):
--   * 'pagada'  cuando lo cobrado cubre el total (con descuento),
--   * 'abierta' en otro caso,
--   * 'cancelada' se respeta hasta que alguien la reabra.
-- Se recalcula al cobrar, quitar un pago, cambiar renglones o el descuento, o al reabrir.
-- =====================================================================

CREATE FUNCTION interno.fn_recalcular_estado(p_venta_id bigint) RETURNS void
LANGUAGE plpgsql SET search_path = public, interno AS $$
DECLARE
    v record;
    nuevo text;
BEGIN
    SELECT estado, total, pagado INTO v FROM v_ventas WHERE id = p_venta_id;
    IF NOT FOUND OR v.estado = 'cancelada' THEN
        RETURN;
    END IF;
    nuevo := CASE WHEN v.total > 0 AND v.pagado >= v.total THEN 'pagada' ELSE 'abierta' END;
    UPDATE ventas SET estado = nuevo WHERE id = p_venta_id AND estado <> nuevo;
END $$;

CREATE FUNCTION interno.fn_estado_por_hijo() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, interno AS $$
BEGIN
    PERFORM fn_recalcular_estado(coalesce(NEW.venta_id, OLD.venta_id));
    RETURN NULL;
END $$;

CREATE FUNCTION interno.fn_estado_por_venta() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, interno AS $$
BEGIN
    IF NEW.estado <> 'cancelada' THEN
        PERFORM fn_recalcular_estado(NEW.id);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER pagos_estado AFTER INSERT OR UPDATE OR DELETE ON pagos
    FOR EACH ROW EXECUTE FUNCTION interno.fn_estado_por_hijo();
CREATE TRIGGER venta_detalle_estado AFTER INSERT OR UPDATE OR DELETE ON venta_detalle
    FOR EACH ROW EXECUTE FUNCTION interno.fn_estado_por_hijo();
CREATE TRIGGER ventas_estado AFTER UPDATE OF estado, descuento ON ventas
    FOR EACH ROW EXECUTE FUNCTION interno.fn_estado_por_venta();

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA interno FROM public, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA interno TO authenticated;
