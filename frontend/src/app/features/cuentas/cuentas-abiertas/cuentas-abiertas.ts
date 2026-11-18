import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { Consumo, CuentaAbierta, Cuentas } from '../../../core/ventas/cuentas';
import { MedioPago } from '../../../core/ventas/ventas';

@Component({
  selector: 'app-cuentas-abiertas',
  standalone: true,
  imports: [],
  templateUrl: './cuentas-abiertas.html',
  styleUrl: './cuentas-abiertas.scss'
})
export class CuentasAbiertas implements OnInit {
  private readonly servicio = inject(Cuentas);

  busqueda = signal('');
  cuentas = signal<CuentaAbierta[]>([]);
  cuentaSeleccionada = signal<CuentaAbierta | null>(null);
  consumos = signal<Consumo[]>([]);

  cargando = signal(true);
  error = signal<string | null>(null);
  mensaje = signal<string | null>(null);

  // Formulario de pago
  monto = signal<number | null>(null);
  medio = signal<MedioPago>('efectivo');
  procesando = signal(false);

  // Formulario de nueva cuenta
  abriendo = signal(false);
  nuevoNombre = signal('');
  nuevoCelular = signal('');

  cuentasFiltradas = computed(() => {
    const quitarTildes = (t: string) =>
      t.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    const texto = quitarTildes(this.busqueda().trim());
    return this.cuentas().filter(c =>
      quitarTildes(`${c.nombre_cuenta} ${c.encargado_nombre} ${c.encargado_celular}`).includes(texto)
    );
  });

  // Lo que falta por cobrar = suma de saldos
  totalPendiente = computed(() =>
    this.cuentas().reduce((suma, c) => suma + c.saldo_cop, 0)
  );

  ngOnInit(): void {
    this.recargar();
  }

  async recargar(): Promise<void> {
    this.cargando.set(true);
    this.error.set(null);
    try {
      const lista = await this.servicio.buscar('');
      this.cuentas.set(lista);
      // Mantiene abierta la cuenta seleccionada con datos frescos
      const actual = this.cuentaSeleccionada();
      if (actual) {
        this.cuentaSeleccionada.set(lista.find(c => c.cuenta_id === actual.cuenta_id) ?? null);
      }
    } catch (e) {
      this.error.set(this.textoError(e));
    } finally {
      this.cargando.set(false);
    }
  }

  async seleccionarCuenta(cuenta: CuentaAbierta): Promise<void> {
    this.cuentaSeleccionada.set(cuenta);
    this.monto.set(null);
    this.mensaje.set(null);
    this.consumos.set([]);
    try {
      this.consumos.set(await this.servicio.consumos(cuenta.cuenta_id));
    } catch (e) {
      this.error.set(this.textoError(e));
    }
  }

  cerrarDetalle(): void {
    this.cuentaSeleccionada.set(null);
  }

  pagarSaldoCompleto(): void {
    this.monto.set(this.cuentaSeleccionada()?.saldo_cop ?? null);
  }

  async registrarPago(): Promise<void> {
    const cuenta = this.cuentaSeleccionada();
    const monto = this.monto();
    if (!cuenta || !monto || monto <= 0 || this.procesando()) return;

    this.procesando.set(true);
    this.error.set(null);
    this.mensaje.set(null);
    try {
      const r = await this.servicio.pagar(cuenta.cuenta_id, monto, this.medio());
      this.monto.set(null);
      if (r.cuenta_cerrada) {
        this.cuentaSeleccionada.set(null);
        this.mensaje.set(`Cuenta de ${cuenta.nombre_cuenta} pagada y cerrada ✓`);
      } else {
        this.mensaje.set(`Pago registrado. Saldo: ${this.formatoPrecio(r.saldo_cop)}`);
      }
      await this.recargar();
    } catch (e) {
      this.error.set(this.textoError(e));
    } finally {
      this.procesando.set(false);
    }
  }

  async abrirCuenta(): Promise<void> {
    if (this.procesando()) return;
    this.procesando.set(true);
    this.error.set(null);
    try {
      const nueva = await this.servicio.abrir({
        encargadoNombre: this.nuevoNombre(),
        encargadoCelular: this.nuevoCelular()
      });
      this.mensaje.set(`Cuenta #${nueva.numero_cuenta} abierta: ${nueva.nombre_cuenta}`);
      this.nuevoNombre.set('');
      this.nuevoCelular.set('');
      this.abriendo.set(false);
      await this.recargar();
    } catch (e) {
      this.error.set(this.textoError(e));
    } finally {
      this.procesando.set(false);
    }
  }

  totalConsumos(): number {
    return this.consumos().reduce((s, i) => s + i.precio * i.cantidad, 0);
  }

  formatoPrecio(valor: number): string {
    return new Intl.NumberFormat('es-CO', {
      style: 'currency',
      currency: 'COP',
      maximumFractionDigits: 0
    }).format(valor);
  }

  formatoHora(iso: string): string {
    return new Date(iso).toLocaleString('es-CO', {
      day: '2-digit', month: 'short', hour: 'numeric', minute: '2-digit'
    });
  }

  private textoError(e: unknown): string {
    return e instanceof Error ? e.message : 'Ocurrió un error inesperado';
  }
}