import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { Auth } from '../auth/auth';
import { Caja } from './caja';

// Pantallas de trabajo (vender, cuentas...): exigen caja abierta y turno activo
export const turnoGuard: CanActivateFn = async () => {
  const auth = inject(Auth);
  const caja = inject(Caja);
  const router = inject(Router);

  await auth.esperarSesion();

  try {
    await caja.cargar();
  } catch {
    // Sin conexión: mejor llevarlo a la caja, donde ve el error
    return router.createUrlTree(['/caja/apertura']);
  }

  return caja.enTurno() ? true : router.createUrlTree(['/caja/apertura']);
};
