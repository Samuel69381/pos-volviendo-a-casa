-- ============================================================
-- Permisos: las funciones nuevas NO quedan disponibles para todos.
-- Cada migración da permiso solo a las que la app debe poder llamar.
-- ============================================================
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- ============================================================
-- Ayudantes (uso interno de otras funciones)
-- ============================================================

-- Devuelve el empleado que inició sesión, o falla si no existe o está inactivo
create or replace function public.empleado_actual()
returns public.perfiles
language plpgsql stable security definer set search_path = public as $$
declare v public.perfiles;
begin
  select * into v from perfiles where id = auth.uid();
  if not found then raise exception 'Usuario no registrado como empleado'; end if;
  if not v.activo then raise exception 'Empleado inactivo: pide al administrador que lo active'; end if;
  return v;
end $$;

-- ¿El usuario actual es administrador activo?
create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'admin' and activo);
$$;

-- Falla si el usuario actual no es administrador
create or replace function public.exigir_admin()
returns public.perfiles
language plpgsql stable security definer set search_path = public as $$
declare v public.perfiles := empleado_actual();
begin
  if v.rol <> 'admin' then raise exception 'Solo el administrador puede hacer esta operación'; end if;
  return v;
end $$;

-- Devuelve la caja abierta, o falla
create or replace function public.caja_abierta_id()
returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  select id into v from cajas where cerrada_en is null;
  if v is null then raise exception 'No hay caja abierta'; end if;
  return v;
end $$;

-- Exige turno abierto en la caja abierta; devuelve la caja
create or replace function public.exigir_turno()
returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_caja uuid := caja_abierta_id();
begin
  perform empleado_actual();
  if not exists (select 1 from turnos where caja_id = v_caja and perfil_id = auth.uid() and fin is null) then
    raise exception 'No tienes turno abierto en la caja de hoy';
  end if;
  return v_caja;
end $$;

-- Deja rastro de cada acción en la tabla auditoria
create or replace function public.registrar_auditoria(p_accion text, p_tabla text, p_id uuid, p_detalles jsonb default '{}')
returns void
language sql security definer set search_path = public as $$
  insert into auditoria(usuario_id, accion, tabla, registro_id, detalles)
  values (auth.uid(), p_accion, p_tabla, p_id, coalesce(p_detalles, '{}'));
$$;

-- ============================================================
-- Caja y turnos
-- ============================================================

-- Abre la caja de la jornada, el turno de quien la abre y toma el inventario inicial
create or replace function public.abrir_caja(p_base_inicial bigint default 0)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := empleado_actual(); v_caja uuid;
begin
  if coalesce(p_base_inicial, 0) < 0 then raise exception 'La base no puede ser negativa'; end if;
  if exists (select 1 from cajas where cerrada_en is null) then
    raise exception 'Ya hay una caja abierta: ciérrala antes de abrir otra';
  end if;
  insert into cajas(abierta_por, base_inicial_cop) values (v_emp.id, coalesce(p_base_inicial, 0)) returning id into v_caja;
  insert into turnos(caja_id, perfil_id) values (v_caja, v_emp.id);
  -- Inventario inicial del día: foto del stock de cada producto
  insert into cuadre_inventario(caja_id, producto_id, inicial)
  select v_caja, id, stock from productos where controla_stock and activo;
  perform registrar_auditoria('abrir_caja', 'cajas', v_caja, jsonb_build_object('base', p_base_inicial));
  return jsonb_build_object('caja_id', v_caja, 'base_inicial_cop', coalesce(p_base_inicial, 0));
end $$;

-- El empleado se une a la caja abierta (se llama al iniciar sesión en la caja)
create or replace function public.iniciar_turno()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := empleado_actual(); v_caja uuid := caja_abierta_id(); v_turno uuid;
begin
  select id into v_turno from turnos where perfil_id = v_emp.id and fin is null;
  if v_turno is not null then
    -- Ya tenía turno: si es de esta caja lo reutiliza (entró desde otro celular)
    if exists (select 1 from turnos where id = v_turno and caja_id = v_caja) then
      return jsonb_build_object('turno_id', v_turno, 'caja_id', v_caja, 'reutilizado', true);
    end if;
    update turnos set fin = now() where id = v_turno;  -- turno viejo olvidado
  end if;
  insert into turnos(caja_id, perfil_id) values (v_caja, v_emp.id) returning id into v_turno;
  perform registrar_auditoria('iniciar_turno', 'turnos', v_turno);
  return jsonb_build_object('turno_id', v_turno, 'caja_id', v_caja, 'reutilizado', false);
end $$;

-- El empleado cierra su turno al salir
create or replace function public.finalizar_turno()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_turno uuid;
begin
  perform empleado_actual();
  update turnos set fin = now() where perfil_id = auth.uid() and fin is null returning id into v_turno;
  if v_turno is null then raise exception 'No tienes turno abierto'; end if;
  perform registrar_auditoria('finalizar_turno', 'turnos', v_turno);
  return jsonb_build_object('turno_id', v_turno);
end $$;

-- ============================================================
-- Quién puede llamar estas funciones desde la app
-- ============================================================
revoke execute on function
  public.empleado_actual(), public.es_admin(), public.exigir_admin(), public.caja_abierta_id(),
  public.exigir_turno(), public.registrar_auditoria(text, text, uuid, jsonb),
  public.abrir_caja(bigint), public.iniciar_turno(), public.finalizar_turno()
from public, anon, authenticated;

grant execute on function
  public.es_admin(), public.abrir_caja(bigint), public.iniciar_turno(), public.finalizar_turno()
to authenticated;