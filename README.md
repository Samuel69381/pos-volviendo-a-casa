# POS Cafetería · Volviendo a Casa

Punto de venta para la cafetería del torneo: cuentas abiertas por equipo,
ventas de contado, registro de pagos (efectivo, Nequi, Bancolombia),
cuadre de inventario y cierre de caja.

## Stack
- Base de datos y autenticación: Supabase (PostgreSQL)
- Frontend: Angular (PWA)

## Ramas
- `develop`: desarrollo y pruebas -> Supabase dev
- `main`: producción del torneo -> Supabase prod
- A `main` solo se llega por Pull Request desde `develop`.

## Configuración local
1. Copia `.env.example` como `.env.development` y `.env.production`.
2. Llena las claves de cada proyecto de Supabase.
3. `npx supabase link --project-ref <ref de dev>`
4. `npx supabase db push`

## Estructura
- `docs/specs/`: especificaciones
- `supabase/migrations/`: cambios de la base de datos, en orden
- `frontend/`: aplicación Angular
