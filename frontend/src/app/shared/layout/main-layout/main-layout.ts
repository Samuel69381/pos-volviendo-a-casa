import { Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { Auth } from '../../../core/auth/auth';

const NOMBRES_ROL = { admin: 'Administrador', cajero: 'Cajero', mesero: 'Mesero' } as const;

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './main-layout.html',
  styleUrl: './main-layout.scss'
})
export class MainLayout {
  private readonly auth = inject(Auth);
  private readonly router = inject(Router);

  menuAbierto = signal(false);

  // Datos del empleado que inició sesión
  readonly empleado = computed(() => this.auth.perfil()?.nombre_completo ?? '');
  readonly rol = computed(() => {
    const rol = this.auth.perfil()?.rol;
    return rol ? NOMBRES_ROL[rol] : '';
  });

  alternarMenu(): void {
    this.menuAbierto.update(valor => !valor);
  }

  cerrarMenu(): void {
    this.menuAbierto.set(false);
  }

  async cerrarSesion(): Promise<void> {
    this.cerrarMenu();
    await this.auth.cerrarSesion();
    await this.router.navigateByUrl('/login');
  }
}