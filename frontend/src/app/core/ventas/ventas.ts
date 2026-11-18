import { inject, Injectable } from '@angular/core';
import { Supabase } from '../supabase';
import { Carrito } from './carrito';

// Códigos de la tabla medios_pago
export type MedioPago = 'efectivo' | 'nequi' | 'bancolombia';

export interface Pago {
  medio: MedioPago;
  monto: number;
}

export interface VentaRegistrada {
  venta_id: string;
  numero_venta: number;
  total_cop: number;
}

@Injectable({ providedIn: 'root' })
export class Ventas {
  private readonly supabase = inject(Supabase).client;
  private readonly carrito = inject(Carrito);

  /** Venta de contado: se cobra en el momento. Si sale bien, vacía el carrito. */
  async registrarContado(pagos: Pago[], cliente: string, notas: string): Promise<VentaRegistrada> {
    if (this.carrito.vacio()) throw new Error('El carrito está vacío');

    const { data, error } = await this.supabase.rpc('registrar_venta', {
      p_items: this.carrito.paraRegistrar(),
      p_pagos: pagos.filter(pago => pago.monto > 0),
      p_nombre_cliente: cliente.trim() || null,
      p_notas: notas.trim() || null
    });
    if (error) throw new Error(error.message);

    this.carrito.vaciar();
    return data as VentaRegistrada;
  }
}