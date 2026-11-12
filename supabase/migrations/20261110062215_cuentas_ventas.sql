-- Cuentas abiertas: se abren el día del partido a nombre del equipo (o de una persona)
-- y llevan siempre un encargado con nombre y celular.
create table public.cuentas (
  id                uuid primary key default gen_random_uuid(),
  numero_cuenta     bigint generated always as identity unique,
  equipo_id         uuid references public.equipos(id),          -- vacío = cuenta particular
  nombre_cuenta     text not null,                                -- lo que se busca: "WICHO FC" o "Carlos Díaz"
  encargado_nombre  text not null check (length(trim(encargado_nombre)) >= 3),
  encargado_celular text not null check (encargado_celular ~ '^3[0-9]{9}$'),
  caja_id           uuid not null references public.cajas(id),   -- jornada en que se abrió
  abierta_por       uuid not null references public.perfiles(id),
  abierta_en        timestamptz not null default now(),
  estado            public.estado_cuenta not null default 'abierta',
  total_cop         bigint not null default 0 check (total_cop >= 0),
  pagado_cop        bigint not null default 0 check (pagado_cop >= 0),
  cerrada_por       uuid references public.perfiles(id),
  cerrada_en        timestamptz,
  notas             text,
  check (pagado_cop <= total_cop),
  check (estado = 'abierta' or cerrada_en is not null)
);

-- Un equipo no puede tener dos cuentas abiertas al mismo tiempo
create unique index una_cuenta_abierta_por_equipo on public.cuentas (equipo_id) where estado = 'abierta';

-- Cada pedido es una venta: de contado (se paga ya) o cargada a una cuenta abierta
create table public.ventas (
  id               uuid primary key default gen_random_uuid(),
  numero_venta     bigint generated always as identity unique,
  tipo             public.tipo_venta not null,
  cuenta_id        uuid references public.cuentas(id),
  nombre_cliente   text,                                          -- opcional en contado
  caja_id          uuid not null references public.cajas(id),
  creada_por       uuid not null references public.perfiles(id),
  creada_en        timestamptz not null default now(),
  estado           public.estado_venta not null default 'registrada',
  total_cop        bigint not null default 0 check (total_cop >= 0),
  notas            text,
  anulada_por      uuid references public.perfiles(id),
  anulada_en       timestamptz,
  motivo_anulacion text,
  check ((tipo = 'cuenta' and cuenta_id is not null) or (tipo = 'contado' and cuenta_id is null)),
  check (estado <> 'anulada' or (anulada_por is not null and motivo_anulacion is not null))
);

-- Productos de cada pedido. Copia nombre, precio y costo del momento de la venta.
create table public.detalle_venta (
  id                  uuid primary key default gen_random_uuid(),
  venta_id            uuid not null references public.ventas(id) on delete restrict,
  producto_id         uuid not null references public.productos(id),
  nombre_producto     text not null,
  precio_unitario_cop integer not null check (precio_unitario_cop > 0),
  costo_unitario_cop  integer not null default 0,
  cantidad            integer not null check (cantidad > 0),
  subtotal_cop        bigint generated always as (precio_unitario_cop::bigint * cantidad) stored
);

-- Pagos: registro de cómo pagó el cliente.
-- Es de una venta de contado o de una cuenta, nunca de las dos.
create table public.pagos (
  id           uuid primary key default gen_random_uuid(),
  venta_id     uuid references public.ventas(id) on delete restrict,
  cuenta_id    uuid references public.cuentas(id) on delete restrict,
  caja_id      uuid not null references public.cajas(id),
  monto_cop    bigint not null check (monto_cop > 0),
  medio_pago   text not null references public.medios_pago(codigo),
  recibido_por uuid not null references public.perfiles(id),
  pagado_en    timestamptz not null default now(),
  anulado      boolean not null default false,
  nota         text,
  check (num_nonnulls(venta_id, cuenta_id) = 1)
);
