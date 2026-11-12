-- ============================================================
-- Índices para las consultas más frecuentes
-- ============================================================
create index on public.equipos (torneo_id);
create index on public.cuentas (estado, nombre_cuenta);
create index on public.cuentas (caja_id);
create index on public.ventas (cuenta_id) where estado = 'registrada';
create index on public.ventas (caja_id);
create index on public.ventas (creada_en desc);
create index on public.turnos (caja_id);
create index on public.detalle_venta (venta_id);
create index on public.pagos (venta_id);
create index on public.pagos (cuenta_id);
create index on public.pagos (caja_id);
create index on public.cuadre_inventario (caja_id);
create index on public.movimientos_inventario (producto_id, creado_en desc);
create index on public.movimientos_inventario (caja_id);
create index on public.gastos (caja_id);

-- ============================================================
-- Datos iniciales
-- ============================================================
insert into public.categorias (nombre, orden) values
  ('Cervezas', 1),
  ('Bebidas',  2),
  ('Mecato',   3);

insert into public.medios_pago (codigo, nombre, tipo, orden) values
  ('efectivo',    'Efectivo',    'efectivo',      1),
  ('nequi',       'Nequi',       'transferencia', 2),
  ('bancolombia', 'Bancolombia', 'transferencia', 3);

insert into public.torneos (nombre) values ('Volviendo a Casa');

insert into public.equipos (torneo_id, nombre)
select t.id, e.nombre
from public.torneos t,
     (values ('WICHO FC'),('CERVECEROS FC'),('EVERT-ON FC'),('ELEGIDOS FC'),
             ('AMIGOS DE JUANCHO FC'),('LA BANDA DEL NEGRO'),('PUPILOS DE BLACHO'),
             ('LA BANDA DEL 2009'),('KUTUPLO'),('THE LEGENDS'),('PEÑATE Y SUS MELLOS FC'),
             ('COCA JRS'),('LA CREW'),('SISO WARRIOS'),('HERMANOS INTER'),('ITALIA 2K17'),
             ('CAPATAZ FC'),('PROMO 2001 FC'),('LA BANDA DEL TRAQUI'),('FC 2015'),
             ('LA BANDA DEL 66'),('LA BANDA DE RODO'),('SOBREVIVIENTES'),('HOOLIGANS')) as e(nombre)
where t.nombre = 'Volviendo a Casa';

insert into public.productos (nombre, precio_cop, categoria_id, orden)
select v.nombre, v.precio, c.id, v.orden
from (values ('Águila Negra', 4000, 'Cervezas', 1),
             ('Costeña',      3500, 'Cervezas', 2),
             ('Gatorade',     5000, 'Bebidas',  3),
             ('Agua',         1000, 'Bebidas',  4),
             ('De Todito',    5000, 'Mecato',   5),
             ('Coca cola',    4000, 'Bebidas',  6)) as v(nombre, precio, categoria, orden)
join public.categorias c on c.nombre = v.categoria;
