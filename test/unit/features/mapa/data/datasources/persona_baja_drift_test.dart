// Baja y reactivación de una persona (HU-UBI-011) contra las tablas reales: AppDatabase en memoria,
// mismo esquema y mismas restricciones que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_nota.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);
  final baja = DateTime.utc(2026, 10, 25, 9, 30);

  Auditoria auditoria({DateTime? creada, DateTime? deletedAt}) => Auditoria(
    createdAt: creada ?? t0,
    updatedAt: creada ?? t0,
    createdBy: 'col-1',
    deletedAt: deletedAt,
  );

  Persona persona(String id, {String nombre = 'Ana', DateTime? creada}) => Persona(
    id: id,
    nombre: nombre,
    apellido: 'Martínez',
    telefono: '099 123 456',
    auditoria: auditoria(creada: creada),
  );

  EspacioPersona vinculo(String personaId, {String espacioId = 'esp-1'}) => EspacioPersona(
    id: 'ep-$personaId',
    espacioId: espacioId,
    personaId: personaId,
    auditoria: auditoria(),
  );

  NotaPersona nota(String personaId) => NotaPersona(
    id: 'nota-$personaId',
    personaId: personaId,
    texto: 'Prefiere de tarde',
    auditoria: auditoria(),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late PersonaLocalDataSourceDrift local;

  Future<void> sembrarEdificio() async {
    await ubicaciones.insertar(
      UbicacionModel(
        id: 'ub-1',
        tipo: TipoUbicacion.edificio,
        calle: 'Mataojo',
        numero: '2044',
        lat: -34.89,
        lon: -56.16,
        ciudadId: 'mvd',
        auditoria: auditoria(),
      ),
    );
    await ubicaciones.insertarEspacio(
      EspacioModel(id: 'esp-1', ubicacionId: 'ub-1', numeroDepto: '101', auditoria: auditoria()),
    );
  }

  Future<void> registrar(String id, {bool conNota = false, DateTime? creada}) async {
    await local.registrar(
      persona: persona(id, creada: creada),
      vinculo: vinculo(id),
      nota: conNota ? nota(id) : null,
    );
    encolador.encolados.clear();
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    local = PersonaLocalDataSourceDrift(db, encolador: encolador);
    await sembrarEdificio();
    encolador.encolados.clear();
  });

  tearDown(() => db.close());

  Future<int> filas(String tabla) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle()).read<int>('n');

  Future<List<AuditLogFila>> auditorias() => db.select(db.auditLogLocal).get();

  Matcher rechaza(MotivoRechazoPersona motivo) =>
      throwsA(isA<PersonaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  group('darDeBaja', () {
    test('dada una persona activa, cuando se da de baja, setea deleted_at y updated_at y deja el '
        'evento persona_baja con su motivo', () async {
      await registrar('per-1');

      final r = await local.darDeBaja(personaId: 'per-1', ahora: baja, motivo: 'Se mudó');

      expect(r.auditoria.deletedAt, baja);
      expect(r.auditoria.updatedAt, baja);
      expect(r.auditoria.createdAt, t0);
      final guardadas = await auditorias();
      expect(guardadas, hasLength(1));
      expect(guardadas.single.evento, EventoAuditoriaLocal.personaBaja);
      expect(guardadas.single.uuid, 'per-1');
      expect(guardadas.single.motivo, 'Se mudó');
      expect(guardadas.single.creadoEn, baja);
    });

    test('dada una baja sin motivo, el evento queda igual y el motivo es nulo', () async {
      await registrar('per-1');

      await local.darDeBaja(personaId: 'per-1', ahora: baja);

      final guardadas = await auditorias();
      expect(guardadas.single.evento, 'persona_baja');
      expect(guardadas.single.motivo, isNull);
    });

    test('dada una baja, es local: no encola nada y el historial y las notas quedan', () async {
      await registrar('per-1', conNota: true);

      await local.darDeBaja(personaId: 'per-1', ahora: baja);

      expect(encolador.encolados, isEmpty);
      expect(await filas('persona'), 1);
      expect(await filas('espacio_persona'), 1);
      expect(await filas('nota'), 1);
      final nota = await db.customSelect('SELECT deleted_at FROM nota').getSingle();
      expect(nota.data['deleted_at'], isNull);
    });

    test('dada una persona de baja, sus notas se ven pero no se pueden agregar ni cambiar (solo '
        'lectura), y al reactivarla vuelven a poder', () async {
      await registrar('per-1', conNota: true);
      final notas = NotaPersonaLocalDataSourceDrift(db);
      await local.darDeBaja(personaId: 'per-1', ahora: baja);

      final vistas = await notas.observar('per-1').first;
      expect(vistas.map((n) => n.id), ['nota-per-1']);
      await expectLater(
        notas.agregar(
          NotaPersona(id: 'nota-2', personaId: 'per-1', texto: 'Otra', auditoria: auditoria()),
        ),
        throwsA(
          isA<NotaRechazadaException>().having(
            (e) => e.motivo,
            'motivo',
            MotivoRechazoNota.soloLectura,
          ),
        ),
      );

      await local.reactivar(personaId: 'per-1', ahora: baja.add(const Duration(days: 1)));
      final agregada = await notas.agregar(
        NotaPersona(id: 'nota-2', personaId: 'per-1', texto: 'Otra', auditoria: auditoria()),
      );
      expect(agregada.id, 'nota-2');
    });

    test('dada una persona de baja, deja de estar entre las activas del espacio y no cuenta para '
        'la baja del espacio', () async {
      await registrar('per-1');
      await registrar('per-2', creada: t0.add(const Duration(minutes: 1)));
      expect(await local.activasEn('esp-1'), 2);

      await local.darDeBaja(personaId: 'per-1', ahora: baja);

      expect(await local.activasEn('esp-1'), 1);
      final activas = await local.observarDelEspacio('esp-1').first;
      expect(activas.map((p) => p.persona.id), ['per-2']);
    });

    test('dado un doble toque (la baja repetida), cuando se vuelve a pedir, no escribe ni deja '
        'una segunda fila de auditoría', () async {
      await registrar('per-1');
      await local.darDeBaja(personaId: 'per-1', ahora: baja, motivo: 'Se mudó');

      final segunda = await local.darDeBaja(
        personaId: 'per-1',
        ahora: baja.add(const Duration(minutes: 5)),
        motivo: 'Otro',
      );

      expect(segunda.auditoria.deletedAt, baja);
      expect(await auditorias(), hasLength(1));
    });

    test('dados dos pedidos casi simultáneos, se serializan y queda una sola baja', () async {
      await registrar('per-1');

      await Future.wait([
        local.darDeBaja(personaId: 'per-1', ahora: baja),
        local.darDeBaja(personaId: 'per-1', ahora: baja.add(const Duration(seconds: 1))),
      ]);

      expect(await auditorias(), hasLength(1));
      final fila = await db.customSelect('SELECT deleted_at FROM persona').getSingle();
      expect(fila.read<int>('deleted_at'), baja.millisecondsSinceEpoch);
    });

    test(
      'dado un reloj atrasado (antes del updated_at de la fila), el updated_at no retrocede',
      () async {
        await registrar('per-1');

        final r = await local.darDeBaja(
          personaId: 'per-1',
          ahora: t0.subtract(const Duration(days: 1)),
        );

        expect(r.auditoria.updatedAt.isBefore(r.auditoria.createdAt), isFalse);
        expect(r.auditoria.deletedAt, r.auditoria.updatedAt);
      },
    );

    test('dada una persona que no está, cuando se da de baja, rechaza y no escribe', () async {
      await expectLater(
        local.darDeBaja(personaId: 'nadie', ahora: baja),
        rechaza(MotivoRechazoPersona.personaInexistente),
      );
      expect(await auditorias(), isEmpty);
    });

    test('dado un espacio dado de baja, la persona es de solo lectura: no se la da de baja y no '
        'queda rastro', () async {
      await registrar('per-1');
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        baja.millisecondsSinceEpoch,
        'esp-1',
      ]);

      await expectLater(
        local.darDeBaja(personaId: 'per-1', ahora: baja),
        rechaza(MotivoRechazoPersona.personaSoloLectura),
      );
      expect(await auditorias(), isEmpty);
      final fila = await db.customSelect('SELECT deleted_at FROM persona').getSingle();
      expect(fila.data['deleted_at'], isNull);
    });

    test('dada la ubicación dada de baja, la persona es de solo lectura', () async {
      await registrar('per-1');
      await db.customStatement('UPDATE ubicacion SET deleted_at = ? WHERE id = ?', [
        baja.millisecondsSinceEpoch,
        'ub-1',
      ]);

      await expectLater(
        local.darDeBaja(personaId: 'per-1', ahora: baja),
        rechaza(MotivoRechazoPersona.personaSoloLectura),
      );
    });

    test('dada una falla al dejar la auditoría, no queda la baja a medias', () async {
      await registrar('per-1');
      await db.customStatement('DROP TABLE audit_log');

      await expectLater(local.darDeBaja(personaId: 'per-1', ahora: baja), throwsA(anything));

      final fila = await db.customSelect('SELECT deleted_at FROM persona').getSingle();
      expect(fila.data['deleted_at'], isNull);
    });
  });

  group('reactivar', () {
    test('dada una persona de baja, cuando se reactiva, deleted_at vuelve a nulo y vuelve a la '
        'lista activa', () async {
      await registrar('per-1');
      await local.darDeBaja(personaId: 'per-1', ahora: baja);
      final despues = baja.add(const Duration(days: 1));

      final r = await local.reactivar(personaId: 'per-1', ahora: despues);

      expect(r.auditoria.deletedAt, isNull);
      expect(r.auditoria.updatedAt, despues);
      expect(await local.activasEn('esp-1'), 1);
      expect(encolador.encolados, isEmpty);
    });

    test('dada una persona activa, cuando se reactiva, no escribe nada', () async {
      await registrar('per-1');

      final r = await local.reactivar(personaId: 'per-1', ahora: baja);

      expect(r.auditoria.updatedAt, t0);
    });

    test('dada una baja y una reactivación y otra baja, cada baja deja su evento', () async {
      await registrar('per-1');
      await local.darDeBaja(personaId: 'per-1', ahora: baja);
      await local.reactivar(personaId: 'per-1', ahora: baja.add(const Duration(days: 1)));
      await local.darDeBaja(personaId: 'per-1', ahora: baja.add(const Duration(days: 2)));

      final guardadas = await auditorias();
      expect(guardadas, hasLength(2));
      expect(guardadas.map((a) => a.creadoEn), [baja, baja.add(const Duration(days: 2))]);
    });

    test('dado el espacio dado de baja, no se reactiva a nadie', () async {
      await registrar('per-1');
      await local.darDeBaja(personaId: 'per-1', ahora: baja);
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        baja.millisecondsSinceEpoch,
        'esp-1',
      ]);

      await expectLater(
        local.reactivar(personaId: 'per-1', ahora: baja),
        rechaza(MotivoRechazoPersona.personaSoloLectura),
      );
    });

    test('dada una persona que no está, rechaza', () async {
      await expectLater(
        local.reactivar(personaId: 'nadie', ahora: baja),
        rechaza(MotivoRechazoPersona.personaInexistente),
      );
    });
  });

  group('observarBajasDelEspacio', () {
    test(
      'lista solo las de baja de ese espacio, la más reciente primero, y se actualiza sola',
      () async {
        await registrar('per-1');
        await registrar('per-2', creada: t0.add(const Duration(minutes: 1)));
        await registrar('per-3', creada: t0.add(const Duration(minutes: 2)));
        final emisiones = <List<String>>[];
        final suscripcion = local
            .observarBajasDelEspacio('esp-1')
            .listen((l) => emisiones.add([for (final p in l) p.persona.id]));
        addTearDown(suscripcion.cancel);
        await pumpEventQueue();
        expect(emisiones.last, isEmpty);

        await local.darDeBaja(personaId: 'per-1', ahora: baja);
        await pumpEventQueue();
        expect(emisiones.last, ['per-1']);

        await local.darDeBaja(personaId: 'per-3', ahora: baja.add(const Duration(hours: 1)));
        await pumpEventQueue();
        expect(emisiones.last, ['per-3', 'per-1']);

        await local.reactivar(personaId: 'per-1', ahora: baja.add(const Duration(hours: 2)));
        await pumpEventQueue();
        expect(emisiones.last, ['per-3']);
      },
    );

    test('no mezcla las bajas de otro espacio', () async {
      await ubicaciones.insertarEspacio(
        EspacioModel(id: 'esp-2', ubicacionId: 'ub-1', numeroDepto: '102', auditoria: auditoria()),
      );
      await registrar('per-1');
      await local.registrar(
        persona: persona('per-2'),
        vinculo: vinculo('per-2', espacioId: 'esp-2'),
      );
      await local.darDeBaja(personaId: 'per-1', ahora: baja);
      await local.darDeBaja(personaId: 'per-2', ahora: baja);

      final deUno = await local.observarBajasDelEspacio('esp-1').first;
      final deDos = await local.observarBajasDelEspacio('esp-2').first;

      expect(deUno.map((p) => p.persona.id), ['per-1']);
      expect(deDos.map((p) => p.persona.id), ['per-2']);
    });
  });
}
