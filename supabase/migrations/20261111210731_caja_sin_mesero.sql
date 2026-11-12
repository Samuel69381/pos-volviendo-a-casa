-- ============================================================
-- Abrir y cerrar la caja: admin o cajero. El mesero no.
-- (antes cualquier empleado podía abrirla y cualquiera en turno cerrarla)
-- Reutiliza el trigger bloquear_mesero() de la migración rol_mesero.
-- ============================================================

create trigger trg_mesero_abrir_caja
  before insert on public.cajas
  for each row
  execute function public.bloquear_mesero('El mesero no puede abrir la caja: pídele al cajero');


create trigger trg_mesero_cerrar_caja
  before update of cerrada_en on public.cajas
  for each row when (old.cerrada_en is null and new.cerrada_en is not null)
  execute function public.bloquear_mesero('El mesero no puede cerrar la caja: pídele al cajero');