import { inject } from "@angular/core";
import { CanActivateFn, Router } from "@angular/router";
import { Auth } from "./auth";

export const sesionGuard: CanActivateFn = async () => {
  const auth = inject(Auth);
  const router = inject(Router);
  await auth.esperarSesion();
  const perfil = auth.perfil();
  if (!perfil) return router.createUrlTree(['/login']);
  if (perfil.debe_cambiar_clave) return router.createUrlTree(['/cambiar-clave']);
  return true;
};

// Pantalla de cambio de clave: solo con sesión
export const cambioClaveGuard: CanActivateFn = async () => {
  const auth = inject(Auth);
  const router = inject(Router);
  await auth.esperarSesion();
  return auth.perfil() ? true : router.createUrlTree(['/login']);
};

export const invitadoGuard: CanActivateFn = async () => {
  const auth = inject(Auth);
  const router = inject(Router);
  await auth.esperarSesion();
  return auth.perfil() ? router.createUrlTree(['/inicio']) : true;
};