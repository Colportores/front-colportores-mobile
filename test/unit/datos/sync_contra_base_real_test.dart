// I3 (#183): el día de trabajo del colportor contra el servidor de verdad — `public.sync_push` y
// `public.sync_pull` de las migraciones del backend, detrás de PostgREST — y no contra el falso, que
// acepta cualquier cosa que tenga forma de fila (no comprueba FK, ni UUID, ni versiones).
//
// Es la «pasada contra Supabase» de la demo. No corre sola: pide una base levantada con las
// migraciones y el seed de `backend-supabase` y un JWT del colportor de la demo. Los pasos están en
// `test/fixtures/sync_real/LEEME.md`. Con estas variables:
//
//   SYNC_REAL_URL=http://host.docker.internal:55184   (PostgREST, sin el prefijo `/rest/v1`)
//   SYNC_REAL_JWT=<JWT HS256 con sub = colportorDemo y role = authenticated>
//
// Sin ellas el grupo se saltea. Usa `SupabaseRpcTransport`, el mismo que arma la app.
import 'dart:io';
import 'dart:math';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../helpers/dia_de_trabajo.dart';
import '../../helpers/logger_mudo.dart';

final _url = Platform.environment['SYNC_REAL_URL'];
final _jwt = Platform.environment['SYNC_REAL_JWT'];

/// PostgREST sirve las RPC en `/rpc/…`; Supabase las expone bajo `/rest/v1/rpc/…`.
final class _SinPrefijo extends http.BaseClient {
  _SinPrefijo(this._cliente);

  final http.Client _cliente;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final sin = request.url.path.replaceFirst('/rest/v1', '');
    final reescrita = http.Request(request.method, request.url.replace(path: sin))
      ..headers.addAll(request.headers);
    if (request is http.Request) reescrita.bodyBytes = request.bodyBytes;
    return _cliente.send(reescrita);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final sinBase = _url == null || _jwt == null;

  group(
    'contra una base real (SYNC_REAL_URL)',
    skip: sinBase ? 'sin SYNC_REAL_URL y SYNC_REAL_JWT: pide una base levantada' : false,
    () {
      late AppDatabase db;
      late SyncEngine motor;
      late DiaDeTrabajo dia;
      final usados = <int>{};

      /// Cada test trabaja en un día distinto y lejano: dos jornadas del mismo colportor no se
      /// pisan en el servidor, ni entre tests ni entre corridas.
      DateTime inicioDeUnDiaLibre() {
        final azar = Random();
        int dias;
        do {
          dias = 3 + azar.nextInt(900);
        } while (!usados.add(dias));
        final hoy = DateTime.now().toUtc();
        return DateTime.utc(hoy.year, hoy.month, hoy.day, 12).subtract(Duration(days: dias));
      }

      setUp(() {
        db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
        motor = SyncEngine(
          specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
          transport: SupabaseRpcTransport(
            projectUrl: Uri.parse(_url!),
            anonKey: 'anon',
            token: () async => _jwt,
            device: const ClientEnvelope(
              deviceId: '01920000-0000-7000-8000-00000000d001',
              appVersion: '0.0.0-test',
            ),
            client: _SinPrefijo(http.Client()),
          ),
          jobs: DriftJobStore(db),
          meta: DriftSyncMeta(db),
          store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
        );
        final azar = Random();
        dia = DiaDeTrabajo(
          db,
          motor,
          inicio: inicioDeUnDiaLibre(),
          calle: 'Calle ${azar.nextInt(1 << 30)}',
          numero: '${1 + azar.nextInt(9000)}',
          lat: -34.9 + azar.nextDouble() * 0.5,
          lon: -56.2 + azar.nextDouble() * 0.5,
        );
      });
      tearDown(() async {
        await motor.dispose();
        await db.close();
      });

      Future<SyncStatus> cola() => DriftJobStore(db).status();

      /// Lo que el servidor rechazó, para que el rojo diga qué fue.
      Future<String> rechazos() async => [
        for (final f in await motor.failedOperations())
          '${f.entity}/${f.op.name} ${f.code}: ${f.lastError}',
      ].join(' | ');
      Future<int> filas(String tabla) async =>
          (await db.customSelect('select count(*) c from $tabla').getSingle()).read<int>('c');

      test('el día entero sin señal sube de una vez sin rechazos y baja el catálogo', () async {
        await dia.correrTodo();
        expect((await cola()).pending, greaterThan(0));

        final resultado = await motor.syncNow();

        expect(resultado.failure, isNull);
        expect(
          resultado.invalidated,
          0,
          reason: 'el servidor aceptó todos los jobs: ${await rechazos()}',
        );
        expect(resultado.conflicts, 0);
        expect((await cola()).pending, 0);
        expect((await cola()).invalid, 0);
        expect(await filas('producto'), greaterThan(0), reason: 'bajó el catálogo');
        expect(await filas('ciudad'), greaterThan(0));
        expect(await filas('campania_colportor'), greaterThan(0), reason: 'su inscripción');
      });

      test('las correcciones de después usan la versión que dio el servidor', () async {
        await dia.correrTodo();
        expect((await motor.syncNow()).invalidated, 0);

        await dia.corregirLaCalle('Rivera 2', minuto: 100);
        var r = await motor.syncNow();
        expect(
          [r.invalidated, r.conflicts],
          [0, 0],
          reason: 'primera corrección: ${await rechazos()}',
        );

        await dia.corregirLaCalle('Rivera 3', minuto: 110);
        r = await motor.syncNow();
        expect([r.invalidated, r.conflicts], [0, 0], reason: 'segunda corrección');

        await dia.visitaSinCita(minuto: 120);
        r = await motor.syncNow();
        expect([r.invalidated, r.conflicts], [0, 0], reason: 'otra visita: cambia el color');

        final otra = await dia.agendarOtra(dias: 3, minuto: 130);
        r = await motor.syncNow();
        expect([r.invalidated, r.conflicts], [0, 0], reason: 'otra agenda');
        await dia.cancelar(otra, minuto: 140);
        r = await motor.syncNow();
        expect([r.invalidated, r.conflicts], [0, 0], reason: 'cancelarla');

        expect((await cola()).pending, 0);
        expect((await cola()).invalid, 0);
      });

      test('cerrar la jornada después de subirla no la reabre en el teléfono', () async {
        await dia.empezarJornada();
        expect((await motor.syncNow()).invalidated, 0);

        await dia.cerrarJornada();
        final r = await motor.syncNow();

        expect([r.invalidated, r.conflicts], [0, 0]);
        final abiertas = await db
            .customSelect('select count(*) c from jornada where fin is null')
            .getSingle();
        expect(abiertas.read<int>('c'), 0, reason: 'el LWW no la reabrió');
      });

      test('reenviar lo mismo no duplica ni rechaza: el servidor lo reconoce', () async {
        await dia.correrTodo();
        await motor.syncNow();

        final r = await motor.syncNow();

        expect([r.pushed, r.invalidated, r.conflicts], [0, 0, 0]);
        expect(r.failure, isNull);
      });
    },
  );
}
