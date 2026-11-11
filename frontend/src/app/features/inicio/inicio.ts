import { Component, inject } from '@angular/core';
import { Router } from '@angular/router';
import { Auth } from '../../core/auth/auth';

// Pantalla temporal para comprobar el login. Luego será la pantalla de Vender.
@Component({
  selector: 'app-inicio',
  standalone: true,
  template: `
    <main style="padding: 24px; font-family: Inter, sans-serif">
      <h1>Hola, {{ auth.perfil()?.nombre_completo }}</h1>
      <p>Usuario: <b>{{ auth.perfil()?.usuario }}</b> · Rol: <b>{{ auth.perfil()?.rol }}</b></p>
      <button type="button" (click)="salir()">Cerrar sesión</button>
    </main>
  `
})
export class Inicio {
  protected readonly auth = inject(Auth);
  private readonly router = inject(Router);

  async salir(): Promise<void> {
    await this.auth.cerrarSesion();
    await this.router.navigateByUrl('/login');
  }
}