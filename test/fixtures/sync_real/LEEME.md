# La pasada contra una base real

`test/unit/datos/sync_contra_base_real_test.dart` corre el día de trabajo del colportor contra
`public.sync_push` y `public.sync_pull` de verdad (las migraciones de `backend-supabase`, detrás de
PostgREST). El servidor falso del motor no comprueba FK, UUID ni versiones; este sí. Se corre a mano
antes de una demo y cuando cambia el contrato del sync. En CI se saltea.

1. Base: en un checkout de `backend-supabase` (`develop`), con su `compose.dev.yml`:
   `DB_PORT=55183 docker compose -p be183 up -d db`, después
   `docker compose -p be183 run --rm -T cli bash scripts/db-migrate.sh`.
2. Datos: `psql <db> -f test/fixtures/sync_real/fixtures.sql` (este archivo) y
   `docker compose -p be183 run --rm -T cli bash scripts/db-seed.sh` (catálogo, zonas y precios).
3. `auth.uid()` de la imagen local solo lee `request.jwt.claim.sub`; PostgREST 14 manda
   `request.jwt.claims`. Como `supabase_admin`: `create or replace function auth.uid() returns uuid
   language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true),
   ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;`
   y `alter role authenticator with password 'postgres'`.
4. PostgREST en la red de la base: `docker run -d --network be183_default -p 55184:3000
   -e PGRST_DB_URI=postgres://authenticator:postgres@db:5432/postgres -e PGRST_DB_SCHEMAS=public
   -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET=<32+ caracteres>
   ghcr.io/supabase/postgrest:v14.5`.
5. JWT HS256 firmado con ese secreto y `{"sub": "01920000-0000-7000-8000-00000000c001", "role":
   "authenticated", "aud": "authenticated", "exp": <lejos>}`.
6. El test, dentro del contenedor de Flutter (que ve el host como `host.docker.internal`):
   `SYNC_REAL_URL=http://host.docker.internal:55184 SYNC_REAL_JWT=<jwt> flutter test
   --concurrency=1 test/unit/datos/sync_contra_base_real_test.dart`.

Cada test elige un día lejano y una dirección al azar: la misma base sirve para varias corridas.
