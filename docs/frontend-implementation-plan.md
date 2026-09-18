# Client Project Portal: plan de frontend (etapa 2)

## Objetivo y alcance

Construir una SPA privada para clientes y administrador con React, Vite, CSS y Supabase JS. La primera pantalla utilizable sera el login; despues cada usuario entra directamente a su area de trabajo. Esta etapa implementa lectura y administracion de los datos que ya permite el backend. No crea registro publico, cobros online, una API propia ni un sistema de mensajeria en tiempo real.

Este documento adapta `implementation_plan_front.md` al esquema y las policies existentes en `supabase/migrations/20260918000100_client_project_portal.sql`. Antes de comenzar la UI, la migracion, el seed y las pruebas de `docs/rls-test-queries.sql` deben haber pasado en un proyecto Supabase de prueba. La seguridad real depende de RLS; los guardas de ruta solo mejoran la experiencia.

## Decisiones cerradas para el MVP

| Tema | Decision | Motivo |
| --- | --- | --- |
| Ubicacion | `frontend/` dentro de este repositorio | Aisla el proyecto Vite de `supabase/` y evita sobrescribir el README o los SQL existentes. |
| Stack | React + Vite, `@supabase/supabase-js`, `react-router` en modo declarativo, `lucide-react`, CSS plano | Dependencias pequenas y rutas suficientes para una SPA. |
| Estado | Context solo para autenticacion y perfil; datos de cada pantalla en hooks/servicios locales | Evita un store global para nueve tablas en un MVP. |
| Datos abiertos | Cargar al entrar, recargar al volver a la pestana y ofrecer boton de actualizar; refetch tras cada mutacion | El cliente ve los cambios al refrescar sin configurar Realtime. |
| Interfaz | UI en espanol, clara por defecto con modo oscuro opcional | El portal es una herramienta de consulta y trabajo repetido. |
| Estructura visual | Superficies neutras, alto contraste, acentos verde petroleo y coral/ambar para estados; bordes discretos | Una identidad sobria y reconocible para cliente y admin. Sin glassmorphism ni decoracion que compita con los datos. |
| Tipografia | Fuente sans-serif del sistema al inicio | Buen rendimiento y sin dependencia de Google Fonts. |
| Divisa | Mostrar los importes demo como COP con `Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP' })` | `payments` no tiene columna `currency`; no inferir divisa por navegador. |
| Orden de fases | Crear al final con `position = max + 1`; no arrastrar para reordenar en el MVP | El indice unico de `(project_id, position)` requiere una operacion atomica para intercambiar posiciones. |
| Alta de usuarios | Admin crea cuentas en Supabase Dashboard y asigna `client_users` alli | El navegador no puede crear usuarios Auth con privilegios de administrador. |

No fijar versiones exactas en este documento. Al implementar, instalar versiones estables compatibles, guardar `package-lock.json` y comprobar los comandos contra la documentacion vigente.

## Contrato real del backend

| Recurso | Cliente | Admin | Regla que afecta al frontend |
| --- | --- | --- | --- |
| `profiles` | Lee el propio; cambia solo `full_name` | Lee perfiles y cambia nombres | `role` se lee para navegacion, pero no se actualiza desde la SPA. |
| `clients`, `client_users` | Lee organizaciones y vinculos propios | CRUD permitido por RLS | La cuenta cliente puede pertenecer a mas de un cliente en el futuro. |
| `projects` | Lee solo los proyectos de sus clientes | CRUD | `progress_percentage` esta entre 0 y 100; `completed_at` y progreso 100 se fijan al completar. |
| `project_phases` | Lee fases del proyecto accesible | CRUD | Maximo una activa por proyecto; el trigger sincroniza `projects.current_phase_id`. |
| `project_updates` | Lee timeline | Crea, edita `title`/`message` y elimina | En cada alta, `created_by` debe ser el ID del admin autenticado. |
| `payments` | Solo lectura | CRUD | Son estados informativos. `paid_at` lo gestiona el trigger; `overdue` no se calcula automaticamente. |
| `comments` | Lee comentarios visibles; crea y edita/soft-delete los propios durante 15 minutos | Lee, responde y modera | `user_id` debe ser el usuario actual; sin borrado fisico. Cliente no ve filas con `deleted_at`. |
| `audit_logs` | Sin acceso | Solo lectura | Actividad administrativa por proyecto, con cambios y borrados. |

Los campos `id`, `created_at`, `updated_at`, `started_at`, `completed_at`, `paid_at` y `deleted_at` se muestran segun corresponda, pero no se envian como valores arbitrarios desde los formularios. En particular, la UI no escribe `current_phase_id`: se cambia el estado de la fase y el trigger lo sincroniza. Una fase tampoco se traslada a otro proyecto.

