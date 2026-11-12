-- Categorías: agrupan los productos (Cervezas, Bebidas, Mecato)
create table public.categorias (
  id     uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  orden  int  not null default 0
);

-- Productos que se venden
create table public.productos (
  id             uuid primary key default gen_random_uuid(),
  nombre         text not null unique,
  categoria_id   uuid references public.categorias(id),
  precio_cop     integer not null check (precio_cop > 0),
  costo_cop      integer not null default 0 check (costo_cop >= 0),
  controla_stock boolean not null default true,
  stock          integer not null default 0 check (stock >= 0),
  stock_minimo   integer not null default 5 check (stock_minimo >= 0),
  orden          int not null default 0,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now()
);

-- Cada cambio de precio queda guardado
create table public.historial_precios (
  id              bigint generated always as identity primary key,
  producto_id     uuid not null references public.productos(id),
  precio_anterior integer not null,
  precio_nuevo    integer not null,
  cambiado_por    uuid references public.perfiles(id),
  cambiado_en     timestamptz not null default now()
);

-- Medios de pago: solo es un registro de cómo pagó el cliente.
-- No cobra ni se conecta con Nequi o Bancolombia.
create table public.medios_pago (
  codigo text primary key check (codigo ~ '^[a-z_]{3,20}$'),
  nombre text not null unique,
  tipo   public.tipo_medio not null,
  orden  int not null default 0,
  activo boolean not null default true
);