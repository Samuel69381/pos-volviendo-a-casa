-- Torneos: cada torneo que se juega en la finca
create table public.torneos (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null unique,
  fecha_inicio date,
  fecha_fin    date,
  activo       boolean not null default true,
  check (fecha_fin is null or fecha_inicio is null or fecha_fin >= fecha_inicio)
);

-- Equipos inscritos en un torneo.
-- El encargado aquí es el habitual y sirve para autollenar la cuenta del día.
create table public.equipos (
  id                uuid primary key default gen_random_uuid(),
  torneo_id         uuid not null references public.torneos(id),
  nombre            text not null,
  encargado_nombre  text,
  encargado_celular text check (encargado_celular is null or encargado_celular ~ '^3[0-9]{9}$'),
  activo            boolean not null default true,
  unique (torneo_id, nombre)
);