El perfil de otro usuario no es visible para un cliente. En comentarios del MVP se mostrara `Cliente` para el `user_id` compartido y `Equipo` para el otro autor, porque hoy solo existen una cuenta cliente y una admin. Esto no atribuye un mensaje a una persona especifica que comparta las credenciales. Antes de admitir varios usuarios cliente por organizacion, habra que exponer nombres/roles de autores mediante una vista o politica de lectura acotada; no ampliar la lectura de `profiles` sin revisar RLS.

## Rutas y acceso

| Ruta | Acceso | Contenido |
| --- | --- | --- |
| `/` | Todos | Redirige a `/login`, `/portal` o `/admin` al resolver la sesion. |
| `/login` | Sin sesion | Formulario email/contrasena y errores de acceso; sin registro. |
| `/portal` | Cliente | Resumen de todos los proyectos accesibles, agrupados por cliente si hace falta. |
| `/portal/projects/:projectId` | Cliente | Estado, progreso, roadmap, updates, pagos y conversacion. |
| `/admin` | Admin | Resumen compacto de clientes, proyectos activos y trabajo reciente. |
| `/admin/clients` y `/admin/clients/new` | Admin | Listado, alta y busqueda de clientes. |
| `/admin/clients/:clientId` | Admin | Datos de cliente y proyectos asociados. |
| `/admin/projects` y `/admin/projects/new` | Admin | Listado, filtros y alta de proyecto. |
| `/admin/projects/:projectId/:section` | Admin | Secciones `overview`, `phases`, `updates`, `payments`, `comments`, `activity`. |
| `/admin/payments` | Admin | Lista de pagos de todos los proyectos, filtrable por estado/vencimiento, con enlace al proyecto. |
| `/admin/updates` | Admin | Actualizaciones recientes de todos los proyectos, con enlace al proyecto. |
| `/admin/comments` | Admin | Conversaciones recientes de todos los proyectos, con enlace para responder. |
| `*` | Todos | Pagina no encontrada, sin revelar si un ID privado existe. |

`/admin/projects/:projectId` redirige a `overview`. Una visita cliente a `/admin` vuelve a `/portal`; un admin en `/portal` vuelve a `/admin`. Un ID no visible por RLS y un ID inexistente se presentan con el mismo estado de "Proyecto no disponible". No guardar el rol en `localStorage` como fuente de autorizacion.

### Sesion y perfil

1. Crear una unica instancia Supabase en `src/lib/supabase.js` con URL y publishable key publicas.
2. En el arranque, resolver el usuario con `supabase.auth.getUser()` y leer `profiles(id, full_name, role)` para ese ID. Mostrar un estado de carga estable hasta terminar; no pintar brevemente una pantalla admin al cliente.
3. Escuchar `onAuthStateChange` para entrada, salida y renovacion de sesion. Mantener el callback sin consultas asincronas; actualizar el estado y cargar perfil fuera de el. Desuscribirse al desmontar.
4. Si Auth no devuelve usuario, mostrar login. Si existe usuario pero falta perfil o el rol no es valido, mostrar un error de configuracion con opcion de cerrar sesion; no asumir `client` silenciosamente.
5. Despues de `signInWithPassword`, navegar segun `profiles.role`. En logout, limpiar estado de pantalla, llamar `signOut({ scope: 'local' })` y volver a `/login`; asi no se cierran otras sesiones de la cuenta cliente compartida.
6. Volver a consultar perfil al recargar y tras un error de permiso; si un admin pierde el rol mientras la pagina esta abierta, la UI se corrige y RLS sigue denegando operaciones.

## Pantallas y acciones

### Login

- Marca simple del portal, email y contrasena, boton de acceso, indicador de envio y error claro para credenciales invalidas o red caida. Sin enlace de registro ni flujo de recuperacion en esta etapa.
- Etiquetas visibles, autocompletado `username`/`current-password`, boton para mostrar/ocultar contrasena con icono y nombre accesible, foco en el error si falla.
- No conservar contrasenas en estado persistente ni registrar sesiones/tokens en consola.

### Portal del cliente

