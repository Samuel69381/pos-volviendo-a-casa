import { Component, inject, signal } from '@angular/core';
import {
  AbstractControl, FormControl, FormGroup, ReactiveFormsModule, ValidationErrors, Validators
} from '@angular/forms';
import { Router } from '@angular/router';
import { Auth } from '../../../core/auth/auth';

// Las dos contraseñas deben ser iguales
function clavesIguales(grupo: AbstractControl): ValidationErrors | null {
  const nueva = grupo.get('nueva')?.value;
  const confirmar = grupo.get('confirmar')?.value;
  return nueva && confirmar && nueva !== confirmar ? { noCoinciden: true } : null;
}

@Component({
  selector: 'app-cambiar-clave',
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: './cambiar-clave.html',
  styleUrl: '../login/login.scss' // reutiliza el diseño del login
})
export class CambiarClave {
  protected readonly auth = inject(Auth);
  private readonly router = inject(Router);

  readonly cargando = signal(false);
  readonly errorServidor = signal<string | null>(null);

  form = new FormGroup(
    {
      nueva: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.minLength(8)] }),
      confirmar: new FormControl('', { nonNullable: true, validators: [Validators.required] })
    },
    { validators: clavesIguales }
  );

  async guardar(): Promise<void> {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    this.cargando.set(true);
    this.errorServidor.set(null);
    try {
      await this.auth.cambiarClave(this.form.getRawValue().nueva);
      await this.router.navigateByUrl('/inicio');
    } catch (e) {
      this.errorServidor.set(e instanceof Error ? e.message : 'Ocurrió un error inesperado');
    } finally {
      this.cargando.set(false);
    }
  }

  async salir(): Promise<void> {
    await this.auth.cerrarSesion();
    await this.router.navigateByUrl('/login');
  }
}