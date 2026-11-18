import { computed, inject, Injectable, signal } from '@angular/core';
import { Supabase } from '../supabase';

export interface Categoria {
  id: string;
  nombre: string;
}

export interface Producto {
  id: string;
  nombre: string;
  categoria_id: string | null;
  precio_cop: number;
  controla_stock: boolean;
  stock: number;
  stock_minimo: number;
}

// El menú de la cafetería: categorías y productos activos
@Injectable({ providedIn: 'root' })
export class Catalogo {
  private readonly supabase = inject(Supabase).client;

  private readonly _categorias = signal<Categoria[]>([]);
  private readonly _productos = signal<Producto[]>([]);

  readonly categorias = this._categorias.asReadonly();
  readonly productos = this._productos.asReadonly();

  /** Productos con stock bajo (para avisar "Quedan 3") */
  readonly stockBajo = computed(() =>
    this._productos().filter(p => p.controla_stock && p.stock > 0 && p.stock <= p.stock_minimo)
  );

  /** Trae categorías y productos desde Supabase. */
  async cargar(): Promise<void> {
    const [categorias, productos] = await Promise.all([
      this.supabase
        .from('categorias')
        .select('id, nombre')
        .order('orden'),
      this.supabase
        .from('productos')
        .select('id, nombre, categoria_id, precio_cop, controla_stock, stock, stock_minimo')
        .eq('activo', true)
        .order('orden')
    ]);

    if (categorias.error || productos.error) {
      throw new Error('No se pudo cargar el menú. Revisa tu conexión');
    }

    this._categorias.set(categorias.data);
    this._productos.set(productos.data);
  }

  /** ¿Se puede vender? Los que no controlan stock (ej. alquiler) siempre sí. */
  disponible(producto: Producto): boolean {
    return !producto.controla_stock || producto.stock > 0;
  }
}