- `/portal`: mostrar nombre del cliente, cantidad de proyectos y lista escaneable con nombre, estado, progreso y proxima fecha. Con un solo proyecto, este se destaca como fila principal; la pagina sigue funcionando cuando haya varios.
- `/portal/projects/:id`: cabecera con nombre y estado; progreso tomado de `projects.progress_percentage`; fase activa tomada de `current_phase_id` y lista `project_phases` ordenada por `position`; fechas y descripcion del proyecto.
- Timeline de `project_updates` de mas reciente a mas antiguo; estados de pagos con descripcion, importe COP, vencimiento y estado del registro. No mostrar boton de pagar ni inferir `overdue` solo por la fecha.
- Conversacion cronologica: leer `comments` del proyecto, enviar con `user_id = auth.uid`, permitir editar o hacer soft-delete de comentario propio si `created_at` esta dentro de 15 minutos. El reloj local solo controla si se muestra el boton; la policy decide si se acepta. Refrescar tras error/guardado.
- Al completar un proyecto, mostrar fecha de cierre y mantener fases, updates, pagos y comentarios accesibles. Un proyecto sin fases o actualizaciones usa un estado vacio especifico, no un bloque en blanco.

### Area del administrador

- `/admin`: resumen orientado a trabajo, con contadores pequenos, proyectos que requieren atencion, ultimas actualizaciones y acceso directo a crear cliente/proyecto. La navegacion lleva a Clientes, Proyectos, Pagos, Actualizaciones y Comentarios. Nada de portada promocional.
- Pagos, actualizaciones y comentarios globales: listas compactas para localizar trabajo entre proyectos; filtros simples, nombre de proyecto/cliente y enlace directo a la seccion correspondiente. Las mutaciones se hacen en el detalle del proyecto para mantener el contexto.
- Clientes: listar, buscar, crear y editar `name`, `contact_name`, `contact_email`, `logo_url` y `accent_color`. Mostrar vista previa del logo con iniciales de respaldo; aplicar color solo donde conserve contraste. La asignacion de usuarios se documenta en Dashboard para el MVP.
- Proyectos: listar por cliente/estado, crear con cliente, nombre, slug editable, descripcion, fechas, estado y progreso. Validar slug y fechas antes de enviar. Mostrar errores de unicidad por cliente y restricciones de fecha con lenguaje comprensible.
- Detalle de proyecto: editar estado, descripcion, fechas y progreso (control numerico 0-100); confirmacion al completar o cancelar, opcion de reabrir. Tras guardar, usar la fila devuelta por Supabase o recargar, porque los triggers pueden cambiar progreso y `completed_at`.
- Fases: crear al final, editar nombre/descripcion/estado, borrar con confirmacion. Para pasar a otra fase activa, completar o desactivar la anterior y luego activar la siguiente, mostrando cada resultado. No prometer un cambio atomico de dos fases desde el navegador. Si el segundo paso falla, dejar el estado actual visible y ofrecer reintentar.
- Actualizaciones: publicar con `created_by = user.id`, editar solo `title`/`message`, eliminar con confirmacion. El timeline usa `created_at` del servidor.
- Pagos: crear/editar descripcion, importe, estado y vencimiento, o eliminar con confirmacion. El administrador marca `paid`/`overdue` manualmente; al volver a `pending`, el trigger limpia `paid_at`.
- Comentarios: responder, editar o hacer soft-delete para moderacion. Los comentarios eliminados pueden verse como registros marcados para el admin; el cliente ya no recibe esas filas por RLS.
- Actividad: leer `audit_logs` del proyecto, ordenar por fecha y traducir acciones conocidas (`project_progress_changed`, `phase_completed`, `payment_status_changed`, etc.) a texto legible. Mostrar `old_values`/`new_values` en un detalle sobrio solo al abrirlo.

No incluir botones de borrado fisico de proyectos o clientes en la primera UI. El backend permite operaciones administrativas, pero el cierre conserva historial y `projects.client_id` restringe borrar clientes con proyectos. La eliminacion irreversible puede disenarse despues de definir su politica de retencion.

## Carga de datos y mutaciones

| Vista | Consulta minima | Orden o filtro |
| --- | --- | --- |
| Arranque | `profiles: id, full_name, role` | `id = user.id`; cero filas es error de configuracion. |
| Portal | `client_users: client_id`; `clients: id, name, logo_url, accent_color`; `projects: id, client_id, name, status, progress_percentage, estimated_end_date` | Agrupar proyectos por `client_id`, sin escoger el primero como unico. |
| Proyecto | `projects: id, client_id, name, description, status, progress_percentage, current_phase_id, start_date, estimated_end_date, completed_at` | `id = :projectId`, `.maybeSingle()`; cero filas es "no disponible". |
| Detalle hijo | `project_phases`, `project_updates`, `payments`, `comments` con columnas usadas por cada seccion | `project_id = :projectId`; fases por `position`, updates recientes primero, comentarios antiguos primero. |
| Admin global | `clients` y `projects`; para colas, `payments`, `project_updates`, `comments` | Paginacion/limite y filtro por proyecto o estado; vincular cada fila a su proyecto. |
| Actividad admin | `audit_logs: id, user_id, project_id, action, entity_type, entity_id, old_values, new_values, created_at` | `project_id = :projectId`, fecha descendente y limite inicial. |

