-- ============================================================
-- Seguridad: quién puede ver y modificar cada tabla desde la app
--
-- Regla general:
--   * Nadie sin sesión (anon) ve nada.
--   * Los empleados activos pueden LEER lo que necesitan para trabajar.
--   * Las operaciones de dinero e inventario solo se hacen con las funciones.
--   * El admin puede editar el catálogo (productos, categorías, medios de pago)
--     y los datos de los empleados.
-- ============================================================

-- Tablas nuevas que se creen en el futuro tampoco quedan abiertas
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- ------------------------------------------------------------
-- 1. Ayudante: ¿el usuario actual es un empleado activo?
-- ------------------------------------------------------------
create or replace function public.es_empleado()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo);
$$;
revoke execute on function public.es_empleado() from public, anon, authenticated;
grant execute on function public.es_empleado() to authenticated;

-- ------------------------------------------------------------
-- 2. Quitar todos los permisos directos sobre las tablas
-- ------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

-- ------------------------------------------------------------
-- 3. Activar RLS en las 17 tablas
-- ------------------------------------------------------------
alter table public.perfiles               enable row level security;
alter table public.categorias             enable row level security;
alter table public.productos              enable row level security;
alter table public.historial_precios      enable row level security;
alter table public.medios_pago            enable row level security;
alter table public.torneos                enable row level security;
alter table public.equipos                enable row level security;
alter table public.cajas                  enable row level security;
alter table public.turnos                 enable row level security;
alter table public.cuentas                enable row level security;
alter table public.ventas                 enable row level security;
alter table public.detalle_venta          enable row level security;
alter table public.pagos                  enable row level security;
alter table public.movimientos_inventario enable row level security;
alter table public.cuadre_inventario      enable row level security;
alter table public.gastos                 enable row level security;
alter table public.auditoria              enable row level security;

-- ------------------------------------------------------------
-- 4. Lectura (select)
-- ------------------------------------------------------------
grant select on all tables in schema public to authenticated;

-- Empleados: cada uno ve su propio perfil; el admin ve a todos
create policy perfiles_leer on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_admin());

-- Lo que cualquier empleado activo necesita para trabajar
create policy categorias_leer        on public.categorias             for select to authenticated using (public.es_empleado());
create policy productos_leer         on public.productos              for select to authenticated using (public.es_empleado());
create policy medios_pago_leer       on public.medios_pago            for select to authenticated using (public.es_empleado());
create policy torneos_leer           on public.torneos                for select to authenticated using (public.es_empleado());
create policy equipos_leer           on public.equipos                for select to authenticated using (public.es_empleado());
create policy cajas_leer             on public.cajas                  for select to authenticated using (public.es_empleado());
create policy turnos_leer            on public.turnos                 for select to authenticated using (public.es_empleado());
create policy cuentas_leer           on public.cuentas                for select to authenticated using (public.es_empleado());
create policy ventas_leer            on public.ventas                 for select to authenticated using (public.es_empleado());
create policy detalle_venta_leer     on public.detalle_venta          for select to authenticated using (public.es_empleado());
create policy pagos_leer             on public.pagos                  for select to authenticated using (public.es_empleado());
create policy movimientos_leer       on public.movimientos_inventario for select to authenticated using (public.es_empleado());
create policy cuadre_leer            on public.cuadre_inventario      for select to authenticated using (public.es_empleado());
create policy gastos_leer            on public.gastos                 for select to authenticated using (public.es_empleado());

-- Solo el admin
create policy historial_precios_leer on public.historial_precios      for select to authenticated using (public.es_admin());
create policy auditoria_leer         on public.auditoria              for select to authenticated using (public.es_admin());

-- ------------------------------------------------------------
-- 5. Escritura directa: solo el admin, solo en el catálogo y empleados,
--    y solo en las columnas permitidas (el stock y el costo NO: van por funciones)
-- ------------------------------------------------------------

-- Productos
grant insert (nombre, categoria_id, precio_cop, controla_stock, stock_minimo, orden) on public.productos to authenticated;
grant update (nombre, categoria_id, precio_cop, controla_stock, stock_minimo, orden, activo) on public.productos to authenticated;
create policy productos_crear  on public.productos for insert to authenticated with check (public.es_admin());
create policy productos_editar on public.productos for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- Categorías
grant insert (nombre, orden), update (nombre, orden) on public.categorias to authenticated;
create policy categorias_crear  on public.categorias for insert to authenticated with check (public.es_admin());
create policy categorias_editar on public.categorias for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- Medios de pago
grant insert (codigo, nombre, tipo, orden), update (nombre, tipo, orden, activo) on public.medios_pago to authenticated;
create policy medios_pago_crear  on public.medios_pago for insert to authenticated with check (public.es_admin());
create policy medios_pago_editar on public.medios_pago for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- Empleados: el admin edita datos, rol y estado (crearlos se hace con la Edge Function)
grant update (nombre_completo, celular, rol, activo) on public.perfiles to authenticated;
create policy perfiles_editar on public.perfiles for update to authenticated
  using (public.es_admin()) with check (public.es_admin());