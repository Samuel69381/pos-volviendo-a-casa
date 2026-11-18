import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CuentasAbiertas } from './cuentas-abiertas';

describe('CuentasAbiertas', () => {
  let component: CuentasAbiertas;
  let fixture: ComponentFixture<CuentasAbiertas>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CuentasAbiertas],
    }).compileComponents();

    fixture = TestBed.createComponent(CuentasAbiertas);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
