import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Auth } from '../../../core/auth/auth';
import { Carrito } from '../../../core/ventas/carrito';
import { Pago, Ventas, VentaRegistrada } from '../../../core/ventas/ventas';

type MetodoPago = 'efectivo' | 'transferencia' | 'mixto';
type CuentaTransferencia = 'nequi' | 'bancolombia';

@Component({
  selector: 'app-venta',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './venta.html',
  styleUrl: './venta.scss'
})
export class Venta {
  private readonly auth = inject(Auth);
  private readonly ventas = inject(Ventas);
  protected readonly carrito = inject(Carrito);

  // Datos del carrito real (los llena la pantalla Vender)
  readonly productos = this.carrito.items;
  readonly cantidadProductos = this.carrito.unidades;
  readonly total = this.carrito.total;

  readonly empleado = computed(() => this.auth.perfil()?.nombre_completo ?? '');
  // El mesero no cobra: solo carga pedidos a cuentas
  readonly puedeCobrar = computed(() => this.auth.perfil()?.rol !== 'mesero');

  cliente = signal('');
  observaciones = signal('');

  metodoPago = signal<MetodoPago>('efectivo');
  cuentaTransferencia = signal<CuentaTransferencia>('nequi');

  dineroRecibido = signal<number | null>(null);
  efectivoMixto = signal<number | null>(null);

  readonly cargando = signal(false);
  readonly errorServidor = signal<string | null>(null);
  readonly ventaRegistrada = signal<VentaRegistrada | null>(null);

  // Cambio en efectivo
  cambio = computed(() =>
    Math.max(0, (this.dineroRecibido() ?? 0) - this.total())
  );

  // Dinero faltante
  faltante = computed(() =>
    Math.max(0, this.total() - (this.dineroRecibido() ?? 0))
  );

  // Valor restante para transferencia mixta
  transferenciaMixta = computed(() =>
    Math.max(0, this.total() - (this.efectivoMixto() ?? 0))
  );

  // ¿El pago cubre exactamente el total?
  pagoCompleto = computed(() => {
    switch (this.metodoPago()) {
      case 'efectivo':
        return this.dineroRecibido() !== null && this.faltante() === 0;
      case 'transferencia':
        return true;
      case 'mixto': {
        const efectivo = this.efectivoMixto() ?? 0;
        return efectivo >= 0 && efectivo <= this.total();
      }
    }
  });

  puedeConfirmar = computed(() =>
    this.puedeCobrar() && !this.carrito.vacio() && this.pagoCompleto() && !this.cargando()
  );

  seleccionarMetodo(metodo: MetodoPago): void {
    this.metodoPago.set(metodo);
    this.errorServidor.set(null);
  }

  seleccionarCuenta(cuenta: CuentaTransferencia): void {
    this.cuentaTransferencia.set(cuenta);
  }

  async confirmarVenta(): Promise<void> {
    if (!this.puedeConfirmar()) return;

    this.cargando.set(true);
    this.errorServidor.set(null);
    try {
      const venta = await this.ventas.registrarContado(
        this.armarPagos(),
        this.cliente(),
        this.observaciones()
      );
      this.ventaRegistrada.set(venta);
      this.limpiarFormulario();
    } catch (e) {
      this.errorServidor.set(e instanceof Error ? e.message : 'Ocurrió un error inesperado');
    } finally {
      this.cargando.set(false);
    }
  }

  formatoPrecio(valor: number): string {
    return new Intl.NumberFormat('es-CO', {
      style: 'currency',
      currency: 'COP',
      maximumFractionDigits: 0
    }).format(valor);
  }

  // En efectivo se registra el TOTAL: el resto del billete se devuelve como cambio
  private armarPagos(): Pago[] {
    const total = this.total();
    const cuenta = this.cuentaTransferencia();
    switch (this.metodoPago()) {
      case 'efectivo':
        return [{ medio: 'efectivo', monto: total }];
      case 'transferencia':
        return [{ medio: cuenta, monto: total }];
      case 'mixto': {
        const efectivo = this.efectivoMixto() ?? 0;
        return [
          { medio: 'efectivo', monto: efectivo },
          { medio: cuenta, monto: total - efectivo }
        ];
      }
    }
  }

  private limpiarFormulario(): void {
    this.cliente.set('');
    this.observaciones.set('');
    this.metodoPago.set('efectivo');
    this.dineroRecibido.set(null);
    this.efectivoMixto.set(null);
  }
}