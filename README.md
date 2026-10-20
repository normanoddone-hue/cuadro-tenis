# Cuadro de Tenis · versión instalable (PWA)

App web del club para torneos de tenis: cuadros, partidos, ranking, estadísticas de jugadores, noticias, galería y reportes en PDF. Se instala en el celular como una app y el público la abre sin cuenta.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La app completa |
| `config.js` | Dirección y clave pública de tu proyecto de Supabase (**tenés que completarlo**) |
| `manifest.webmanifest` | Nombre, colores e íconos para instalarla |
| `sw.js` | Service worker: abre rápido y muestra la última copia sin conexión |
| `icons/` | Íconos de la app (generados con el logo) |
| `supabase.sql` | Tablas, reglas de seguridad y almacenamiento de fotos |

## 1. Supabase (10 minutos)

1. Creá un proyecto nuevo en <https://supabase.com> (región São Paulo, la más cercana a Paraguay).
2. **SQL Editor → New query**: pegá todo `supabase.sql` y tocá **Run**.
3. **Authentication → Sign In / Providers → Email**: dejá Email activado y **desactivá "Allow new users to sign up"**. Así nadie puede crearse una cuenta: solo existen los administradores que vos agregues.
4. **Authentication → Users → Add user → Create new user**: cargá tu correo y una contraseña (marcá *Auto Confirm User*). Repetí para cada administrador.
5. **Project Settings → API**: copiá *Project URL* y la clave *anon public* y pegalas en `config.js`:

```js
window.CFG = {
  url: 'https://abcdxyz.supabase.co',
  key: 'eyJhbGciOi...'
};
```

## 2. Publicar en Vercel

1. Subí esta carpeta a un repositorio de GitHub (por ejemplo `cuadro-tenis`).
2. En Vercel: **Add New → Project → Import** ese repositorio. Framework: **Other**. Sin comando de build. **Deploy**.
3. Cada `git push` vuelve a publicar solo.
4. Opcional: en Vercel → Settings → Domains agregá un dominio propio (por ejemplo `tenis.tuclub.com.py`).

> Después de cada cambio en `index.html`, subí también el número de `VERSION` en `sw.js` (`cdt-v2`, `cdt-v3`…) para que los celulares tomen la versión nueva.

## 3. Pasar los datos que ya cargaste

1. En la versión de claude.ai: ingresá como administrador → **Club y cuenta → Exportar datos (JSON)**.
2. En la versión nueva: ingresá con tu correo → **Club y cuenta → Importar datos (JSON)** → elegí el archivo → **Confirmar importación**.

Se pasan jugadores, torneos, cuadros, resultados, noticias, nombre y logo del club. Las fotos subidas en claude.ai no se pueden transferir: volvé a subirlas desde la galería y los perfiles.

## 4. Instalar en el celular

- **Android (Chrome):** abrí el sitio → aparece **"Instalar app"** abajo en el menú (o ⋮ → *Instalar aplicación*).
- **iPhone (Safari):** botón Compartir → **Agregar a inicio**.
- **Computadora (Chrome/Edge):** ícono de instalar en la barra de direcciones.

## Seguridad

- El público solo puede **leer** la fila `principal` (torneos, resultados, ranking). Cédulas, teléfonos y fechas de nacimiento se guardan aparte, en la fila `privado`, que solo leen los administradores con sesión iniciada. Al público solo le llega la edad.
- Solo los usuarios que creás en Supabase pueden guardar cambios y subir fotos. Con el registro desactivado nadie más puede crearse una cuenta.
- La clave *anon* de `config.js` es pública por diseño. Nunca pongas ahí la *service_role key*.

## Para publicarla en Google Play (opcional)

Se puede empaquetar con Capacitor (`npx cap init`, `npx cap add android`, copiar esta carpeta como `www`) o con Bubblewrap (TWA) apuntando al dominio de Vercel.
