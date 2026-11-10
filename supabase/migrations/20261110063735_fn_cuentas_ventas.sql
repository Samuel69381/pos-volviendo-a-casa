-- ============================================================
-- Cuentas abiertas, pedidos (ventas) y pagos
-- ============================================================

-- Valida una lista de pagos [{"medio":"nequi","monto":5000}, ...] y devuelve la suma
create or replace function public.validar_pagos(p_pagos jsonb)
returns bigint
language plpgsql stable security definer set search_path = public as $$
declare x jsonb; v_total bigint := 0; v_monto bigint;
begin
  if p_pagos is null or jsonb_typeof(p_pagos) = 'null' then return 0; end if;
  if jsonb_typeof(p_pagos) <> 'array' then raise exception 'Los pagos deben ser una lista'; end if;
  for x in select * from jsonb_array_elements(p_pagos) loop
    v_monto := (x->>'monto')::bigint;
    if v_monto is null or v_monto <= 0 then raise exception 'Cada pago debe ser mayor a cero'; end if;
    if not exists (select 1 from medios_pago where codigo = x->>'medio' and activo) then
      raise exception 'Medio de pago no válido: %', coalesce(x->>'medio', '(vacío)');
    end if;
    v_total := v_total + v_monto;
  end loop;
  return v_total;
end $$;

