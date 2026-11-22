-- Los datos del colportor de la demo para la pasada contra una base real (ver LEEME.md):
-- un colportor, su coordinador, una ciudad y una campaña larga en la que está inscripto (los días de
-- trabajo del test caen dentro de ella: el servidor rechaza una jornada anterior al inicio).
-- Los ids son los de `colportorDemo` y `ciudadDemo` de test/helpers/dia_de_trabajo.dart.
\set ON_ERROR_STOP on

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, confirmed_at, created_at, updated_at)
values ('01920000-0000-7000-8000-00000000c001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'demo183@example.com', 'x', now(), now(), now()),
       ('01920000-0000-7000-8000-00000000c0d1', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'coord183@example.com', 'x', now(), now(), now());
insert into public.usuario_rol (usuario_id, rol_id)
select '01920000-0000-7000-8000-00000000c001', r.id from public.rol r where r.codigo = 'COLPORTOR';
insert into public.usuario_rol (usuario_id, rol_id)
select '01920000-0000-7000-8000-00000000c0d1', r.id from public.rol r where r.codigo = 'COORDINADOR';
insert into public.pais (id, nombre, iso_code) values ('01920000-0000-7000-8000-00000000c0f0', 'Pais 183', 'ZZ');
insert into public.ciudad (id, nombre, departamento, pais_id, lat_centro, lon_centro)
values ('01920000-0000-7000-8000-00000000c002', 'Ciudad 183', 'Depto 183', '01920000-0000-7000-8000-00000000c0f0', -34.9, -56.16);
insert into public.campania (id, nombre, tipo, fecha_inicio, fecha_fin, coordinador_id)
values ('01920000-0000-7000-8000-00000000c0e1', 'Campania 183', 'VERANO',
        public.hoy_montevideo() - 1500, public.hoy_montevideo() + 400, '01920000-0000-7000-8000-00000000c0d1');
insert into public.campania_ciudad (id, campania_id, ciudad_id)
values ('01920000-0000-7000-8000-00000000c0e2', '01920000-0000-7000-8000-00000000c0e1', '01920000-0000-7000-8000-00000000c002');
insert into public.campania_colportor (campania_id, usuario_id, deleted_at)
values ('01920000-0000-7000-8000-00000000c0e1', '01920000-0000-7000-8000-00000000c001', null);

