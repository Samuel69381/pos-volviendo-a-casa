import { inject, Injectable, signal } from '@angular/core';
import { Supabase } from '../supabase';

export interface ProductoAdmin {
  id: string;
  nombre: string;
  categoria_id: string | null;
  precio_cop: number;
  controla_stock: boolean;
  stock: number;
  stock_minimo: number;
  orden: number;
  activo: boolean;
}

export interface NuevoProducto {
  nombre: string;
  precio_cop: number;
  categoria_id: string | null;
  controla_stock: boolean;
  stock_minimo: number;
}

// Lo que el admin puede cambiar (el stock NO: entra por compras y el cierre)
export type CambiosProducto = Partial<
  Pick<ProductoAdmin, 'nombre' | 'categoria_id' | 'precio_cop' | 'controla_stock' | 'stock_minimo' | 'orden' | 'activo'>
>;

const COLUMNAS = 'id, nombre, categoria_id, precio_cop, controla_stock, stock, stock_minimo, orden, activo';

// Gestión del catálogo: ver todos, crear (cajero y admin) y editar (solo admin)
@Injectable({ providedIn: 'root' })
export class Productos {
  private readonly supabase = inject(Supabase).client;

  private readonly _lista = signal<ProductoAdmin[]>([]);
  readonly lista = this._lista.asReadonly();

  /** Todos los productos, también los desactivados. */
  async cargar(): Promise<void> {
    const { data, error } = await this.supabase
      .from('productos')
      .select(COLUMNAS)
      .order('orden');
    if (error) throw new Error('No se pudieron cargar los productos');
    this._lista.set(data);
  }

  /** Crea un producto. Lo pueden hacer el cajero y el admin. */
  async crear(nuevo: NuevoProducto): Promise<void> {
    const { error } = await this.supabase.rpc('crear_producto', {
      p_nombre: nuevo.nombre,
      p_precio_cop: nuevo.precio_cop,
      p_categoria_id: nuevo.categoria_id,
      p_controla_stock: nuevo.controla_stock,
      p_stock_minimo: nuevo.stock_minimo
    });
    if (error) throw new Error(error.message);
    await this.cargar();
  }

  /** Edita un producto. Solo el admin (lo exige la seguridad RLS de la base). */
  async actualizar(id: string, cambios: CambiosProducto): Promise<void> {
    const { data, error } = await this.supabase
      .from('productos')
      .update(cambios)
      .eq('id', id)
      .select('id');
    if (error) throw new Error(this.traducirError(error.code, error.message));
    // RLS no lanza error: si no eres admin, simplemente no cambia ninguna fila
    if (!data || data.length === 0) throw new Error('Solo el administrador puede editar productos');
    await this.cargar();
  }

  /** Activa o desactiva (un producto desactivado no aparece en Vender). */
  async cambiarActivo(id: string, activo: boolean): Promise<void> {
    await this.actualizar(id, { activo });
  }

  private traducirError(codigo: string, mensaje: string): string {
    if (codigo === '23505') return 'Ya existe un producto con ese nombre';
    if (codigo === '23514') return 'Revisa los valores: el precio debe ser mayor a cero';
    return mensaje;
  }
}