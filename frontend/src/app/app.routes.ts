
import { Routes } from '@angular/router';

import {
  cambioClaveGuard,
  invitadoGuard,
  sesionGuard
} from './core/auth/auth.guards';

import { MainLayout } from './shared/layout/main-layout/main-layout';

import { AperturaCaja } from './features/caja/apertura-caja/apertura-caja';

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

  // INICIO
  {
    path: 'inicio',
    canActivate: [sesionGuard],
    loadComponent: () =>
      import('./features/inicio/inicio')
        .then(m => m.Inicio)
  },

  // MÓDULO DE CAJA
  {
    path: 'caja',
    component: MainLayout,
    canActivate: [sesionGuard],
    children: [
      {
        path: '',
        redirectTo: 'apertura',
        pathMatch: 'full'
      },
      {
        path: 'apertura',
        component: AperturaCaja
      }
    ]
  },

  // RUTA PRINCIPAL
  {
    path: '',
    redirectTo: 'inicio',
    pathMatch: 'full'
  },

  // RUTA NO ENCONTRADA
  {
    path: '**',
    redirectTo: 'inicio'
  }

];
