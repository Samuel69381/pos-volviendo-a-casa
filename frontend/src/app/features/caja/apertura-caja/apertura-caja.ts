import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { Auth } from '../../../core/auth/auth';
import { Caja } from '../../../core/caja/caja';

@Component({
  selector: 'app-apertura-caja',
  standalone: true,
  imports: [ReactiveFormsModule, DatePipe],
  templateUrl: './apertura-caja.html',
  styleUrl: './apertura-caja.scss'
})
export class AperturaCaja implements OnInit {
  protected readonly caja = inject(Caja);
  private readonly auth = inject(Auth);

  // El mesero no abre la caja (la base de datos también lo bloquea)
  readonly puedeAbrir = computed(() => this.auth.perfil()?.rol !== 'mesero');

  readonly cargando = signal(false);
  readonly errorServidor = signal<string | null>(null);

  aperturaForm = new FormGroup({
    montoInicial: new FormControl<number | null>(null, {
      validators: [Validators.required, Validators.min(0)]
    }),
    observaciones: new FormControl('', {
      nonNullable: true,
      validators: [Validators.maxLength(500)]
    })
  });

  async ngOnInit(): Promise<void> {
    await this.ejecutar(() => this.caja.cargar());
  }

  async abrirCaja(): Promise<void> {
    if (this.aperturaForm.invalid) {
      this.aperturaForm.markAllAsTouched();
      return;
    }
    const { montoInicial, observaciones } = this.aperturaForm.getRawValue();
    await this.ejecutar(() => this.caja.abrirCaja(montoInicial ?? 0, observaciones));
  }

  async iniciarTurno(): Promise<void> {
    await this.ejecutar(() => this.caja.iniciarTurno());
  }

  cancelar(): void {
    this.aperturaForm.reset();
    this.errorServidor.set(null);
  }

  /** Formato de pesos colombianos: 150000 → $150.000 */
  cop(valor: number): string {
    return '$' + valor.toLocaleString('es-CO');
  }

  // Patrón común: cargando → acción → error si falla
  private async ejecutar(accion: () => Promise<void>): Promise<void> {
    this.cargando.set(true);
    this.errorServidor.set(null);
    try {
      await accion();
    } catch (e) {
      this.errorServidor.set(e instanceof Error ? e.message : 'Ocurrió un error inesperado');
    } finally {
      this.cargando.set(false);
    }
  }
}