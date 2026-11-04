// HU-UBI-010 «Modificar persona (local-only)» contra las tablas reales: AppDatabase en memoria, mismo
// esquema y mismas restricciones que en el dispositivo. Cubre la lectura para editar y la escritura:
// todo o nada, auditoría sin valores, nada encolado, solo lectura y los casos límite.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 10, 26, 9, 30, 5, 456);

  Auditoria auditoria({DateTime? deletedAt}) =>
      Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', deletedAt: deletedAt);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late PersonaLocalDataSourceDrift local;

  Future<void> sembrarEspacio(String id, {String depto = '3B'}) async {
    await UbicacionLocalDataSourceDrift(db, encolador: encolador).insertarEspacio(
      EspacioModel(id: id, ubicacionId: 'ub-1', numeroDepto: depto, auditoria: auditoria()),
    );
  }

  Future<void> vincular(String vinculoId, String espacioId, {String personaId = 'per-1'}) =>
      db.customStatement(
        'INSERT INTO espacio_persona (id, espacio_id, persona_id, created_at, updated_at, '
        'created_by, sync_version) VALUES (?, ?, ?, ?, ?, ?, 0)',
        [
          vinculoId,
          espacioId,
          personaId,
          t0.millisecondsSinceEpoch,
          t0.millisecondsSinceEpoch,
          'col-1',
        ],
      );

  /// Una ubicación con el depto `esp-1` y a «María Fernández» (099 123 456) en él.
  Future<void> sembrar() async {
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
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
    await sembrarEspacio('esp-1');
    await local.registrar(
      persona: Persona(
        id: 'per-1',
        nombre: 'María',
        apellido: 'Fernández',
        telefono: '099 123 456',
        auditoria: auditoria(),
      ),
      vinculo: EspacioPersona(
        id: 'ep-1',
        espacioId: 'esp-1',
        personaId: 'per-1',
        auditoria: auditoria(),
      ),
    );
    encolador.encolados.clear();
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = PersonaLocalDataSourceDrift(db, encolador: encolador);
  });

  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> auditorias() async => [
    for (final f in await db.customSelect('SELECT * FROM audit_log').get()) f.data,
  ];

  Matcher rechaza(MotivoRechazoPersona motivo) =>
      throwsA(isA<PersonaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  Future<ResultadoModificarPersona> modificarComoSiempre({
    String nombre = 'María',
    String apellido = 'Fernández',
    String? telefono = '098 765 432',
    DateTime? ahora,
  }) => local.modificar(
    personaId: 'per-1',
    nombre: nombre,
    apellido: apellido,
    telefono: telefono,
    ahora: ahora ?? t1,
  );

  group('modificar', () {
    test('dado un teléfono nuevo, cuando modifico, cambia solo lo pedido y `updated_at`', () async {
      await sembrar();

      final r = await local.modificar(
        personaId: 'per-1',
        nombre: 'María',
        apellido: 'Fernández',
        telefono: '098 765 432',
        ahora: t1,
      );

      expect(r.huboCambios, isTrue);
      expect(r.persona.telefono, '098 765 432');
      expect(r.persona.nombre, 'María');
      final fila = await db
          .customSelect(
            'SELECT nombre, apellido, telefono, created_at, updated_at, sync_version, created_by '
            'FROM persona',
          )
          .getSingle();
      expect(fila.read<String>('nombre'), 'María');
      expect(fila.read<String>('apellido'), 'Fernández');
      expect(fila.read<String>('telefono'), '098 765 432');
      expect(fila.read<int>('created_at'), t0.millisecondsSinceEpoch);
      expect(fila.read<int>('updated_at'), t1.millisecondsSinceEpoch);
      expect(fila.read<String>('created_by'), 'col-1');
      expect(fila.read<int>('sync_version'), 0);
    });

    test(
      'dado "Gonzalez", cuando lo cambio a "González", se aplica el cambio localmente',
      () async {
        await sembrar();

        await local.modificar(
          personaId: 'per-1',
          nombre: 'María',
          apellido: 'Gonzalez',
          telefono: '099 123 456',
          ahora: t0,
        );
        final r = await local.modificar(
          personaId: 'per-1',
          nombre: 'María',
          apellido: 'González',
          telefono: '099 123 456',
          ahora: t1,
        );

        expect(r.huboCambios, isTrue);
        expect(r.persona.apellido, 'González');
      },
    );

    test('dado que vacío el teléfono y el apellido, cuando modifico, quedan sin dato', () async {
      await sembrar();

      await modificarComoSiempre(apellido: '', telefono: null);

      final leida = await local.leerParaEditar('per-1');
      expect(leida!.persona.telefono, isNull);
      expect(leida.persona.apellido, '');
    });

    test(
      'dado el mismo contenido, cuando modifico, no escribe nada: ni `updated_at` ni auditoría',
      () async {
        await sembrar();

        final r = await local.modificar(
          personaId: 'per-1',
          nombre: 'María',
          apellido: 'Fernández',
          telefono: '099 123 456',
          ahora: t1,
        );

        expect(r.huboCambios, isFalse);
        final fila = await db.customSelect('SELECT updated_at FROM persona').getSingle();
        expect(fila.read<int>('updated_at'), t0.millisecondsSinceEpoch);
        expect(await auditorias(), isEmpty);
      },
    );

    test(
      'dado un cambio, cuando modifico, deja un `persona_modificada` con solo el id, sin valores '
      'ni motivo',
      () async {
        await sembrar();

        await modificarComoSiempre(nombre: 'Marta', apellido: 'Gómez');

        final filas = await auditorias();
        expect(filas, hasLength(1));
        expect(filas.single['evento'], EventoAuditoriaLocal.personaModificada);
        expect(filas.single['evento'], 'persona_modificada');
        expect(filas.single['uuid'], 'per-1');
        expect(filas.single['motivo'], isNull);
        expect(filas.single['creado_en'], t1.millisecondsSinceEpoch);
        // Nada de lo nuevo ni de lo viejo en ninguna columna de la auditoría.
        final todo = filas.single.values.join('|');
        for (final dato in ['María', 'Fernández', 'Marta', 'Gómez', '098', '099']) {
          expect(todo, isNot(contains(dato)));
        }
      },
    );

    test('dado un cambio, cuando modifico, no encola nada: la persona es local-only', () async {
      await sembrar();

      await modificarComoSiempre();

      expect(encolador.encolados, isEmpty);
    });

    test('dado un reloj atrasado, cuando modifico, `updated_at` no retrocede', () async {
      await sembrar();
      await modificarComoSiempre(telefono: '098 000 111', ahora: t1);

      await modificarComoSiempre(telefono: '098 222 333', ahora: t0);

      final fila = await db.customSelect('SELECT updated_at FROM persona').getSingle();
      expect(fila.read<int>('updated_at'), t1.millisecondsSinceEpoch);
      final filas = await auditorias();
      expect(filas.map((f) => f['creado_en']), everyElement(t1.millisecondsSinceEpoch));
    });

    test(
      'dado que la auditoría falla, cuando modifico, la persona queda como estaba (todo o nada)',
      () async {
        await sembrar();
        await db.customStatement(
          'CREATE TRIGGER falla_auditoria BEFORE INSERT ON audit_log BEGIN '
          "SELECT RAISE(ABORT, 'sin auditoría'); END",
        );

        await expectLater(modificarComoSiempre(telefono: '098 765 432'), throwsA(anything));

        final fila = await db.customSelect('SELECT telefono, updated_at FROM persona').getSingle();
        expect(fila.read<String>('telefono'), '099 123 456');
        expect(fila.read<int>('updated_at'), t0.millisecondsSinceEpoch);
      },
    );

    test(
      'dado dos guardados seguidos sin esperar, cuando modifico, se serializan y gana el último',
      () async {
        await sembrar();

        final a = local.modificar(
          personaId: 'per-1',
          nombre: 'María',
          apellido: 'Fernández',
          telefono: '098 111 111',
          ahora: t1,
        );
        final b = local.modificar(
          personaId: 'per-1',
          nombre: 'María',
          apellido: 'Fernández',
          telefono: '098 222 222',
          ahora: t1.add(const Duration(seconds: 1)),
        );
        final r = await Future.wait([a, b]);

        expect(r.map((x) => x.huboCambios), [true, true]);
        final fila = await db.customSelect('SELECT telefono FROM persona').getSingle();
        expect(fila.read<String>('telefono'), '098 222 222');
        expect(await auditorias(), hasLength(2));
      },
    );

    test(
      'dado el mismo guardado repetido (doble toque), cuando modifico dos veces, escribe una',
      () async {
        await sembrar();

        final primera = await modificarComoSiempre();
        final segunda = await modificarComoSiempre();

        expect(primera.huboCambios, isTrue);
        expect(segunda.huboCambios, isFalse);
        expect(await auditorias(), hasLength(1));
      },
    );

    test(
      'dado un nombre largo y con caracteres especiales, cuando modifico, se guarda tal cual',
      () async {
        await sembrar();
        final largo = 'Ñandú ${'ü' * 50} 🙂';

        await modificarComoSiempre(nombre: largo, apellido: "O'Brien-Núñez");

        final leida = await local.leerParaEditar('per-1');
        expect(leida!.persona.nombre, largo);
        expect(leida.persona.apellido, "O'Brien-Núñez");
      },
    );

    test('dado una persona que no existe, cuando modifico, se rechaza', () async {
      await sembrar();

      await expectLater(
        local.modificar(
          personaId: 'no-esta',
          nombre: 'Ana',
          apellido: '',
          telefono: null,
          ahora: t1,
        ),
        rechaza(MotivoRechazoPersona.personaInexistente),
      );
      expect(await auditorias(), isEmpty);
    });

    test('dado una persona dada de baja, cuando modifico, se rechaza y no cambia nada', () async {
      await sembrar();
      await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
        t0.millisecondsSinceEpoch,
        'per-1',
      ]);

      await expectLater(modificarComoSiempre(), rechaza(MotivoRechazoPersona.personaSoloLectura));

      final fila = await db.customSelect('SELECT telefono FROM persona').getSingle();
      expect(fila.read<String>('telefono'), '099 123 456');
      expect(await auditorias(), isEmpty);
    });

    test('dado que su espacio se dio de baja, cuando modifico, se rechaza', () async {
      await sembrar();
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        t0.millisecondsSinceEpoch,
        'esp-1',
      ]);

      await expectLater(modificarComoSiempre(), rechaza(MotivoRechazoPersona.personaSoloLectura));
    });

    test('dado que su ubicación se dio de baja, cuando modifico, se rechaza', () async {
      await sembrar();
      await db.customStatement('UPDATE ubicacion SET deleted_at = ? WHERE id = ?', [
        t0.millisecondsSinceEpoch,
        'ub-1',
      ]);

      await expectLater(modificarComoSiempre(), rechaza(MotivoRechazoPersona.personaSoloLectura));
    });

    test('dado que su vínculo se dio de baja, cuando modifico, se rechaza', () async {
      await sembrar();
      await db.customStatement('UPDATE espacio_persona SET deleted_at = ? WHERE id = ?', [
        t0.millisecondsSinceEpoch,
        'ep-1',
      ]);

      await expectLater(modificarComoSiempre(), rechaza(MotivoRechazoPersona.personaSoloLectura));
    });

    test('dado dos espacios y uno de baja, cuando modifico, se puede: queda uno activo', () async {
      await sembrar();
      await sembrarEspacio('esp-2', depto: '4C');
      await vincular('ep-2', 'esp-2');
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        t0.millisecondsSinceEpoch,
        'esp-1',
      ]);

      final r = await local.modificar(
        personaId: 'per-1',
        nombre: 'María',
        apellido: 'Fernández',
        telefono: '098 765 432',
        ahora: t1,
      );

      expect(r.huboCambios, isTrue);
    });
  });

  group('leerParaEditar', () {
    test(
      'dado una persona activa, cuando la leo, trae sus datos, su espacio y se puede editar',
      () async {
        await sembrar();

        final c = await local.leerParaEditar('per-1');

        expect(c!.persona.nombre, 'María');
        expect(c.persona.apellido, 'Fernández');
        expect(c.persona.telefono, '099 123 456');
        expect(c.espacioId, 'esp-1');
        expect(c.soloLectura, isFalse);
        expect(c.causa, isNull);
      },
    );

    test('dado una persona que no está, cuando la leo, devuelve null', () async {
      await sembrar();

      expect(await local.leerParaEditar('no-esta'), isNull);
    });

    test('dado una persona de baja, cuando la leo, dice desde cuándo (32B·04)', () async {
      await sembrar();
      await db.customStatement('UPDATE persona SET deleted_at = ? WHERE id = ?', [
        t1.millisecondsSinceEpoch,
        'per-1',
      ]);

      final c = await local.leerParaEditar('per-1');

      expect(c!.causa, CausaSoloLectura.personaDeBaja);
      expect(c.bajaDesde, t1);
      expect(c.soloLectura, isTrue);
    });

    test('dado un depto de baja, cuando la leo, dice cuál y dónde (32B·08)', () async {
      await sembrar();
      await db.customStatement('UPDATE espacio SET deleted_at = ? WHERE id = ?', [
        t1.millisecondsSinceEpoch,
        'esp-1',
      ]);

      final c = await local.leerParaEditar('per-1');

      expect(c!.causa, CausaSoloLectura.espacioDeBaja);
      expect(c.numeroDepto, '3B');
      expect(c.direccion, 'Mataojo 2044');
    });

    test('dado que perdió su vínculo, cuando la leo, está sin espacio activo', () async {
      await sembrar();
      await db.customStatement('UPDATE espacio_persona SET deleted_at = ? WHERE id = ?', [
        t1.millisecondsSinceEpoch,
        'ep-1',
      ]);

      final c = await local.leerParaEditar('per-1');

      expect(c!.causa, CausaSoloLectura.sinEspacioActivo);
    });

    test('dado dos espacios, cuando la leo, trae el vigente más reciente', () async {
      await sembrar();
      await sembrarEspacio('esp-2', depto: '4C');
      await db.customStatement(
        'INSERT INTO espacio_persona (id, espacio_id, persona_id, created_at, updated_at, '
        'created_by, sync_version) VALUES (?, ?, ?, ?, ?, ?, 0)',
        ['ep-2', 'esp-2', 'per-1', t1.millisecondsSinceEpoch, t1.millisecondsSinceEpoch, 'col-1'],
      );

      final c = await local.leerParaEditar('per-1');

      expect(c!.espacioId, 'esp-2');
    });
  });
}
