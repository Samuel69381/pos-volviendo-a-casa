-- ============================================================
-- La cajera también administra lo del día a día cuando el dueño no está:
-- crear torneos, inscribir equipos, crear productos nuevos y registrar compras.
-- Siguen siendo solo del admin: cambiar precios, desactivar, finalizar torneos,
-- empleados, anular ventas y cierre de caja. El mesero no hace nada de esto.
-- ============================================================

-- 1. Admin o cajero activo; si no, falla. Devuelve el perfil.
--    (rol::text para no depender de que 'mesero' ya esté confirmado)
create or replace function public.exigir_encargado()
returns public.perfiles
language plpgsql stable security definer set search_path = public as $$
declare v public.perfiles := empleado_actual();
begin
  if v.rol::text not in ('admin', 'cajero') then
    raise exception 'Solo el cajero o el administrador pueden hacer esta operación';
  end if;
  return v;
end $$;

-- 2. Las mismas funciones de antes, ahora con exigir_encargado() en vez de exigir_admin()

-- Crea un torneo nuevo
create or replace function public.crear_torneo(
  p_nombre       text,
  p_fecha_inicio date default null,
  p_fecha_fin    date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := exigir_encargado(); v_id uuid;
begin
  if nullif(trim(p_nombre), '') is null then raise exception 'Escribe el nombre del torneo'; end if;
  if p_fecha_inicio is not null and p_fecha_fin is not null and p_fecha_fin < p_fecha_inicio then
    raise exception 'La fecha de fin no puede ser antes de la de inicio';
  end if;
  if exists (select 1 from torneos where lower(nombre) = lower(trim(p_nombre))) then
    raise exception 'Ya existe un torneo llamado %', trim(p_nombre);
  end if;
  insert into torneos(nombre, fecha_inicio, fecha_fin)
  values (trim(p_nombre), p_fecha_inicio, p_fecha_fin) returning id into v_id;
  perform registrar_auditoria('crear_torneo', 'torneos', v_id, jsonb_build_object('nombre', trim(p_nombre)));
  return jsonb_build_object('torneo_id', v_id, 'nombre', trim(p_nombre));
end $$;

-- Inscribe un equipo en un torneo (el encargado habitual es opcional)
create or replace function public.inscribir_equipo(
  p_torneo_id         uuid,
  p_nombre            text,
  p_encargado_nombre  text default null,
  p_encargado_celular text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := exigir_encargado(); t public.torneos; v_id uuid; v_nombre text := upper(trim(p_nombre));
begin
  select * into t from torneos where id = p_torneo_id;
  if not found then raise exception 'Torneo no encontrado'; end if;
  if not t.activo then raise exception 'El torneo % ya terminó', t.nombre; end if;
  if nullif(v_nombre, '') is null then raise exception 'Escribe el nombre del equipo'; end if;
  if exists (select 1 from equipos where torneo_id = t.id and nombre = v_nombre) then
    raise exception '% ya está inscrito en %', v_nombre, t.nombre;
  end if;
  p_encargado_celular := nullif(trim(p_encargado_celular), '');
  if p_encargado_celular is not null and p_encargado_celular !~ '^3[0-9]{9}$' then
    raise exception 'Celular inválido: deben ser 10 dígitos y empezar por 3';
  end if;
  insert into equipos(torneo_id, nombre, encargado_nombre, encargado_celular)
  values (t.id, v_nombre, nullif(trim(p_encargado_nombre), ''), p_encargado_celular)
  returning id into v_id;
  perform registrar_auditoria('inscribir_equipo', 'equipos', v_id, jsonb_build_object('torneo', t.nombre, 'equipo', v_nombre));
  return jsonb_build_object('equipo_id', v_id, 'nombre', v_nombre, 'torneo', t.nombre);
end $$;

-- Entrada de mercancía. Recalcula el costo promedio ponderado.
create or replace function public.registrar_compra(p_producto_id uuid, p_cantidad int, p_costo_unitario int default null,
                                                   p_proveedor text default null, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := exigir_encargado(); p public.productos; v_costo int;
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
          (select id from cajas where cerrada_en is null), v_emp.id, p_nota);
  -- Producto nuevo durante la jornada: entra al cuadre con inicial 0
  insert into cuadre_inventario(caja_id, producto_id, inicial)
  select id, p.id, 0 from cajas where cerrada_en is null
  on conflict (caja_id, producto_id) do nothing;
  perform registrar_auditoria('registrar_compra', 'productos', p.id, jsonb_build_object('cantidad', p_cantidad, 'costo', p_costo_unitario));
  return jsonb_build_object('producto', p.nombre, 'stock', p.stock + p_cantidad, 'costo_promedio_cop', v_costo);
end $$;

-- 3. Crear un producto nuevo. La cajera lo puede vender de una vez;
--    cambiar el precio después sigue siendo solo del admin.
create or replace function public.crear_producto(
  p_nombre         text,
  p_precio_cop     integer,
  p_categoria_id   uuid    default null,
  p_controla_stock boolean default true,
  p_stock_minimo   integer default 5)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := exigir_encargado(); v_id uuid; v_nombre text := trim(p_nombre);
begin
  if nullif(v_nombre, '') is null then raise exception 'Escribe el nombre del producto'; end if;
  if p_precio_cop is null or p_precio_cop <= 0 then raise exception 'El precio debe ser mayor a cero'; end if;
  if p_stock_minimo is null or p_stock_minimo < 0 then raise exception 'Stock mínimo inválido'; end if;
  if exists (select 1 from productos where lower(nombre) = lower(v_nombre)) then
    raise exception 'Ya existe un producto llamado %', v_nombre;
  end if;
  if p_categoria_id is not null and not exists (select 1 from categorias where id = p_categoria_id) then
    raise exception 'Categoría no encontrada';
  end if;
  insert into productos(nombre, categoria_id, precio_cop, controla_stock, stock_minimo, orden)
  values (v_nombre, p_categoria_id, p_precio_cop, coalesce(p_controla_stock, true), p_stock_minimo,
          (select coalesce(max(orden), 0) + 1 from productos))
  returning id into v_id;
  -- Si hay caja abierta y maneja inventario, entra al cuadre de hoy con inicial 0
  if coalesce(p_controla_stock, true) then
    insert into cuadre_inventario(caja_id, producto_id, inicial)
    select id, v_id, 0 from cajas where cerrada_en is null
    on conflict (caja_id, producto_id) do nothing;
  end if;
  perform registrar_auditoria('crear_producto', 'productos', v_id,
          jsonb_build_object('nombre', v_nombre, 'precio', p_precio_cop));
  return jsonb_build_object('producto_id', v_id, 'nombre', v_nombre, 'precio_cop', p_precio_cop);
end $$;

-- 4. Permisos de las funciones nuevas (las reemplazadas conservan los suyos)
revoke execute on function public.exigir_encargado(),
  public.crear_producto(text, integer, uuid, boolean, integer) from public, anon, authenticated;
grant execute on function public.crear_producto(text, integer, uuid, boolean, integer) to authenticated;