import { computed, inject, Injectable, signal } from '@angular/core';
import { Supabase } from '../supabase';
import { Auth } from '../auth/auth';

export interface CajaAbierta {
  id: string;
  abierta_en: string;
  base_inicial_cop: number;
}

export interface Turno {
  id: string;
  inicio: string;
}

// Estado de la jornada: ¿hay caja abierta? ¿tengo turno en ella?
@Injectable({ providedIn: 'root' })
export class Caja {
  private readonly supabase = inject(Supabase).client;
  private readonly auth = inject(Auth);

  private readonly _caja = signal<CajaAbierta | null>(null);
  private readonly _turno = signal<Turno | null>(null);
  private readonly _cargado = signal(false);

  readonly caja = this._caja.asReadonly();
  readonly turno = this._turno.asReadonly();
  readonly cargado = this._cargado.asReadonly();
  readonly abierta = computed(() => this._caja() !== null);
  readonly enTurno = computed(() => this._turno() !== null);

  /** Consulta la caja abierta y mi turno en ella. */
  async cargar(): Promise<void> {
    const { data: caja, error } = await this.supabase
      .from('cajas')
      .select('id, abierta_en, base_inicial_cop')
      .is('cerrada_en', null)
      .maybeSingle();
    if (error) throw new Error('No se pudo consultar la caja. Revisa tu conexión');

    let turno: Turno | null = null;
    const miId = this.auth.perfil()?.id;
    if (caja && miId) {
      const { data } = await this.supabase
        .from('turnos')
        .select('id, inicio')
        .eq('caja_id', caja.id)
        .eq('perfil_id', miId)
        .is('fin', null)
        .maybeSingle();
      turno = data;
    }

    this._caja.set(caja);
    this._turno.set(turno);
    this._cargado.set(true);
  }

  /** Abre la caja del día. Quien la abre queda en turno de una vez. */
  async abrirCaja(baseInicial: number, notas: string): Promise<void> {
    const { error } = await this.supabase.rpc('abrir_caja', {
      p_base_inicial: baseInicial,
      p_notas: notas
    });
    if (error) throw new Error(error.message);
    await this.cargar();
  }

  /** Une al empleado a la caja que ya está abierta. */
  async iniciarTurno(): Promise<void> {
    const { error } = await this.supabase.rpc('iniciar_turno');
    if (error) throw new Error(error.message);
    await this.cargar();
  }
}