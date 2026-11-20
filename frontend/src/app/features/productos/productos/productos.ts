import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Auth } from '../../../core/auth/auth';
import { Catalogo } from '../../../core/catalogo/catalogo';
import { ProductoAdmin, Productos as ProductosService } from '../../../core/catalogo/productos';

// La forma que ya usa tu HTML (ahora con los datos reales de Supabase)
interface Producto {
  id: string;
  nombre: string;
  categoria: string;
  precio: number;
  stock: number;
  stockMinimo: number;
  activo: boolean;
  controlaStock: boolean;
}

@Component({
  selector: 'app-productos',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './productos.html',
  styleUrl: './productos.scss'
})
export class Productos implements OnInit {
  private readonly auth = inject(Auth);
  private readonly productosService = inject(ProductosService);
  private readonly catalogo = inject(Catalogo);

  busqueda = signal('');
  categoriaFiltro = signal('Todas');
  mostrarFormulario = signal(false);
  editandoId = signal<string | null>(null);

  // Estado de la conexión con Supabase
  readonly cargando = signal(true);
  readonly guardando = signal(false);
  readonly error = signal<string | null>(null);
  readonly mensaje = signal<string | null>(null);

  // Crear: cajero y admin. Editar y activar/desactivar: solo admin
  readonly esAdmin = computed(() => this.auth.perfil()?.rol === 'admin');

  /** Nombres de las categorías reales, con "Todas" al inicio */
  get categorias(): string[] {
    return ['Todas', ...this.catalogo.categorias().map(c => c.nombre)];
  }

  // Los productos de Supabase convertidos a la forma de tu pantalla
  productos = computed<Producto[]>(() =>
    this.productosService.lista().map(p => this.aPantalla(p))
  );

  formulario: Omit<Producto, 'id'> = this.formularioVacio();

  productosFiltrados = computed(() => {
    const texto = this.busqueda().trim().toLowerCase();
    const categoria = this.categoriaFiltro();

    return this.productos().filter(p => {
      const coincideTexto =
        p.nombre.toLowerCase().includes(texto) ||
        p.categoria.toLowerCase().includes(texto);

      const coincideCategoria =
        categoria === 'Todas' || p.categoria === categoria;

      return coincideTexto && coincideCategoria;
    });
  });

  totalProductos = computed(() => this.productos().length);

  productosDisponibles = computed(() =>
    this.productos().filter(p => p.activo && (!p.controlaStock || p.stock > 0)).length
  );

  productosStockBajo = computed(() =>
    this.productos().filter(
      p => p.activo && p.controlaStock && p.stock <= p.stockMinimo
    ).length
  );

  async ngOnInit(): Promise<void> {
    await this.ejecutar(async () => {
      await Promise.all([this.productosService.cargar(), this.catalogo.cargar()]);
    });
    this.cargando.set(false);
  }

  formularioVacio(): Omit<Producto, 'id'> {
    return {
      nombre: '',
      categoria: this.categorias[1] ?? '',
      precio: 0,
      stock: 0,
      stockMinimo: 5,
      activo: true,
      controlaStock: true
    };
  }

  nuevoProducto(): void {
    this.editandoId.set(null);
    this.formulario = this.formularioVacio();
    this.limpiarMensajes();
    this.mostrarFormulario.set(true);
  }

  editarProducto(producto: Producto): void {
    if (!this.esAdmin()) return;
    this.editandoId.set(producto.id);
    this.formulario = {
      nombre: producto.nombre,
      categoria: producto.categoria,
      precio: producto.precio,
      stock: producto.stock,
      stockMinimo: producto.stockMinimo,
      activo: producto.activo,
      controlaStock: producto.controlaStock
    };
    this.limpiarMensajes();
    this.mostrarFormulario.set(true);
  }

  cerrarFormulario(): void {
    this.mostrarFormulario.set(false);
    this.editandoId.set(null);
  }

  async guardarProducto(): Promise<void> {
    const nombre = this.formulario.nombre.trim();
    const precio = Number(this.formulario.precio);
    const stockMinimo = Number(this.formulario.stockMinimo);

    if (!nombre) return this.error.set('Escribe el nombre del producto');
    if (!Number.isInteger(precio) || precio <= 0) return this.error.set('El precio debe ser mayor a cero');
    if (!Number.isInteger(stockMinimo) || stockMinimo < 0) return this.error.set('El stock mínimo no puede ser negativo');

    // El stock NO se envía: entra por Compras y se corrige en el cierre
    const datos = {
      nombre,
      precio_cop: precio,
      categoria_id: this.idCategoria(this.formulario.categoria),
      controla_stock: this.formulario.controlaStock,
      stock_minimo: stockMinimo
    };

    const id = this.editandoId();
    this.guardando.set(true);
    const ok = await this.ejecutar(async () => {
      if (id !== null) {
        await this.productosService.actualizar(id, { ...datos, activo: this.formulario.activo });
      } else {
        await this.productosService.crear(datos);
      }
    });
    this.guardando.set(false);

    if (ok) {
      this.mensaje.set(id !== null ? `"${nombre}" actualizado` : `"${nombre}" creado`);
      this.cerrarFormulario();
    }
  }

  async cambiarEstado(producto: Producto): Promise<void> {
    if (!this.esAdmin()) return;
    this.limpiarMensajes();
    await this.ejecutar(() => this.productosService.cambiarActivo(producto.id, !producto.activo));
  }

  estadoStock(producto: Producto): string {
    if (!producto.controlaStock) return 'Sin control';
    if (producto.stock === 0) return 'Agotado';
    if (producto.stock <= producto.stockMinimo) return 'Stock bajo';
    return 'Disponible';
  }

  formatoPrecio(valor: number): string {
    return new Intl.NumberFormat('es-CO', {
      style: 'currency',
      currency: 'COP',
      maximumFractionDigits: 0
    }).format(valor);
  }

  // ---------- Conversión entre Supabase y tu pantalla ----------

  private aPantalla(p: ProductoAdmin): Producto {
    return {
      id: p.id,
      nombre: p.nombre,
      categoria: this.catalogo.categorias().find(c => c.id === p.categoria_id)?.nombre ?? 'Sin categoría',
      precio: p.precio_cop,
      stock: p.stock,
      stockMinimo: p.stock_minimo,
      activo: p.activo,
      controlaStock: p.controla_stock
    };
  }

  private idCategoria(nombre: string): string | null {
    return this.catalogo.categorias().find(c => c.nombre === nombre)?.id ?? null;
  }

  private limpiarMensajes(): void {
    this.error.set(null);
    this.mensaje.set(null);
  }

  // Intenta la acción y muestra el error si falla. Devuelve si salió bien.
  private async ejecutar(accion: () => Promise<void>): Promise<boolean> {
    this.error.set(null);
    try {
      await accion();
      return true;
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Ocurrió un error inesperado');
      return false;
    }
  }
}