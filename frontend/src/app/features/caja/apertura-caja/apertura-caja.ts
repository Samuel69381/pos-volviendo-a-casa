import { Component, signal } from '@angular/core';
import {
  FormControl,
  FormGroup,
  ReactiveFormsModule,
  Validators
} from '@angular/forms';

@Component({
  selector: 'app-apertura-caja',
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: './apertura-caja.html',
  styleUrl: './apertura-caja.scss'
})
export class AperturaCaja {

  cajaAbierta = signal(false);

  mensaje = signal('');

  aperturaForm = new FormGroup({
    montoInicial: new FormControl<number | null>(null, {
      validators: [
        Validators.required,
        Validators.min(0)
      ]
    }),

    observaciones: new FormControl('', {
      nonNullable: true,
      validators: [Validators.maxLength(500)]
    })
  });

  abrirCaja(): void {
    if (this.aperturaForm.invalid) {
      this.aperturaForm.markAllAsTouched();
      return;
    }

    const datos = this.aperturaForm.getRawValue();

    // Por ahora solo validamos el formulario.
    // Aquí conectaremos posteriormente la apertura real con Supabase.
    console.log('Datos de apertura:', datos);

    this.mensaje.set(
      'Formulario validado. Pendiente registrar la apertura en Supabase.'
    );
  }

  cancelar(): void {
    this.aperturaForm.reset();
    this.mensaje.set('');
  }
}