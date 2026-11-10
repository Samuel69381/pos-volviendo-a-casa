// Edge Function: admin-empleados
// Permite al administrador crear empleados y restablecer contraseñas.
// Corre en los servidores de Supabase, donde la clave secreta (service_role) está protegida.

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

// Permite que la app (otro dominio) llame a esta función desde el navegador
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Mismas reglas que la tabla perfiles
const DOMINIO = 'pos.local';
const RE_USUARIO = /^[a-z0-9._]{3,30}$/;
const RE_CEDULA = /^[0-9]{6,10}$/;
const RE_CELULAR = /^3[0-9]{9}$/;
const CLAVE_MINIMA = 8;

type Cuerpo = Record<string, unknown>;

function responder(status: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function texto(valor: unknown): string {
  return String(valor ?? '').trim();
}

Deno.serve(async (req: Request): Promise<Response> => {
  // El navegador pregunta primero si puede llamar (CORS)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return responder(405, { error: 'Método no permitido' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const claveAnon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const claveServicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1. ¿Quién llama? Usamos el token de su sesión
  const comoUsuario = createClient(url, claveAnon, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: sesion } = await comoUsuario.auth.getUser();
  if (!sesion.user) return responder(401, { error: 'Inicia sesión para continuar' });

  // 2. ¿Es administrador? Lo responde la función es_admin() de la base
  const { data: esAdmin, error: errorAdmin } = await comoUsuario.rpc('es_admin');
  if (errorAdmin || esAdmin !== true) {
    return responder(403, { error: 'Solo el administrador puede gestionar empleados' });
  }

  // 3. Cliente con permisos totales: solo existe aquí, nunca en la app
  const admin = createClient(url, claveServicio, { auth: { persistSession: false } });

  let cuerpo: Cuerpo;
  try {
    cuerpo = await req.json();
  } catch {
    return responder(400, { error: 'Datos inválidos' });
  }

  if (cuerpo.accion === 'crear') return await crearEmpleado(admin, sesion.user.id, cuerpo);
  if (cuerpo.accion === 'restablecer_clave') return await restablecerClave(admin, sesion.user.id, cuerpo);
  return responder(400, { error: 'Acción no válida. Usa "crear" o "restablecer_clave"' });
});

// Crea el usuario de acceso (Auth) y su perfil de empleado
async function crearEmpleado(admin: SupabaseClient, adminId: string, b: Cuerpo): Promise<Response> {
  const usuario = texto(b.usuario).toLowerCase();
  const nombre = texto(b.nombre_completo);
  const cedula = texto(b.cedula);
  const celular = texto(b.celular);
  const rol = texto(b.rol);
  const clave = String(b.clave_temporal ?? '');

  if (!RE_USUARIO.test(usuario)) {
    return responder(400, { error: 'Usuario inválido: solo minúsculas, números, punto o guion bajo (3 a 30 caracteres)' });
  }
  if (nombre.length < 5) return responder(400, { error: 'Escribe el nombre completo' });
  if (!RE_CEDULA.test(cedula)) return responder(400, { error: 'Cédula inválida: solo números, de 6 a 10 dígitos' });
  if (!RE_CELULAR.test(celular)) return responder(400, { error: 'Celular inválido: 10 dígitos que empiecen por 3' });
  if (rol !== 'admin' && rol !== 'cajero') return responder(400, { error: 'El rol debe ser admin o cajero' });
  if (clave.length < CLAVE_MINIMA) {
    return responder(400, { error: `La contraseña temporal debe tener al menos ${CLAVE_MINIMA} caracteres` });
  }

  // a) Usuario de acceso: usuario@pos.local + contraseña temporal
  const { data: creado, error: errorAuth } = await admin.auth.admin.createUser({
    email: `${usuario}@${DOMINIO}`,
    password: clave,
    email_confirm: true,
  });
  if (errorAuth || !creado.user) {
    const yaExiste = (errorAuth?.message ?? '').toLowerCase().includes('already');
    return responder(400, {
      error: yaExiste ? `El usuario ${usuario} ya existe` : `No se pudo crear el usuario: ${errorAuth?.message}`,
    });
  }

  // b) Perfil de empleado con el mismo id
  const { error: errorPerfil } = await admin.from('perfiles').insert({
    id: creado.user.id,
    usuario,
    nombre_completo: nombre,
    cedula,
    celular,
    rol,
    debe_cambiar_clave: true,
  });
  if (errorPerfil) {
    // Si el perfil falla (ej. cédula repetida), se borra el usuario para no dejarlo a medias
    await admin.auth.admin.deleteUser(creado.user.id);
    const duplicado = errorPerfil.code === '23505';
    return responder(400, {
      error: duplicado ? 'Ya existe un empleado con ese usuario o esa cédula' : `Datos inválidos: ${errorPerfil.message}`,
    });
  }

  await admin.from('auditoria').insert({
    usuario_id: adminId,
    accion: 'crear_empleado',
    tabla: 'perfiles',
    registro_id: creado.user.id,
    detalles: { usuario, rol },
  });

  return responder(200, { id: creado.user.id, usuario, rol, debe_cambiar_clave: true });
}

// Asigna una contraseña temporal nueva a un empleado que olvidó la suya
async function restablecerClave(admin: SupabaseClient, adminId: string, b: Cuerpo): Promise<Response> {
  const usuario = texto(b.usuario).toLowerCase();
  const clave = String(b.clave_temporal ?? '');
  if (clave.length < CLAVE_MINIMA) {
    return responder(400, { error: `La contraseña temporal debe tener al menos ${CLAVE_MINIMA} caracteres` });
  }

  const { data: perfil } = await admin.from('perfiles').select('id').eq('usuario', usuario).maybeSingle();
  if (!perfil) return responder(404, { error: `No existe el empleado ${usuario}` });

  const { error: errorAuth } = await admin.auth.admin.updateUserById(perfil.id, { password: clave });
  if (errorAuth) return responder(400, { error: `No se pudo cambiar la contraseña: ${errorAuth.message}` });

  await admin.from('perfiles').update({ debe_cambiar_clave: true }).eq('id', perfil.id);
  await admin.from('auditoria').insert({
    usuario_id: adminId,
    accion: 'restablecer_clave',
    tabla: 'perfiles',
    registro_id: perfil.id,
    detalles: { usuario },
  });

  return responder(200, { usuario, debe_cambiar_clave: true });
}