-- Abre la cuenta del día. Con equipo: el nombre de la cuenta es el del equipo y el encargado
-- se autollena con el habitual si no se envía. Sin equipo: cuenta particular a nombre del encargado.
create or replace function public.abrir_cuenta(
  p_encargado_nombre  text default null,
  p_encargado_celular text default null,
  p_equipo_id         uuid default null,
  p_notas             text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_caja uuid := exigir_turno(); e public.equipos; v_id uuid; v_num bigint; v_nombre text;
begin
  if p_equipo_id is not null then
    select * into e from equipos where id = p_equipo_id;
    if not found or not e.activo then raise exception 'Equipo no válido o inactivo'; end if;
    if not exists (select 1 from torneos where id = e.torneo_id and activo) then
      raise exception 'El torneo de % ya terminó', e.nombre;
    end if;
    if exists (select 1 from cuentas where equipo_id = e.id and estado = 'abierta') then
      raise exception '% ya tiene una cuenta abierta: agrega los pedidos a esa', e.nombre;
    end if;
    p_encargado_nombre  := coalesce(nullif(trim(p_encargado_nombre), ''), e.encargado_nombre);
    p_encargado_celular := coalesce(nullif(trim(p_encargado_celular), ''), e.encargado_celular);
    v_nombre := e.nombre;
  else
    v_nombre := trim(p_encargado_nombre);
  end if;
  if nullif(trim(p_encargado_nombre), '') is null then raise exception 'Escribe el nombre del encargado de la cuenta'; end if;
  if nullif(trim(p_encargado_celular), '') is null then raise exception 'Escribe el celular del encargado'; end if;
  if trim(p_encargado_celular) !~ '^3[0-9]{9}$' then raise exception 'Celular inválido: deben ser 10 dígitos y empezar por 3'; end if;

  insert into cuentas(equipo_id, nombre_cuenta, encargado_nombre, encargado_celular, caja_id, abierta_por, notas)
  values (p_equipo_id, v_nombre, trim(p_encargado_nombre), trim(p_encargado_celular), v_caja, auth.uid(), p_notas)
  returning id, numero_cuenta into v_id, v_num;

  -- Recuerda el encargado en el equipo para autollenar la próxima vez
  if p_equipo_id is not null then
    update equipos set encargado_nombre = trim(p_encargado_nombre), encargado_celular = trim(p_encargado_celular)
     where id = p_equipo_id;
  end if;
  perform registrar_auditoria('abrir_cuenta', 'cuentas', v_id, jsonb_build_object('nombre', v_nombre));
  return jsonb_build_object('cuenta_id', v_id, 'numero_cuenta', v_num, 'nombre_cuenta', v_nombre,
                            'encargado', trim(p_encargado_nombre), 'celular', trim(p_encargado_celular));
end $$;

-- Busca cuentas abiertas por nombre del equipo, del encargado o por celular.
-- Ignora mayúsculas y tildes: "wicho", "Wicho" y "WÍCHO" encuentran "WICHO FC".
create or replace function public.buscar_cuentas(p_texto text default '')
returns table (cuenta_id uuid, numero_cuenta bigint, nombre_cuenta text, encargado_nombre text,
               encargado_celular text, productos bigint, total_cop bigint, pagado_cop bigint, saldo_cop bigint,
               abierta_en timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.numero_cuenta, c.nombre_cuenta, c.encargado_nombre, c.encargado_celular,
         (select coalesce(sum(d.cantidad), 0) from ventas v join detalle_venta d on d.venta_id = v.id
           where v.cuenta_id = c.id and v.estado = 'registrada'),
         c.total_cop, c.pagado_cop, c.total_cop - c.pagado_cop, c.abierta_en
  from cuentas c
  where (select empleado_actual()) is not null
    and c.estado = 'abierta'
    and (coalesce(trim(p_texto), '') = ''
         or translate(lower(c.nombre_cuenta || ' ' || c.encargado_nombre || ' ' || c.encargado_celular),
                      'áéíóúüñ', 'aeiouun')
            like '%' || translate(lower(trim(p_texto)), 'áéíóúüñ', 'aeiouun') || '%')
  order by c.nombre_cuenta;
$$;

-- Pago o abono a una cuenta. Si queda en cero, la cuenta se cierra como pagada.
create or replace function public.pagar_cuenta(p_cuenta_id uuid, p_monto bigint, p_medio text, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_caja uuid := exigir_turno(); c public.cuentas; v_pago uuid; v_saldo bigint;
begin
  select * into c from cuentas where id = p_cuenta_id for update;
  if not found then raise exception 'Cuenta no encontrada'; end if;
  if c.estado <> 'abierta' then raise exception 'La cuenta % no está abierta', c.numero_cuenta; end if;
  if p_monto is null or p_monto <= 0 then raise exception 'Escribe un valor mayor a cero'; end if;
  if p_monto > c.total_cop - c.pagado_cop then
    raise exception 'El pago (%) supera el saldo de la cuenta (%)', p_monto, c.total_cop - c.pagado_cop;
  end if;
  if not exists (select 1 from medios_pago where codigo = p_medio and activo) then
    raise exception 'Medio de pago no válido: %', coalesce(p_medio, '(vacío)');
  end if;
  insert into pagos(cuenta_id, caja_id, monto_cop, medio_pago, recibido_por, nota)
  values (c.id, v_caja, p_monto, p_medio, auth.uid(), p_nota) returning id into v_pago;
  v_saldo := c.total_cop - c.pagado_cop - p_monto;
  update cuentas set pagado_cop = pagado_cop + p_monto,
         estado      = case when v_saldo = 0 then 'pagada' else 'abierta' end::estado_cuenta,
         cerrada_en  = case when v_saldo = 0 then now() end,
         cerrada_por = case when v_saldo = 0 then auth.uid() end
   where id = c.id;
  perform registrar_auditoria('pagar_cuenta', 'pagos', v_pago, jsonb_build_object('cuenta', c.numero_cuenta, 'monto', p_monto, 'medio', p_medio));
  return jsonb_build_object('pago_id', v_pago, 'saldo_cop', v_saldo, 'cuenta_cerrada', v_saldo = 0);
end $$;

-- Anula una cuenta abierta por error, solo si no tiene pedidos ni pagos
create or replace function public.anular_cuenta(p_cuenta_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := empleado_actual(); c public.cuentas;
begin
  if nullif(trim(p_motivo), '') is null then raise exception 'Escribe el motivo'; end if;
  select * into c from cuentas where id = p_cuenta_id for update;
  if not found then raise exception 'Cuenta no encontrada'; end if;
  if c.estado <> 'abierta' then raise exception 'La cuenta no está abierta'; end if;
  if c.total_cop > 0 or c.pagado_cop > 0 then
    raise exception 'La cuenta tiene pedidos o pagos: el administrador debe anular los pedidos primero';
  end if;
  update cuentas set estado = 'anulada', cerrada_en = now(), cerrada_por = v_emp.id,
         notas = coalesce(notas || ' · ', '') || 'Anulada: ' || p_motivo
   where id = c.id;
  perform registrar_auditoria('anular_cuenta', 'cuentas', c.id, jsonb_build_object('motivo', p_motivo));
  return jsonb_build_object('cuenta_id', c.id);
end $$;

-- p_items: [{"producto_id":"...","cantidad":2}, ...]
-- Con p_cuenta_id: el pedido se carga a la cuenta y no se cobra ahora.
-- Sin p_cuenta_id: venta de contado; p_pagos debe sumar el total. Puede combinar medios:
-- [{"medio":"efectivo","monto":5000},{"medio":"nequi","monto":3000}]
-- (se registra lo que se aplica, las vueltas las calcula la pantalla).
create or replace function public.registrar_venta(
  p_items          jsonb,
  p_cuenta_id      uuid    default null,
  p_pagos          jsonb   default '[]',
  p_nombre_cliente text    default null,
  p_notas          text    default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_caja  uuid := exigir_turno();
  v_tipo  public.tipo_venta := case when p_cuenta_id is null then 'contado' else 'cuenta' end;
  c public.cuentas; v_venta uuid; v_numero bigint; v_total bigint := 0; v_stock int;
  v_pagado bigint := validar_pagos(p_pagos); x jsonb;
  it record; p public.productos;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido no tiene productos';
  end if;
  if v_tipo = 'cuenta' then
    select * into c from cuentas where id = p_cuenta_id for update;
    if not found then raise exception 'Cuenta no encontrada'; end if;
    if c.estado <> 'abierta' then raise exception 'La cuenta % no está abierta', c.numero_cuenta; end if;
    if v_pagado > 0 then
      raise exception 'Un pedido a cuenta no se cobra al momento: usa pagar_cuenta';
    end if;
  end if;

  insert into ventas(tipo, cuenta_id, nombre_cliente, caja_id, creada_por, notas)
  values (v_tipo, p_cuenta_id, nullif(trim(p_nombre_cliente), ''), v_caja, auth.uid(), p_notas)
  returning id, numero_venta into v_venta, v_numero;

  -- Agrupa por producto y bloquea en orden para evitar choques entre dos celulares
  for it in
    select (e->>'producto_id')::uuid as producto_id, sum((e->>'cantidad')::int) as cantidad
    from jsonb_array_elements(p_items) e group by 1 order by 1
  loop
    if it.cantidad is null or it.cantidad <= 0 then raise exception 'Cantidad inválida'; end if;
    select * into p from productos where id = it.producto_id for update;
    if not found or not p.activo then raise exception 'Producto no disponible'; end if;
    if p.controla_stock and p.stock < it.cantidad then
      raise exception 'Stock insuficiente de %: hay % y pides %', p.nombre, p.stock, it.cantidad;
    end if;
    insert into detalle_venta(venta_id, producto_id, nombre_producto, precio_unitario_cop, costo_unitario_cop, cantidad)
    values (v_venta, p.id, p.nombre, p.precio_cop, p.costo_cop, it.cantidad);
    if p.controla_stock then
      update productos set stock = stock - it.cantidad where id = p.id returning stock into v_stock;
      insert into movimientos_inventario(producto_id, tipo_movimiento, cantidad, stock_resultante, venta_id, caja_id, creado_por)
      values (p.id, 'venta', -it.cantidad, v_stock, v_venta, v_caja, auth.uid());
    end if;
    v_total := v_total + p.precio_cop::bigint * it.cantidad;
  end loop;

  update ventas set total_cop = v_total where id = v_venta;

  if v_tipo = 'contado' then
    if v_pagado <> v_total then
      raise exception 'De contado el pago debe ser igual al total (%). Recibido: %. Si van a pagar después, abre una cuenta',
        v_total, v_pagado;
    end if;
    for x in select * from jsonb_array_elements(p_pagos) loop
      insert into pagos(venta_id, caja_id, monto_cop, medio_pago, recibido_por)
      values (v_venta, v_caja, (x->>'monto')::bigint, x->>'medio', auth.uid());
    end loop;
  else
    update cuentas set total_cop = total_cop + v_total where id = c.id;
  end if;

  perform registrar_auditoria('registrar_venta', 'ventas', v_venta,
          jsonb_build_object('tipo', v_tipo, 'total', v_total, 'cuenta', c.numero_cuenta));
  return jsonb_build_object('venta_id', v_venta, 'numero_venta', v_numero, 'tipo', v_tipo, 'total_cop', v_total,
                            'saldo_cuenta_cop', case when v_tipo = 'cuenta' then c.total_cop + v_total - c.pagado_cop end);
end $$;

-- Anula un pedido de la caja abierta: devuelve stock. Si era de contado marca sus pagos como devueltos;
-- si era a cuenta, lo descuenta del total de la cuenta.
create or replace function public.anular_venta(p_venta_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin public.perfiles := exigir_admin(); v public.ventas; c public.cuentas; d record; v_stock int; v_devolver bigint := 0;
begin
  if nullif(trim(p_motivo), '') is null then raise exception 'Escribe el motivo de la anulación'; end if;
  select * into v from ventas where id = p_venta_id for update;
  if not found then raise exception 'Venta no encontrada'; end if;
  if v.estado = 'anulada' then raise exception 'La venta ya está anulada'; end if;
  if v.caja_id <> caja_abierta_id() then
    raise exception 'Solo se anulan ventas de la caja abierta. Para días cerrados usa un ajuste de inventario';
  end if;
  if v.tipo = 'cuenta' then
    select * into c from cuentas where id = v.cuenta_id for update;
    if c.estado <> 'abierta' then raise exception 'La cuenta ya está cerrada: no se puede anular este pedido'; end if;
    if c.total_cop - v.total_cop < c.pagado_cop then
      raise exception 'La cuenta ya tiene pagos por más de lo que quedaría (%). Revisa con el encargado', c.total_cop - v.total_cop;
    end if;
    update cuentas set total_cop = total_cop - v.total_cop where id = c.id;
  else
    select coalesce(sum(monto_cop), 0) into v_devolver from pagos where venta_id = v.id and not anulado;
    update pagos set anulado = true where venta_id = v.id;
  end if;
  for d in
    select dv.producto_id, sum(dv.cantidad) as cantidad
    from detalle_venta dv join productos pr on pr.id = dv.producto_id
    where dv.venta_id = v.id and pr.controla_stock group by 1 order by 1
  loop
    update productos set stock = stock + d.cantidad where id = d.producto_id returning stock into v_stock;
    insert into movimientos_inventario(producto_id, tipo_movimiento, cantidad, stock_resultante, venta_id, caja_id, creado_por, nota)
    values (d.producto_id, 'devolucion_anulacion', d.cantidad, v_stock, v.id, v.caja_id, v_admin.id, p_motivo);
  end loop;
  update ventas set estado = 'anulada', anulada_por = v_admin.id, anulada_en = now(), motivo_anulacion = p_motivo
   where id = v.id;
  perform registrar_auditoria('anular_venta', 'ventas', v.id, jsonb_build_object('motivo', p_motivo, 'devolver_cop', v_devolver));
  return jsonb_build_object('venta_id', v.id, 'devolver_al_cliente_cop', v_devolver);
end $$;

-- ============================================================
-- Quién puede llamar estas funciones desde la app
-- ============================================================
revoke execute on function
  public.validar_pagos(jsonb),
  public.abrir_cuenta(text, text, uuid, text), public.buscar_cuentas(text),
  public.pagar_cuenta(uuid, bigint, text, text), public.anular_cuenta(uuid, text),
  public.registrar_venta(jsonb, uuid, jsonb, text, text), public.anular_venta(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.abrir_cuenta(text, text, uuid, text), public.buscar_cuentas(text),
  public.pagar_cuenta(uuid, bigint, text, text), public.anular_cuenta(uuid, text),
  public.registrar_venta(jsonb, uuid, jsonb, text, text), public.anular_venta(uuid, text)
to authenticated;