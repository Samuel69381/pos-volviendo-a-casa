-- ============================================================
-- abrir_caja ahora recibe observaciones (opcional) y las guarda en cajas.notas
-- ============================================================

-- Se borra la versión anterior porque cambia la lista de parámetros
drop function public.abrir_caja(bigint);

create function public.abrir_caja(p_base_inicial bigint default 0, p_notas text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := empleado_actual(); v_caja uuid;
begin
  if coalesce(p_base_inicial, 0) < 0 then raise exception 'La base no puede ser negativa'; end if;
  if exists (select 1 from cajas where cerrada_en is null) then
    raise exception 'Ya hay una caja abierta: ciérrala antes de abrir otra';
  end if;
  insert into cajas(abierta_por, base_inicial_cop, notas)
  values (v_emp.id, coalesce(p_base_inicial, 0), nullif(trim(p_notas), ''))
  returning id into v_caja;
  insert into turnos(caja_id, perfil_id) values (v_caja, v_emp.id);
  -- Inventario inicial del día: foto del stock de cada producto
  insert into cuadre_inventario(caja_id, producto_id, inicial)
  select v_caja, id, stock from productos where controla_stock and activo;
  perform registrar_auditoria('abrir_caja', 'cajas', v_caja, jsonb_build_object('base', p_base_inicial));
  return jsonb_build_object('caja_id', v_caja, 'base_inicial_cop', coalesce(p_base_inicial, 0));
end $$;

revoke execute on function public.abrir_caja(bigint, text) from public, anon, authenticated;
grant  execute on function public.abrir_caja(bigint, text) to authenticated;