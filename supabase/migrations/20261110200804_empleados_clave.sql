-- ============================================================
-- Contraseña temporal: quien la recibe del admin debe cambiarla al primer ingreso
-- ============================================================

-- true = el empleado entra con una contraseña temporal y la app le pide cambiarla
alter table public.perfiles add column debe_cambiar_clave boolean not null default false;

-- Datos del empleado que inició sesión (la app la llama al entrar)
create or replace function public.mi_perfil()
returns table (id uuid, usuario text, nombre_completo text, rol public.rol_usuario, debe_cambiar_clave boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.usuario, p.nombre_completo, p.rol, p.debe_cambiar_clave
  from perfiles p
  where p.id = auth.uid() and p.activo;
$$;

-- La app la llama después de que el empleado cambia su contraseña
create or replace function public.marcar_clave_cambiada()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp public.perfiles := empleado_actual();
begin
  update perfiles set debe_cambiar_clave = false where id = v_emp.id;
  perform registrar_auditoria('cambiar_clave', 'perfiles', v_emp.id);
  return jsonb_build_object('usuario', v_emp.usuario, 'debe_cambiar_clave', false);
end $$;

-- ============================================================
-- Quién puede llamar estas funciones desde la app
-- ============================================================
revoke execute on function public.mi_perfil(), public.marcar_clave_cambiada() from public, anon, authenticated;
grant  execute on function public.mi_perfil(), public.marcar_clave_cambiada() to authenticated;