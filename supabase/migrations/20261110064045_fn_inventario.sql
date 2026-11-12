-- ============================================================
-- Inventario: compras, ajustes, gastos, cuadre del día e historial de precios
-- ============================================================

-- Entrada de mercancía. Recalcula el costo promedio ponderado.
create or replace function public.registrar_compra(p_producto_id uuid, p_cantidad int, p_costo_unitario int default null,
                                                   p_proveedor text default null, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin public.perfiles := exigir_admin(); p public.productos; v_costo int;
begin
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'Cantidad inválida'; end if;
  if p_costo_unitario is not null and p_costo_unitario < 0 then raise exception 'Costo inválido'; end if;
  select * into p from productos where id = p_producto_id for update;
  if not found then raise exception 'Producto no encontrado'; end if;
  if not p.controla_stock then raise exception '% no maneja inventario', p.nombre; end if;
  v_costo := case when p_costo_unitario is null then p.costo_cop
                  else round((p.stock::numeric * p.costo_cop + p_cantidad::numeric * p_costo_unitario) / (p.stock + p_cantidad)) end;
  update productos set stock = stock + p_cantidad, costo_cop = v_costo where id = p.id;
  insert into movimientos_inventario(producto_id, tipo_movimiento, cantidad, stock_resultante, costo_unitario_cop, proveedor, caja_id, creado_por, nota)
  values (p.id, 'compra', p_cantidad, p.stock + p_cantidad, p_costo_unitario, p_proveedor,
          (select id from cajas where cerrada_en is null), v_admin.id, p_nota);
  -- Producto nuevo durante la jornada: entra al cuadre con inicial 0
  insert into cuadre_inventario(caja_id, producto_id, inicial)
  select id, p.id, 0 from cajas where cerrada_en is null
  on conflict (caja_id, producto_id) do nothing;
  perform registrar_auditoria('registrar_compra', 'productos', p.id, jsonb_build_object('cantidad', p_cantidad, 'costo', p_costo_unitario));
  return jsonb_build_object('producto', p.nombre, 'stock', p.stock + p_cantidad, 'costo_promedio_cop', v_costo);
end $$;

-- Conteo físico: deja el stock en lo contado (mermas, daños, regalos)
create or replace function public.ajustar_inventario(p_producto_id uuid, p_stock_contado int, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin public.perfiles := exigir_admin(); p public.productos; v_dif int;
begin
  if p_stock_contado is null or p_stock_contado < 0 then raise exception 'Stock contado inválido'; end if;
  if nullif(trim(p_motivo), '') is null then raise exception 'Escribe el motivo del ajuste'; end if;
  select * into p from productos where id = p_producto_id for update;
  if not found then raise exception 'Producto no encontrado'; end if;
  if not p.controla_stock then raise exception '% no maneja inventario', p.nombre; end if;
  v_dif := p_stock_contado - p.stock;
  if v_dif = 0 then return jsonb_build_object('producto', p.nombre, 'diferencia', 0); end if;
  update productos set stock = p_stock_contado where id = p.id;
  insert into movimientos_inventario(producto_id, tipo_movimiento, cantidad, stock_resultante, caja_id, creado_por, nota)
  values (p.id, 'ajuste', v_dif, p_stock_contado, (select id from cajas where cerrada_en is null), v_admin.id, p_motivo);
  perform registrar_auditoria('ajustar_inventario', 'productos', p.id, jsonb_build_object('antes', p.stock, 'despues', p_stock_contado, 'motivo', p_motivo));
  return jsonb_build_object('producto', p.nombre, 'antes', p.stock, 'despues', p_stock_contado, 'diferencia', v_dif);
end $$;

-- Gasto pagado con el efectivo de la caja (hielo, bolsas, transporte)
create or replace function public.registrar_gasto(p_monto bigint, p_categoria text, p_descripcion text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_caja uuid := exigir_turno(); v_id uuid;
begin
  if p_monto is null or p_monto <= 0 then raise exception 'Escribe un valor mayor a cero'; end if;
  if nullif(trim(p_categoria), '') is null then raise exception 'Escribe la categoría del gasto'; end if;
  insert into gastos(caja_id, monto_cop, categoria, descripcion, pagado_por)
  values (v_caja, p_monto, trim(p_categoria), p_descripcion, auth.uid()) returning id into v_id;
  perform registrar_auditoria('registrar_gasto', 'gastos', v_id, jsonb_build_object('monto', p_monto));
  return jsonb_build_object('gasto_id', v_id);
end $$;

-- Cuadre del día por producto: Inicial + Compré − Vendido ± Ajustes = Debe haber; Conteo; Diferencia
create or replace function public.cuadre_caja(p_caja_id uuid default null)
returns table (producto_id uuid, producto text, inicial integer, comprado bigint, vendido bigint, ajustes bigint,
               debe_haber bigint, contado integer, diferencia integer)
language sql stable security definer set search_path = public as $$
  with caja as (select coalesce(p_caja_id, caja_abierta_id()) as id),
  mov as (
    select m.producto_id,
           sum(case when m.tipo_movimiento = 'compra' then m.cantidad else 0 end) as comprado,
           -sum(case when m.tipo_movimiento in ('venta','devolucion_anulacion') then m.cantidad else 0 end) as vendido,
           sum(case when m.tipo_movimiento = 'ajuste' then m.cantidad else 0 end) as ajustes
    from movimientos_inventario m, caja where m.caja_id = caja.id group by 1)
  select p.id, p.nombre, q.inicial,
         coalesce(mov.comprado, 0), coalesce(mov.vendido, 0), coalesce(mov.ajustes, 0),
         coalesce(q.debe_haber, q.inicial + coalesce(mov.comprado, 0) - coalesce(mov.vendido, 0) + coalesce(mov.ajustes, 0)),
         q.contado,
         coalesce(q.diferencia, q.contado - (q.inicial + coalesce(mov.comprado, 0) - coalesce(mov.vendido, 0) + coalesce(mov.ajustes, 0)))::int
  from caja
  join cuadre_inventario q on q.caja_id = caja.id
  join productos p on p.id = q.producto_id
  left join mov on mov.producto_id = p.id
  where (select empleado_actual()) is not null
  order by p.orden, p.nombre;
$$;

-- El empleado anota cuántas unidades contó al cierre (puede corregirlo las veces que quiera).
-- El stock NO cambia aquí: se ajusta a lo contado cuando se cierra la caja.
create or replace function public.registrar_conteo(p_producto_id uuid, p_contado int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_caja uuid := exigir_turno(); p public.productos; v_id uuid;
begin
  if p_contado is null or p_contado < 0 then raise exception 'Escribe cuántas unidades contaste'; end if;
  select * into p from productos where id = p_producto_id;
  if not found or not p.controla_stock then raise exception 'Producto no válido para conteo'; end if;
  insert into cuadre_inventario(caja_id, producto_id, inicial, contado, contado_por, contado_en)
  values (v_caja, p.id, 0, p_contado, auth.uid(), now())
  on conflict (caja_id, producto_id)
  do update set contado = excluded.contado, contado_por = excluded.contado_por, contado_en = excluded.contado_en
  returning id into v_id;
  perform registrar_auditoria('registrar_conteo', 'cuadre_inventario', v_id,
          jsonb_build_object('producto', p.nombre, 'debe_haber', p.stock, 'contado', p_contado));
  return jsonb_build_object('producto', p.nombre, 'debe_haber', p.stock, 'contado', p_contado, 'diferencia', p_contado - p.stock);
end $$;

-- ============================================================
-- 6. HISTORIAL DE PRECIOS (automático)
-- ============================================================
create or replace function public.guardar_historial_precio()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.precio_cop <> old.precio_cop then
    insert into historial_precios(producto_id, precio_anterior, precio_nuevo, cambiado_por)
    values (new.id, old.precio_cop, new.precio_cop, auth.uid());
  end if;
  return new;
end $$;

create trigger trg_historial_precio after update of precio_cop on public.productos
for each row execute function public.guardar_historial_precio();

-- ============================================================
-- Quién puede llamar estas funciones desde la app
-- ============================================================
revoke execute on function
  public.registrar_compra(uuid, int, int, text, text), public.ajustar_inventario(uuid, int, text),
  public.registrar_gasto(bigint, text, text), public.cuadre_caja(uuid), public.registrar_conteo(uuid, int),
  public.guardar_historial_precio()
from public, anon, authenticated;

grant execute on function
  public.registrar_compra(uuid, int, int, text, text), public.ajustar_inventario(uuid, int, text),
  public.registrar_gasto(bigint, text, text), public.cuadre_caja(uuid), public.registrar_conteo(uuid, int)
to authenticated;