import { Routes } from '@angular/router';
import { cambioClaveGuard, invitadoGuard, sesionGuard } from './core/auth/auth.guards';

export const routes: Routes = [
  {
    path: 'login',
    canActivate: [invitadoGuard],
    loadComponent: () => import('./features/auth/login/login').then(m => m.Login)
  },
  {
    path: 'cambiar-clave',
    canActivate: [cambioClaveGuard],
    loadComponent: () => import('./features/auth/cambiar-clave/cambiar-clave').then(m => m.CambiarClave)
  },
  {
    path: 'inicio',
    canActivate: [sesionGuard],
    loadComponent: () => import('./features/inicio/inicio').then(m => m.Inicio)
  },
  { path: '', redirectTo: 'inicio', pathMatch: 'full' },
  { path: '**', redirectTo: 'inicio' }
];