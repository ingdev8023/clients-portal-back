# Verificacion del backend

Fecha: 2026-09-17/18. Proyecto de pruebas: `hmyumxnkcxnbbtieefqk` (`https://hmyumxnkcxnbbtieefqk.supabase.co`).

## PostgreSQL local

Se uso una instancia temporal de PostgreSQL 18.4 con esquemas y roles minimos que simulan `auth.users`, `auth.uid()`, `authenticated` y `anon`. La migracion principal y el seed se aplicaron sin errores; el seed se pudo repetir. Las pruebas de `docs/rls-test-queries.sql` pasaron y revirtieron sus escrituras. Las pruebas negativas rechazaron lectura anonima, elevacion del rol propio, suplantacion en comentarios, creacion de proyectos por cliente, una segunda fase activa y una fase actual no activa. La instancia temporal se apago y elimino.

## Supabase remoto

- Se vinculo el proyecto con Supabase CLI 2.117.0 y se aplicaron las dos migraciones. `db push --dry-run` confirma que no quedan migraciones pendientes.
- Las nueve tablas del portal tienen RLS habilitado. Se crearon dos usuarios confirmados mediante Auth Admin API; el trigger creo sus perfiles y se promovio solo `admin@example.com`.
- El seed remoto quedo en 2 usuarios Auth, 2 perfiles, 1 cliente, 1 proyecto, 5 fases, 2 actualizaciones, 2 pagos y 1 comentario.
- `docs/rls-test-queries.sql`, con los UUID reales y `ROLLBACK`, paso antes y despues de la migracion de endurecimiento. Verifico aislamiento entre clientes, cambios administrativos, cierre/reapertura y auditoria de borrados.
- El login real de admin y cliente funciono con la publishable key. Por PostgREST el cliente recibio 1 perfil, 1 relacion cliente, 1 cliente, 1 proyecto, 5 fases, 2 actualizaciones, 2 pagos, 1 comentario y 0 logs de auditoria. El admin recibio 2 perfiles y acceso a auditoria.
- Con JWT de cliente, una actualizacion de progreso afecto cero filas. Crear, editar y hacer soft-delete de un comentario propio funciono; el comentario eliminado quedo legible para su autor pero excluido por `deleted_at is null`, y no pudo editarse otra vez. Ese comentario temporal se elimino despues de la prueba.
- `auth.enable_signup` se cambio a `false` mediante `config push`. Una solicitud publica de signup fue rechazada y el login de la cuenta cliente existente siguio funcionando.

Las contrasenas aleatorias de las dos cuentas demo estan en `C:\Users\artej\AppData\Local\client_portal_test_credentials.json`, fuera del repositorio y con permisos limitados al usuario local. No se guardo ninguna clave secret/service-role en el proyecto. Cambia estas credenciales antes de usar cuentas reales.

## Correcciones y avisos

El soft-delete fallaba originalmente porque RLS ocultaba la fila despues de marcarla como eliminada. La policy ahora conserva lectura para el autor; la UI debe filtrar `deleted_at is null`. Una segunda migracion fijo `search_path` en nueve funciones de trigger del portal y elimino sus nueve avisos del asesor de seguridad.

Quedan avisos del asesor sobre `public.rls_auto_enable()` (funcion event trigger administrada por Supabase con grants de ejecucion) y sobre la proteccion contra contrasenas filtradas desactivada. No se modifico la funcion administrada. La prueba del frontend visual aun no aplica porque esa etapa no esta implementada.
