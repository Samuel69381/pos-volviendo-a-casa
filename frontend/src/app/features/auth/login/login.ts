import { Component, inject, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { Auth } from '../../../core/auth/auth';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: './login.html',
  styleUrl: './login.scss'
})
export class Login {
  private readonly auth = inject(Auth);
  private readonly router = inject(Router);

  mostrarPassword = false;
  readonly cargando = signal(false);
  readonly errorServidor = signal<string | null>(null);

  loginForm = new FormGroup({
    usuario: new FormControl('', { nonNullable: true, validators: [Validators.required] }),
    password: new FormControl('', { nonNullable: true, validators: [Validators.required] })
  });

  togglePassword(): void {
    this.mostrarPassword = !this.mostrarPassword;
  }

  async iniciarSesion(): Promise<void> {
    if (this.loginForm.invalid) {
      this.loginForm.markAllAsTouched();
      return;
    }

    this.cargando.set(true);
    this.errorServidor.set(null);
    const { usuario, password } = this.loginForm.getRawValue();

    try {
      const perfil = await this.auth.iniciarSesion(usuario, password);
      // Primer ingreso con clave temporal → debe cambiarla antes de seguir
      await this.router.navigateByUrl(perfil.debe_cambiar_clave ? '/cambiar-clave' : '/inicio');
    } catch (e) {
      this.errorServidor.set(e instanceof Error ? e.message : 'Ocurrió un error inesperado');
      this.loginForm.controls.password.reset();
    } finally {
      this.cargando.set(false);
    }
  }
}