import { Routes } from '@angular/router';

import {
  cambioClaveGuard,
  invitadoGuard,
  sesionGuard
} from './core/auth/auth.guards';

export const routes: Routes = [

  // LOGIN
  {
    path: 'login',
    canActivate: [invitadoGuard],
    loadComponent: () =>
      import('./features/auth/login/login')
        .then(m => m.Login)
  },

  // CAMBIO DE CONTRASEÑA
  {
    path: 'cambiar-clave',
    canActivate: [cambioClaveGuard],
    loadComponent: () =>
      import('./features/auth/cambiar-clave/cambiar-clave')
        .then(m => m.CambiarClave)
  },

  // INICIO: por ahora lleva a la caja
  {
    path: 'inicio',
    redirectTo: 'caja',
    pathMatch: 'full'
  },

  // MÓDULO DE CAJA
  {
    path: 'caja',
    loadComponent: () =>
      import('./shared/layout/main-layout/main-layout')
        .then(m => m.MainLayout),
    canActivate: [sesionGuard],
    children: [
      {
        path: '',
        redirectTo: 'apertura',
        pathMatch: 'full'
      },
      {
        path: 'apertura',
        loadComponent: () =>
          import('./features/caja/apertura-caja/apertura-caja')
            .then(m => m.AperturaCaja)
      },
      {
        path: 'ventas',
        loadComponent: () =>
          import('./features/ventas/vender/vender')
            .then(m => m.Vender)
      },
      {
        path: 'venta',
        loadComponent: () =>
          import('./features/ventas/venta/venta')
            .then(m => m.Venta)
      },
      {
        path: 'cuentas',
        loadComponent: () =>
          import('./features/cuentas/cuentas-abiertas/cuentas-abiertas')
            .then(m => m.CuentasAbiertas)
      }
    ]
  },

  // RUTA PRINCIPAL
  {
    path: '',
    redirectTo: 'caja',
    pathMatch: 'full'
  },

  // RUTA NO ENCONTRADA (siempre al final)
  {
    path: '**',
    redirectTo: 'caja'
  }
];