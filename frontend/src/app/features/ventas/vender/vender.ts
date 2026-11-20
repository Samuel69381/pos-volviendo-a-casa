import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Auth } from '../../../core/auth/auth';
import { Catalogo, Producto } from '../../../core/catalogo/catalogo';
import { Carrito } from '../../../core/ventas/carrito';

@Component({
  selector: 'app-vender',
  standalone: true,
  imports: [RouterLink, FormsModule],
  templateUrl: './vender.html',
  styleUrl: './vender.scss'
})
export class Vender implements OnInit {
  private readonly auth = inject(Auth);
  protected readonly catalogo = inject(Catalogo);
  protected readonly carrito = inject(Carrito);

  readonly empleado = computed(() => this.auth.perfil()?.nombre_completo ?? '');

  // null = "Todas"
  readonly categoriaActiva = signal<string | null>(null);
  readonly busqueda = signal('');

  readonly cargando = signal(true);
  readonly error = signal<string | null>(null);

  // Productos que se ven según la categoría y lo que se escribió en el buscador
  readonly productosVisibles = computed(() => {
    const categoria = this.categoriaActiva();
    const texto = this.normalizar(this.busqueda());
    return this.catalogo.productos().filter(producto =>
      (categoria === null || producto.categoria_id === categoria) &&
      (texto === '' || this.normalizar(producto.nombre).includes(texto))
    );
  });

  async ngOnInit(): Promise<void> {
    await this.cargarCatalogo();
  }

  async cargarCatalogo(): Promise<void> {
    this.cargando.set(true);
    this.error.set(null);
    try {
      await this.catalogo.cargar();
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'No se pudo cargar el menú');
    } finally {
      this.cargando.set(false);
    }
  }

  seleccionarCategoria(id: string | null): void {
    this.categoriaActiva.set(id);
  }

  agregar(producto: Producto): void {
    if (this.catalogo.disponible(producto)) this.carrito.agregar(producto);
  }

  /** ¿Ya no se puede sumar más de este producto? (llegó al stock) */
  enElLimite(producto: Producto): boolean {
    return producto.controla_stock && this.carrito.cantidadDe(producto.id) >= producto.stock;
  }

  stockBajo(producto: Producto): boolean {
    return producto.controla_stock && producto.stock > 0 && producto.stock <= producto.stock_minimo;
  }

  formatoPrecio(valor: number): string {
    return new Intl.NumberFormat('es-CO', {
      style: 'currency',
      currency: 'COP',
      maximumFractionDigits: 0
    }).format(valor);
  }

  // "Águila" y "aguila" cuentan igual al buscar
  private normalizar(texto: string): string {
    return texto.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
  }
}