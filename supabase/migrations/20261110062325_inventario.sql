-- Kardex: cada entrada o salida de un producto
create table public.movimientos_inventario (
  id                 uuid primary key default gen_random_uuid(),
  producto_id        uuid not null references public.productos(id),
  tipo_movimiento    public.tipo_movimiento not null,
  cantidad           integer not null check (cantidad <> 0),
  stock_resultante   integer not null check (stock_resultante >= 0),
  costo_unitario_cop integer check (costo_unitario_cop >= 0),
  proveedor          text,
  venta_id           uuid references public.ventas(id),
  caja_id            uuid references public.cajas(id),            -- jornada en que ocurrió
  creado_por         uuid not null references public.perfiles(id),
  creado_en          timestamptz not null default now(),
  nota               text
);

-- Cuadre de inventario por jornada: el inicial se toma al abrir la caja, el conteo lo
-- escribe el empleado al final, y al cerrar la caja se guarda el "debe haber" y el stock
-- se corrige a lo contado.
create table public.cuadre_inventario (
  id          uuid primary key default gen_random_uuid(),
  caja_id     uuid not null references public.cajas(id),
  producto_id uuid not null references public.productos(id),
  inicial     integer not null default 0,
  debe_haber  integer,
  contado     integer check (contado >= 0),
  diferencia  integer generated always as (contado - debe_haber) stored,
  contado_por uuid references public.perfiles(id),
  contado_en  timestamptz,
  unique (caja_id, producto_id)
);

-- Gastos pagados con el efectivo de la caja
create table public.gastos (
  id          uuid primary key default gen_random_uuid(),
  caja_id     uuid not null references public.cajas(id),
  monto_cop   bigint not null check (monto_cop > 0),
  categoria   text not null,
  descripcion text,
  pagado_por  uuid not null references public.perfiles(id),
  creado_en   timestamptz not null default now()
);

-- Auditoría: registro de quién hizo cada acción
create table public.auditoria (
  id          bigint generated always as identity primary key,
  usuario_id  uuid references public.perfiles(id),
  accion      text not null,
  tabla       text not null,
  registro_id uuid,
  detalles    jsonb not null default '{}',
  creado_en   timestamptz not null default now()
);