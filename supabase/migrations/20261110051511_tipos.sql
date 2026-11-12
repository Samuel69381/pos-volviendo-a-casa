-- Extensión para generar identificadores únicos (uuid)
create extension if not exists pgcrypto;

-- Tipos con valores fijos (enums)
create type public.rol_usuario     as enum ('admin','cajero');
create type public.tipo_venta      as enum ('contado','cuenta');
create type public.estado_venta    as enum ('registrada','anulada');
create type public.estado_cuenta   as enum ('abierta','pagada','anulada');
create type public.tipo_medio      as enum ('efectivo','transferencia');
create type public.tipo_movimiento as enum ('compra','venta','ajuste','conteo','devolucion_anulacion');