-- ============================================================
-- Torneos y equipos: el admin los administra desde la app.
-- La cantidad de equipos no es fija: cada torneo tiene los que se inscriban.
-- ============================================================

-- Crea un torneo nuevo
create or replace function public.crear_torneo(
  p_nombre       text,
  p_fecha_inicio date default null,
  p_fecha_fin    date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin public.perfiles := exigir_admin(); v_id uuid;
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
declare v_admin public.perfiles := exigir_admin(); t public.torneos; v_id uuid; v_nombre text := upper(trim(p_nombre));
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

-- Retira un equipo sin borrarlo: sus cuentas y ventas quedan intactas
create or replace function public.desactivar_equipo(p_equipo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin public.perfiles := exigir_admin(); e public.equipos;
begin
  select * into e from equipos where id = p_equipo_id for update;
  if not found then raise exception 'Equipo no encontrado'; end if;
  if exists (select 1 from cuentas where equipo_id = e.id and estado = 'abierta') then
    raise exception '% tiene una cuenta abierta: cóbrala antes de desactivarlo', e.nombre;
  end if;
  update equipos set activo = false where id = e.id;
  perform registrar_auditoria('desactivar_equipo', 'equipos', e.id, jsonb_build_object('equipo', e.nombre));
  return jsonb_build_object('equipo_id', e.id, 'nombre', e.nombre, 'activo', false);
end $$;

-- Marca un torneo como terminado; sus equipos dejan de aparecer para abrir cuentas
create or replace function public.finalizar_torneo(p_torneo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin public.perfiles := exigir_admin(); t public.torneos; v_abiertas int;
begin
  select * into t from torneos where id = p_torneo_id for update;
  if not found then raise exception 'Torneo no encontrado'; end if;
  select count(*) into v_abiertas
  from cuentas c join equipos e on e.id = c.equipo_id
  where e.torneo_id = t.id and c.estado = 'abierta';
  if v_abiertas > 0 then
    raise exception 'Hay % cuenta(s) abiertas de equipos de este torneo: cóbralas antes de finalizarlo', v_abiertas;
  end if;
  update torneos set activo = false, fecha_fin = coalesce(fecha_fin, current_date) where id = t.id;
  perform registrar_auditoria('finalizar_torneo', 'torneos', t.id, jsonb_build_object('torneo', t.nombre));
  return jsonb_build_object('torneo_id', t.id, 'nombre', t.nombre, 'activo', false);
end $$;

-- Lista los equipos activos de los torneos activos (lo que ve el cajero al abrir una cuenta)
create or replace function public.equipos_disponibles(p_texto text default '')
returns table (equipo_id uuid, equipo text, torneo text, encargado_nombre text, encargado_celular text, tiene_cuenta_abierta boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.nombre, t.nombre, e.encargado_nombre, e.encargado_celular,
         exists (select 1 from cuentas c where c.equipo_id = e.id and c.estado = 'abierta')
  from equipos e join torneos t on t.id = e.torneo_id
  where (select empleado_actual()) is not null
    and e.activo and t.activo
    and (coalesce(trim(p_texto), '') = ''
         or translate(lower(e.nombre), 'áéíóúüñ', 'aeiouun')
            like '%' || translate(lower(trim(p_texto)), 'áéíóúüñ', 'aeiouun') || '%')
  order by t.nombre, e.nombre;
$$;

-- ============================================================
-- Quién puede llamar estas funciones desde la app
-- ============================================================
revoke execute on function
  public.crear_torneo(text, date, date), public.inscribir_equipo(uuid, text, text, text),
  public.desactivar_equipo(uuid), public.finalizar_torneo(uuid), public.equipos_disponibles(text)
from public, anon, authenticated;

grant execute on function
  public.crear_torneo(text, date, date), public.inscribir_equipo(uuid, text, text, text),
  public.desactivar_equipo(uuid), public.finalizar_torneo(uuid), public.equipos_disponibles(text)
to authenticated;