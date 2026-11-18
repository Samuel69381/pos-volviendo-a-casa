import { computed, Injectable, signal } from '@angular/core';
import { Producto } from '../catalogo/catalogo';

export interface ItemCarrito {
  producto: Producto;
  cantidad: number;
}

// Lo que el cliente va pidiendo. Vive en memoria hasta cobrar o cargar a cuenta.
@Injectable({ providedIn: 'root' })
export class Carrito {
  private readonly _items = signal<ItemCarrito[]>([]);

  readonly items = this._items.asReadonly();
  readonly vacio = computed(() => this._items().length === 0);

  /** Unidades en total (ej. 2 Águila + 1 Agua = 3) */
  readonly unidades = computed(() =>
    this._items().reduce((suma, item) => suma + item.cantidad, 0)
  );

  /** Valor a pagar */
  readonly total = computed(() =>
    this._items().reduce((suma, item) => suma + item.producto.precio_cop * item.cantidad, 0)
  );

  /** Suma 1 unidad. Si ya está en el carrito, aumenta la cantidad. */
  agregar(producto: Producto): void {
    const actual = this.cantidadDe(producto.id);
    this.cambiarCantidad(producto, actual + 1);
  }

  /** Resta 1 unidad. Si llega a 0, lo quita del carrito. */
  restar(producto: Producto): void {
    this.cambiarCantidad(producto, this.cantidadDe(producto.id) - 1);
  }

  /** Pone una cantidad exacta, sin pasar del stock disponible. */
  cambiarCantidad(producto: Producto, cantidad: number): void {
    const maximo = producto.controla_stock ? producto.stock : Infinity;
    const nueva = Math.min(Math.max(cantidad, 0), maximo);

    this._items.update(items => {
      const sinEste = items.filter(item => item.producto.id !== producto.id);
      if (nueva === 0) return sinEste;
      const existe = items.some(item => item.producto.id === producto.id);
      return existe
        ? items.map(item => item.producto.id === producto.id ? { ...item, cantidad: nueva } : item)
        : [...items, { producto, cantidad: nueva }];
    });
  }

  quitar(producto: Producto): void {
    this.cambiarCantidad(producto, 0);
  }

  vaciar(): void {
    this._items.set([]);
  }

  cantidadDe(productoId: string): number {
    return this._items().find(item => item.producto.id === productoId)?.cantidad ?? 0;
  }

  /** El formato que espera la función registrar_venta de la base de datos */
  paraRegistrar(): { producto_id: string; cantidad: number }[] {
    return this._items().map(item => ({ producto_id: item.producto.id, cantidad: item.cantidad }));
  }
}