- El servicio de cada recurso selecciona columnas explicitas, aplica `.eq('project_id', id)` en hijos, ordena resultados y devuelve `{ data, error }` con una interfaz uniforme. Los filtros mejoran eficiencia; RLS decide visibilidad.
- Primero consultar `projects` por `:projectId` con `.maybeSingle()`. Si existe, cargar fases, updates, pagos y comentarios en paralelo. Si no existe, mostrar el mismo estado para 404 y acceso denegado. Evitar que respuestas de una ruta anterior sobrescriban la ruta nueva.
- En `/portal`, consultar `client_users`, `clients` y `projects` segun la sesion. Si no hay vinculo o proyectos, ofrecer un estado vacio util; no fabricar datos demo en produccion.
- En `/admin` y las listas globales, paginar o limitar resultados; usar filtros por cliente/estado y orden estable. No cargar todo `audit_logs` ni todas las conversaciones en el dashboard.
- En formularios, deshabilitar guardar durante la peticion, evitar doble envio y revalidar con datos del servidor. No aplicar actualizaciones optimistas para progreso, fases, pagos o cierre.
- Mapear errores comunes (credenciales, red, `23505` por slug/posicion/fase activa, checks de rango/fecha y RLS) a mensajes breves. Conservar lo escrito en formularios cuando falle el guardado. No exponer trazas SQL al cliente.
- `date` se trata como fecha de calendario, sin convertirla directamente con `new Date('YYYY-MM-DD')`; `timestamptz` se formatea en la zona horaria de la interfaz. Evitar diferencias de un dia por UTC.

## Estructura propuesta

```text
frontend/
  package.json
  .env.example
  public/_redirects
  src/
    app/App.jsx
    app/routes.jsx
    auth/AuthProvider.jsx
    lib/supabase.js
    lib/format.js
    lib/errors.js
    services/clients.js
    services/projects.js
    services/projectDetails.js
    services/comments.js
    components/ui/
    components/layout/
    features/login/
    features/portal/
    features/admin/
    styles/tokens.css
    styles/global.css
```

Agregar archivos por pantalla o recurso cuando se implementen; no crear carpetas vacias por adelantado. Un modulo de servicio puede incluir mas de una tabla si la pantalla siempre las usa juntas. CSS global solo para reset, tokens y tipografia; estilos de componentes junto a sus componentes.

## Diseno visual y accesibilidad

- Interfaz de trabajo compacta: navegacion persistente en escritorio, menu accesible en movil, contenido con ancho maximo razonable y tablas/listas que priorizan lectura. Las secciones son superficies sin tarjetas anidadas; usar tarjetas solo para elementos repetidos o herramientas delimitadas.
- Modo claro como base: fondo neutro, texto casi negro, verde petroleo para acciones, acentos coral/ambar para advertencias y estados. Modo oscuro opcional con preferencia de sistema y selector persistido localmente. `clients.accent_color` no se usa para texto si no pasa contraste.
- Tokens iniciales para modo claro: lienzo `#F4F6F5`, superficie `#FFFFFF`, texto `#1D2926`, borde `#D7E0DC`, accion `#0D6B63`, advertencia `#9A5B12` y error `#A7362B`. Son punto de partida; validar contraste en el diseno final. El modo oscuro usa neutros verdes/grises, no un fondo azul dominante.
- Iconos `lucide-react` para acciones reconocibles con tooltip o nombre accesible; estados siempre combinan texto e icono/color. Controles pequenos pero con area tactil suficiente.
- Componentes base: boton, campo, textarea, selector, badge, barra de progreso accesible, dialogo de confirmacion, tabs, tabla/lista adaptable, skeleton y alertas. No construir una libreria propia extensa antes de las pantallas.
- Verificar 320 px, 768 px y escritorio amplio; sin texto truncado que oculte datos decisivos, sin desbordamiento horizontal, sin controles superpuestos. Probar teclado, foco visible, dialogos con foco contenido, `aria-live` para errores/guardados y `prefers-reduced-motion`.

## Fases de implementacion

