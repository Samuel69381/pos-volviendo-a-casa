import { inject, Injectable } from '@angular/core';
import { Supabase } from '../supabase';
import { Carrito } from './carrito';
import { MedioPago } from './ventas';

// Lo que devuelve buscar_cuentas (una fila por cuenta abierta)
export interface CuentaAbierta {
  cuenta_id: string;
  numero_cuenta: number;
  nombre_cuenta: string;
  encargado_nombre: string;
  encargado_celular: string;
  productos: number;
  total_cop: number;
  pagado_cop: number;
  saldo_cop: number;
  abierta_en: string;
}

export interface PedidoACuenta {
  venta_id: string;
  numero_venta: number;
  total_cop: number;
  saldo_cuenta_cop: number;
}

// Un producto consumido en una cuenta (ya sumado entre pedidos)
export interface Consumo {
  nombre: string;
  cantidad: number;
  precio: number;
}

export interface PagoCuenta {
  pago_id: string;
  saldo_cop: number;
  cuenta_cerrada: boolean;
}

@Injectable({ providedIn: 'root' })
export class Cuentas {
  private readonly supabase = inject(Supabase).client;
  private readonly carrito = inject(Carrito);

  /** Cuentas abiertas. Con texto filtra por equipo, encargado o celular. */
  async buscar(texto = ''): Promise<CuentaAbierta[]> {
    const { data, error } = await this.supabase.rpc('buscar_cuentas', { p_texto: texto });
    if (error) throw new Error(error.message);
    return (data ?? []) as CuentaAbierta[];
  }

  /** Abre una cuenta. Con equipo se autollena el encargado habitual. */
  async abrir(datos: {
    encargadoNombre?: string;
    encargadoCelular?: string;
    equipoId?: string | null;
    notas?: string;
  }): Promise<{ cuenta_id: string; numero_cuenta: number; nombre_cuenta: string }> {
    const { data, error } = await this.supabase.rpc('abrir_cuenta', {
      p_encargado_nombre: datos.encargadoNombre ?? null,
      p_encargado_celular: datos.encargadoCelular ?? null,
      p_equipo_id: datos.equipoId ?? null,
      p_notas: datos.notas ?? null
    });
    if (error) throw new Error(error.message);
    return data;
  }

  /** Carga el carrito a una cuenta (no se cobra ahora). Si sale bien, vacía el carrito. */
  async cargarCarrito(cuentaId: string, notas = ''): Promise<PedidoACuenta> {
    if (this.carrito.vacio()) throw new Error('El carrito está vacío');
    const { data, error } = await this.supabase.rpc('registrar_venta', {
      p_items: this.carrito.paraRegistrar(),
      p_cuenta_id: cuentaId,
      p_notas: notas.trim() || null
    });
    if (error) throw new Error(error.message);
    this.carrito.vaciar();
    return data as PedidoACuenta;
  }

  /** Abono o pago final de una cuenta. */
  async pagar(cuentaId: string, monto: number, medio: MedioPago, nota = ''): Promise<PagoCuenta> {
    const { data, error } = await this.supabase.rpc('pagar_cuenta', {
      p_cuenta_id: cuentaId,
      p_monto: monto,
      p_medio: medio,
      p_nota: nota.trim() || null
    });
    if (error) throw new Error(error.message);
    return data as PagoCuenta;
  }

  /** Productos consumidos en la cuenta, sumando los pedidos no anulados. */
  async consumos(cuentaId: string): Promise<Consumo[]> {
    const { data, error } = await this.supabase
      .from('ventas')
      .select('detalle_venta(nombre_producto, precio_unitario_cop, cantidad)')
      .eq('cuenta_id', cuentaId)
      .eq('estado', 'registrada');
    if (error) throw new Error(error.message);

    const mapa = new Map<string, Consumo>();
    for (const venta of (data ?? []) as any[]) {
      for (const d of venta.detalle_venta ?? []) {
        const clave = `${d.nombre_producto}|${d.precio_unitario_cop}`;
        const previo = mapa.get(clave);
        if (previo) previo.cantidad += d.cantidad;
        else mapa.set(clave, { nombre: d.nombre_producto, cantidad: d.cantidad, precio: d.precio_unitario_cop });
      }
    }
    return [...mapa.values()];
  }
}
