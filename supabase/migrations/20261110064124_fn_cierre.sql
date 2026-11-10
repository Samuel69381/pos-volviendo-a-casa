-- ============================================================
-- Cierre de caja: resumen de la jornada y arqueo
-- ============================================================

-- Totales de una caja (por defecto la abierta). Sirve para la pantalla de cierre.
create or replace function public.resumen_caja(p_caja_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_caja uuid := coalesce(p_caja_id, caja_abierta_id()); c public.cajas; r jsonb;
begin
  perform empleado_actual();
  select * into c from cajas where id = v_caja;
  if not found then raise exception 'Caja no encontrada'; end if;
  select jsonb_build_object(
    'caja_id', c.id,
    'abierta_en', c.abierta_en,
    'cerrada_en', c.cerrada_en,
    'base_inicial_cop', c.base_inicial_cop,
    'ventas_contado_cop',  coalesce((select sum(total_cop) from ventas where caja_id = c.id and estado = 'registrada' and tipo = 'contado'), 0),
    'pedidos_a_cuenta_cop',coalesce((select sum(total_cop) from ventas where caja_id = c.id and estado = 'registrada' and tipo = 'cuenta'), 0),
    'numero_ventas',       (select count(*) from ventas where caja_id = c.id and estado = 'registrada'),
    'ventas_anuladas',     (select count(*) from ventas where caja_id = c.id and estado = 'anulada'),
    'efectivo_cop',        coalesce((select sum(p.monto_cop) from pagos p join medios_pago m on m.codigo = p.medio_pago
                                     where p.caja_id = c.id and not p.anulado and m.tipo = 'efectivo'), 0),
    'transferencias_cop',  coalesce((select sum(p.monto_cop) from pagos p join medios_pago m on m.codigo = p.medio_pago
                                     where p.caja_id = c.id and not p.anulado and m.tipo = 'transferencia'), 0),
    'por_medio',           (select coalesce(jsonb_object_agg(m.nombre, coalesce(t.total, 0) order by m.orden), '{}')
                            from medios_pago m
                            left join (select medio_pago, sum(monto_cop) total from pagos
                                       where caja_id = c.id and not anulado group by 1) t on t.medio_pago = m.codigo),
    'productos_sin_contar',(select count(*) from cuadre_inventario where caja_id = c.id and contado is null),
    'gastos_cop',          coalesce((select sum(monto_cop) from gastos where caja_id = c.id), 0),
    'cuentas_abiertas',    (select count(*) from cuentas where estado = 'abierta'),
    'saldo_cuentas_abiertas_cop', coalesce((select sum(total_cop - pagado_cop) from cuentas where estado = 'abierta'), 0)
  ) into r;
  r := r || jsonb_build_object('efectivo_esperado_cop',
         (r->>'base_inicial_cop')::bigint + (r->>'efectivo_cop')::bigint - (r->>'gastos_cop')::bigint);
  return r;
end $$;

-- Cierra la caja con el arqueo y cierra todos los turnos abiertos.
-- Las cuentas que sigan abiertas quedan pendientes y se pueden pagar en otra jornada.
create or replace function public.cerrar_caja(p_efectivo_contado bigint, p_notas text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := empleado_actual(); v_caja uuid; r jsonb; v_esperado bigint;
        q record; v_dif_inv jsonb := '{}';
begin
  if p_efectivo_contado is null or p_efectivo_contado < 0 then raise exception 'Escribe el efectivo contado'; end if;
  select id into v_caja from cajas where cerrada_en is null for update;
  if v_caja is null then raise exception 'No hay caja abierta'; end if;
  if v_emp.rol <> 'admin' and not exists
     (select 1 from turnos where caja_id = v_caja and perfil_id = v_emp.id and fin is null) then
    raise exception 'Solo el administrador o un empleado en turno puede cerrar la caja';
  end if;
  r := resumen_caja(v_caja);
  v_esperado := (r->>'efectivo_esperado_cop')::bigint;
  -- Cuadre de inventario: guarda el "debe haber" y lleva el stock a lo contado
  for q in
    select ci.id, ci.producto_id, ci.contado, pr.stock, pr.nombre
    from cuadre_inventario ci join productos pr on pr.id = ci.producto_id
    where ci.caja_id = v_caja order by ci.producto_id for update of ci, pr
  loop
    update cuadre_inventario set debe_haber = q.stock where id = q.id;
    if q.contado is not null and q.contado <> q.stock then
      update productos set stock = q.contado where id = q.producto_id;
      insert into movimientos_inventario(producto_id, tipo_movimiento, cantidad, stock_resultante, caja_id, creado_por, nota)
      values (q.producto_id, 'conteo', q.contado - q.stock, q.contado, v_caja, v_emp.id, 'Conteo de cierre');
      v_dif_inv := v_dif_inv || jsonb_build_object(q.nombre, q.contado - q.stock);
    end if;
  end loop;
  update cajas set cerrada_en = now(), cerrada_por = v_emp.id,
         efectivo_esperado_cop = v_esperado, efectivo_contado_cop = p_efectivo_contado, notas = p_notas
   where id = v_caja;
  update turnos set fin = now() where caja_id = v_caja and fin is null;
  r := r || jsonb_build_object('cerrada_en', now(), 'efectivo_contado_cop', p_efectivo_contado,
                               'diferencia_cop', p_efectivo_contado - v_esperado,
                               'diferencias_inventario', v_dif_inv);
  perform registrar_auditoria('cerrar_caja', 'cajas', v_caja, r);
  return r;
end $$;

-- ============================================================
-- Quién puede llamar estas funciones desde la app
-- ============================================================
revoke execute on function public.resumen_caja(uuid), public.cerrar_caja(bigint, text)
from public, anon, authenticated;

grant execute on function public.resumen_caja(uuid), public.cerrar_caja(bigint, text)
to authenticated;