1. **Preparacion.** Aplicar backend en Supabase de prueba, ejecutar seed y pruebas RLS. Crear `frontend/` con Vite React, dependencias, lint, `.env.example`, `.gitignore` y cliente Supabase. Criterio: arranca localmente y el build no incluye claves secretas.
2. **Autenticacion y shell.** Implementar login, proveedor Auth, rutas protegidas, redireccion por perfil, logout, layout y estados de carga/error. Criterio: admin y cliente entran en rutas distintas; refrescar una ruta profunda conserva la sesion.
3. **Portal cliente.** Implementar lista de proyectos y detalle con fases, updates, pagos y comentarios. Criterio: ABC Construction ve el proyecto demo y sus 5 fases, 2 pagos y 2 updates; puede comentar y el segundo cliente permanece invisible.
4. **Admin de datos.** Implementar clientes, proyectos, fases, updates, pagos y respuestas con formularios, confirmaciones y refetch. Criterio: cambios se reflejan tras recargar en la cuenta cliente; cierre/reapertura y restriccion de fase activa se representan correctamente.
5. **Actividad y pulido.** Implementar audit log admin, dark mode, estados vacios, errores, accesibilidad y responsive. Criterio: flujo completo funciona con teclado y en movil, sin filtraciones de acciones admin a cliente.
6. **Verificacion y despliegue.** Ejecutar tests, build y recorrido real con ambas cuentas en entorno de prueba. Configurar Netlify y verificar rutas directas. Criterio: build publicado abre `/login`, `/portal/projects/:id` y `/admin/projects/:id/overview` al cargar directamente.

## Plan de pruebas

- Tests focalizados con Vitest y Testing Library: decisiones de ruta para sesion/rol/falta de perfil, validacion de formularios, mapeo de errores, formato de fecha/divisa y limite visual de 15 minutos en comentarios. Mockear Supabase solo en tests de UI.
- Pruebas de integracion en Supabase de prueba: ejecutar `docs/rls-test-queries.sql`; login real admin/cliente; consultar un ID de otro cliente desde la URL y desde DevTools; intentar escribir `profiles.role`, `projects.progress_percentage`, pagos y fases como cliente. Los rechazos deben provenir de RLS/grants, no de botones ocultos.
- Recorrido de navegador: admin crea/edita proyecto, fase, update y pago; cliente los ve tras refrescar; ambos comentan; cliente edita dentro del plazo; admin cierra y reabre; ambos cierran sesion. Probar red lenta, error de Supabase y sesiones caducadas.
- Calidad: `npm run build`, lint y tests; revisar consola sin errores, responsive en 320/768/1440 px, navegacion por teclado y contraste. No publicar con datos demo en una instancia de cliente real.

## Configuracion y despliegue

- `frontend/.env.example` solo documenta `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`. Los valores reales de desarrollo van en `frontend/.env.local` ignorado por Git. Cualquier variable `VITE_*` queda en el bundle, asi que nunca guardar ahi una secret/service role key.
- Netlify: base directory `frontend`, build command `npm run build`, publish directory `dist`. Copiar `frontend/public/_redirects` con `/* /index.html 200` para que funcionen rutas profundas de la SPA.
- Configurar las dos variables publicas en Netlify. Revisar dominio, HTTPS, logout y login tras despliegue. No enviar credenciales demo ni tokens a logs o analitica.

## Limites conocidos y siguientes decisiones

- El backend aun no fue ejecutado en un Supabase real desde este workspace; ese es el primer gate antes de integrar la SPA.
- Reordenar fases sin riesgo requiere una funcion/transaccion en PostgreSQL o un cambio del constraint; se deja fuera del MVP. El paso "cerrar fase actual y activar otra" tambien es de dos mutaciones, con posibilidad de estado intermedio sin fase activa.
- `payments` carece de `currency`: antes de operar con distintas monedas, agregar ese campo y adaptar el formateo.
- Multiples usuarios cliente por organizacion necesitan una forma RLS-segura de mostrar autores de comentarios y una gestion de cuentas fuera del navegador. La estructura de clientes/proyectos ya admite multiples registros.
- Realtime, archivos/entregables, recuperacion de contrasena, pagos online y notificaciones se evaluan despues del flujo base. No son dependencias de esta etapa.

## Referencias tecnicas

- React Router, instalacion declarativa: https://reactrouter.com/start/declarative/installation
- Supabase JS, cambios de Auth: https://supabase.com/docs/reference/javascript/auth-onauthstatechange
- Supabase JS, usuario actual: https://supabase.com/docs/reference/javascript/auth-getuser
- Supabase JS, cierre de sesion: https://supabase.com/docs/reference/javascript/auth-signout
- Supabase, RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- Vite, variables de entorno: https://vite.dev/guide/env-and-mode
- Netlify, directorios de build: https://docs.netlify.com/build/configure-builds/overview/
- Netlify, rutas de SPA: https://docs.netlify.com/resources/troubleshooting/page-not-found-error-guide/
