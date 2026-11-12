-- Cajas: cada jornada de trabajo. Se abre con una base y se cierra con el arqueo.
create table public.cajas (
  id                    uuid primary key default gen_random_uuid(),
  abierta_por           uuid not null references public.perfiles(id),
  abierta_en            timestamptz not null default now(),
  base_inicial_cop      bigint not null default 0 check (base_inicial_cop >= 0),
  cerrada_por           uuid references public.perfiles(id),
  cerrada_en            timestamptz,
  efectivo_esperado_cop bigint,
  efectivo_contado_cop  bigint,
  notas                 text,
  check (cerrada_en is null or (efectivo_contado_cop is not null and efectivo_esperado_cop is not null))
);

-- Solo puede existir UNA caja abierta a la vez
create unique index una_caja_abierta on public.cajas ((true)) where cerrada_en is null;

-- Turnos: quién trabaja en cada caja y en qué horario
create table public.turnos (
  id        uuid primary key default gen_random_uuid(),
  caja_id   uuid not null references public.cajas(id),
  perfil_id uuid not null references public.perfiles(id),
  inicio    timestamptz not null default now(),
  fin       timestamptz,
  notas     text,
  check (fin is null or fin > inicio)
);

-- Un empleado no puede tener dos turnos abiertos al mismo tiempo
create unique index un_turno_abierto_por_empleado on public.turnos (perfil_id) where fin is null;