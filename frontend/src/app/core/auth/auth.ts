import { computed, inject, Injectable, signal } from '@angular/core';
import { Supabase } from '../supabase';
import { environment } from '../../../environments/environment';

export type Rol = 'admin' | 'cajero' | 'mesero';

export interface Perfil {
  id: string;
  usuario: string;
  nombre_completo: string;
  rol: Rol;
  debe_cambiar_clave: boolean;
}

@Injectable({ providedIn: 'root' })
export class Auth {
  private readonly supabase = inject(Supabase).client;

  // Estado de la sesión: lo leen los guards y las pantallas
  private readonly _perfil = signal<Perfil | null>(null);
  readonly perfil = this._perfil.asReadonly();
  readonly autenticado = computed(() => this._perfil() !== null);
  readonly esAdmin = computed(() => this._perfil()?.rol === 'admin');

  // Se resuelve una sola vez, al abrir la app, con la sesión guardada (si hay)
  private readonly listo: Promise<void> = this.restaurarSesion();

  /** Espera a que se revise la sesión guardada (lo usan los guards). */
  esperarSesion(): Promise<void> {
    return this.listo;
  }

  /** Inicia sesión con el usuario que le dio el admin (sin @pos.local). */
  async iniciarSesion(usuario: string, clave: string): Promise<Perfil> {
    const email = `${usuario.trim().toLowerCase()}@${environment.dominioUsuarios}`;
    const { error } = await this.supabase.auth.signInWithPassword({ email, password: clave });
    if (error) {
      throw new Error(
        error.message === 'Invalid login credentials'
          ? 'Usuario o contraseña incorrectos'
          : 'No se pudo iniciar sesión. Revisa tu conexión e intenta de nuevo'
      );
    }

    const perfil = await this.cargarPerfil();
    if (!perfil) {
      // Existe en Auth pero no tiene perfil o está desactivado
      await this.supabase.auth.signOut();
      throw new Error('Tu usuario está desactivado. Habla con el administrador');
    }
    return perfil;
  }

  /** Cambia la contraseña y quita la marca de clave temporal. */
  async cambiarClave(nueva: string): Promise<void> {
    const { error } = await this.supabase.auth.updateUser({ password: nueva });
    if (error) {
      throw new Error(
        error.code === 'same_password'
          ? 'La nueva contraseña debe ser distinta a la temporal'
          : 'No se pudo cambiar la contraseña. Intenta de nuevo'
      );
    }
    const { error: errorMarca } = await this.supabase.rpc('marcar_clave_cambiada');
    if (errorMarca) throw new Error('La clave cambió, pero no se pudo actualizar tu perfil. Intenta de nuevo');
    await this.cargarPerfil();
  }

  async cerrarSesion(): Promise<void> {
    await this.supabase.auth.signOut();
    this._perfil.set(null);
  }

  // Pide a la base quién es el usuario de la sesión (función mi_perfil)
  private async cargarPerfil(): Promise<Perfil | null> {
    const { data, error } = await this.supabase.rpc('mi_perfil');
    const perfil = !error && Array.isArray(data) && data.length > 0 ? (data[0] as Perfil) : null;
    this._perfil.set(perfil);
    return perfil;
  }

  private async restaurarSesion(): Promise<void> {
    const { data } = await this.supabase.auth.getSession();
    if (data.session) await this.cargarPerfil();
  }
}