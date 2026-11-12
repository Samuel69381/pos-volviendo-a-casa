-- ============================================================
-- Rol mesero: toma pedidos y los carga a cuentas, pero no maneja dinero
-- ============================================================

-- 1. Nuevo valor en el tipo de rol
alter type public.rol_usuario add value if not exists 'mesero';

-- 2. ¿El usuario de la sesión es mesero?
--    (se compara como texto porque el valor nuevo aún no está confirmado dentro de esta migración)
create or replace function public.es_mesero()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo and rol::text = 'mesero');
$$;

-- 3. Un solo trigger que bloquea al mesero. El mensaje llega como argumento (TG_ARGV[0]).
create or replace function public.bloquear_mesero()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if es_mesero() then
    raise exception '%', tg_argv[0];
  end if;
  return new;
end $$;

-- Ventas de contado: el mesero no recibe dinero
create trigger trg_mesero_contado
  before insert on public.ventas
  for each row when (new.tipo = 'contado')
  execute function public.bloquear_mesero('El mesero no puede cobrar: carga el pedido a una cuenta');

-- Pagos de cuentas (y cualquier otro pago)
create trigger trg_mesero_pagos
  before insert on public.pagos
  for each row
  execute function public.bloquear_mesero('El mesero no puede registrar pagos: pídele al cajero que cobre');

-- Gastos con el efectivo de la caja
create trigger trg_mesero_gastos
  before insert on public.gastos
  for each row
  execute function public.bloquear_mesero('El mesero no puede registrar gastos');

-- Conteo de inventario
create trigger trg_mesero_conteo
  before insert or update of contado on public.cuadre_inventario
  for each row when (new.contado is not null)
  execute function public.bloquear_mesero('El conteo de inventario lo hace el cajero');

-- Anular cuentas
create trigger trg_mesero_anular_cuenta
  before update of estado on public.cuentas
  for each row when (new.estado = 'anulada')
  execute function public.bloquear_mesero('El mesero no puede anular cuentas');

-- 4. Permisos: es_mesero la usa la app; bloquear_mesero solo los triggers
revoke execute on function public.es_mesero(), public.bloquear_mesero() from public, anon, authenticated;
grant  execute on function public.es_mesero() to authenticated;