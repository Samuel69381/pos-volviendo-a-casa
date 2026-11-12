-- Empleados: los crea el admin. Usuario y contraseña los asigna el admin.
create table public.perfiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  usuario         text not null unique check (usuario ~ '^[a-z0-9._]{3,30}$'),
  nombre_completo text not null check (length(trim(nombre_completo)) >= 5),
  cedula          text not null unique check (cedula ~ '^[0-9]{6,10}$'),
  celular         text not null check (celular ~ '^3[0-9]{9}$'),
  rol             public.rol_usuario not null,
  activo          boolean not null default true,
  fecha_ingreso   date not null default current_date,
  creado_en       timestamptz not null default now()
);