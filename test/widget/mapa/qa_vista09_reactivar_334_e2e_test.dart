// QA de «Reactivar una baja» (HU-UBI-005, #334, PR #366) de punta a punta con la base real: la Lista
// «Con bajas» (la pantalla real), el caso de uso, el repositorio y Drift en memoria (con la tabla de
// auditoría local y la cola de sync). Los tests del PR prueban la pantalla con un repositorio falso y la
// guarda con Drift sin pantalla; estos prueban que una persona, tocando, ve lo que la HU promete y que
// del teléfono no se pierde ni se pisa nada.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/duplicados_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_reactivar_334_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// El "ahora" de los tests de la Lista (`ahoraLista`): las reactivaciones y las bajas nuevas se
/// escriben con este instante.
final _t0 = DateTime.utc(2026, 9, 1, 10);
final _el12 = DateTime.utc(2026, 9, 12, 15);
final _el03 = DateTime.utc(2026, 9, 3, 15);

void main() {
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;
  late UbicacionRepositoryImpl repositorio;
  late _SalidaEnMemoria salida;

  UbicacionModel ubicacion(
    String id, {
    required String calle,
    required String numero,
    double metrosAlNorte = 0,
    DateTime? baja,
    DateTime? actualizada,
    String ciudadId = 'ciu-mvd',
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
    lat: puntoItalia.lat + metrosAlNorte / 111195.08,
    lon: puntoItalia.lon,
    ciudadId: ciudadId,
    auditoria: Auditoria(
      createdAt: _t0,
      updatedAt: actualizada ?? _t0,
      createdBy: 'col-1',
      deletedAt: baja,
      syncVersion: 3,
    ),
  );

  Future<void> motivo(String id, DateTime cuando, String texto) => db
      .into(db.auditLogLocal)
      .insert(
        AuditLogLocalCompanion.insert(
          evento: EventoAuditoriaLocal.ubicacionBaja,
          uuid: id,
          motivo: Value(texto),
          creadoEn: cuando,
        ),
      );

  Future<UbicacionModel> guardada(WidgetTester tester, String id) async =>
      (await tester.runAsync(() => local.obtener(id)))!;

  Future<List<AuditLogFila>> auditoria(WidgetTester tester) async => (await tester.runAsync(
    () => (db.select(db.auditLogLocal)..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
  ))!;

  /// Arma el teléfono: `[inserciones]` corre dentro de `runAsync` (la base real no avanza con el
  /// reloj falso del test).
  Future<void> armar(WidgetTester tester, Future<void> Function() inserciones) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
    );
    salida = _SalidaEnMemoria();
    repositorio = UbicacionRepositoryImpl(local, logger: AppLogger(output: salida));
    await tester.runAsync(() async {
      await inserciones();
      encolador.encolados.clear();
    });
  }

  /// Un test de la Lista con la base real: al terminar desmonta la pantalla (Drift deja un timer al
  /// cancelar el stream de la Lista) y cierra la base.
  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    });
  }

  /// Monta la Lista real con «Con bajas».
  Future<void> montar(
    WidgetTester tester, {
    Size tamano = t390x844,
    AlAbrirUbicacion? alAbrir,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ubicacionRepositoryProvider.overrideWithValue(repositorio),
          ...overridesLista(repo: RepoListaFalso()).skip(1),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => RepaintBoundary(
            key: raizCaptura334,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: ListaUbicacionesPage(
              colportorId: 'col-1',
              activa: true,
              alAbrirUbicacion: alAbrir,
            ),
          ),
        ),
      ),
    );
    await _esperarBase(tester);
    await abrirHojaFiltros(tester);
    await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
    await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
    await _esperarBase(tester);
    await tester.ensureVisible(botonVerUbicaciones);
    await tester.tap(botonVerUbicaciones);
    await _esperarBase(tester);
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
    await tester.tap(f);
    await _esperarBase(tester);
  }

  Finder baja1240() => find.text('Av. Italia 1240');

  /// La dirección de la fila que es una baja (cuando hay otra activa con el mismo texto).
  Finder bajaDeItalia() => find.descendant(
    of: find.byWidgetPredicate((w) => w is FilaUbicacionLista && w.item.esBaja),
    matching: find.text('Av. Italia 1240'),
  );
  Finder botonReactivar() => find.widgetWithText(FilledButton, TextosReactivar.reactivar);

  group('QA 09·03/04 · de punta a punta con la base real (Drift en memoria)', () {
    prueba('dado una baja común y una baja por unión (hecha con «Conservar A y unir»), entonces '
        'la Lista dice el motivo de la primera y «Unida a otra ubicación» en la segunda, que no se '
        'abre al tocarla', (tester) async {
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await motivo('baja-1', _el12, 'Ya no existe');
        await local.insertar(
          ubicacion('ub-a', calle: 'Orinoco', numero: '5031', metrosAlNorte: 400),
        );
        await local.insertar(
          ubicacion('ub-b', calle: 'Michigan', numero: '1552', metrosAlNorte: 900),
        );
        await local.unirDuplicada('ub-a', 'ub-b', ahora: _el03);
      });
      await montar(tester);

      expect(find.text('Casa · baja el 12/09 · Ya no existe'), findsOneWidget);
      expect(find.text('Casa · baja el 03/09 · Unida a otra ubicación'), findsOneWidget);
      expect(find.textContaining('duplicado_de'), findsNothing);

      await tester.tap(find.text('Michigan 1552'));
      await _esperarBase(tester);
      expect(find.byType(HojaReactivarUbicacion), findsNothing);
      expect(find.text('Dada de baja'), findsNothing);
    });

    prueba('dado «Reactivar» y luego «Deshacer», entonces la casa vuelve a la lista y a la base, '
        'se encola un solo update por paso y «Deshacer» la deja de baja con el mismo motivo', (
      tester,
    ) async {
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await motivo('baja-1', _el12, 'Está deshabitada');
      });
      await montar(tester);
      await tocar(tester, baja1240());
      expect(find.text('Está deshabitada'), findsWidgets);

      await tocar(tester, botonReactivar());
      await tester.pump(const Duration(milliseconds: 700));

      expect((await guardada(tester, 'baja-1')).auditoria.deletedAt, isNull);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
      expect(
        find.text('Av. Italia 1240 reactivada. Vuelve a aparecer en el mapa.'),
        findsOneWidget,
      );
      expect(find.text('BAJA'), findsNothing);

      await tester.tap(find.text('Deshacer'));
      await _esperarBase(tester);
      await tester.pump(const Duration(milliseconds: 900));

      final vuelta = await guardada(tester, 'baja-1');
      expect(vuelta.auditoria.deletedAt, isNotNull);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion', 'ubicacion']);
      final eventos = await auditoria(tester);
      expect(
        eventos.last.motivo,
        'Está deshabitada',
        reason: 'la auditoría guarda el mismo motivo',
      );
      expect(
        find.text('Casa · baja el ${_diaMes(vuelta.auditoria.deletedAt!)} · Está deshabitada'),
        findsOneWidget,
      );
    });

    prueba('HU «Reactivación con la ciudad fuera del catálogo»: la casa se reactiva igual, '
        'se encola el update y la hoja no inventa una ciudad', (tester) async {
      await armar(tester, () async {
        await local.insertar(
          ubicacion(
            'baja-1',
            calle: 'Av. Italia',
            numero: '1240',
            baja: _el12,
            ciudadId: 'ciu-que-ya-no-esta',
          ),
        );
        await motivo('baja-1', _el12, 'Ya no existe');
      });
      await montar(tester);
      await tocar(tester, baja1240());
      expect(find.text('Dada de baja'), findsOneWidget);
      expect(find.textContaining('Montevideo'), findsNothing);

      await tocar(tester, botonReactivar());

      expect((await guardada(tester, 'baja-1')).auditoria.deletedAt, isNull);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
      expect(
        find.text('Av. Italia 1240 reactivada. Vuelve a aparecer en el mapa.'),
        findsOneWidget,
      );
    });

    prueba('dado que hay otra casa activa con la misma dirección a menos de 100 m, entonces la '
        'hoja dice «No se puede reactivar» con la dirección, «Abrir la existente» abre esa y la '
        'base no cambia (ni cola ni auditoría)', (tester) async {
      final abiertas = <String>[];
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await motivo('baja-1', _el12, 'Ya no existe');
        await local.insertar(
          ubicacion('viva', calle: 'Av. Italia', numero: '1240', metrosAlNorte: 30),
        );
      });
      await montar(tester, alAbrir: (id, _) => abiertas.add(id));
      final antes = await guardada(tester, 'baja-1');
      final filasAntes = (await auditoria(tester)).length;
      // Hay dos filas con la misma dirección; la de baja lleva «BAJA».
      await tocar(tester, bajaDeItalia());

      await tocar(tester, botonReactivar());

      expect(find.text('No se puede reactivar'), findsOneWidget);
      expect(
        find.text(
          'No puede haber dos ubicaciones con la misma dirección a menos de 100 m, y Av. Italia '
          '1240 ya está activa. Si es la misma, seguí usando esa; si es otra puerta, abrila y '
          'agregala como espacio.',
        ),
        findsOneWidget,
      );
      expect(await guardada(tester, 'baja-1'), antes);
      expect(encolador.encolados, isEmpty);
      expect((await auditoria(tester)).length, filasAntes);

      await tocar(tester, find.text('Abrir la existente'));
      expect(abiertas, ['viva']);
    });

    prueba('dado dos casas activas con esa dirección, entonces la hoja abre la más cercana a la '
        'baja', (tester) async {
      final abiertas = <String>[];
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await local.insertar(
          ubicacion('lejos', calle: 'Av. Italia', numero: '1240', metrosAlNorte: 80),
        );
        await local.insertar(
          ubicacion('cerca', calle: 'AV. ITALIA', numero: '1240', metrosAlNorte: 15),
        );
      });
      await montar(tester, alAbrir: (id, _) => abiertas.add(id));
      await tocar(tester, bajaDeItalia());
      await tocar(tester, botonReactivar());

      await tocar(tester, find.text('Abrir la existente'));

      expect(abiertas, ['cerca']);
    });

    prueba('dado que la baja se une a otra mientras la hoja está abierta, entonces «Reactivar» '
        'dice que se unió, ofrece abrir la conservada y no escribe nada', (tester) async {
      final abiertas = <String>[];
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await motivo('baja-1', _el12, 'Ya no existe');
        await local.insertar(
          ubicacion('ub-a', calle: 'Orinoco', numero: '5031', metrosAlNorte: 400),
        );
      });
      await montar(tester, alAbrir: (id, _) => abiertas.add(id));
      await tocar(tester, baja1240());
      final antes = await guardada(tester, 'baja-1');
      // Llega la unión (el motivo de la auditoría pasa a `duplicado_de_ub-a`).
      await tester.runAsync(() async {
        await (db.update(db.auditLogLocal)..where((t) => t.uuid.equals('baja-1'))).write(
          const AuditLogLocalCompanion(motivo: Value('duplicado_de_ub-a')),
        );
      });
      encolador.encolados.clear();

      await tocar(tester, botonReactivar());

      expect(
        find.text('Esta ubicación se unió a otra y no se puede reactivar. Seguí usando la otra.'),
        findsOneWidget,
      );
      expect(await guardada(tester, 'baja-1'), antes);
      expect(encolador.encolados, isEmpty);
      await tocar(tester, find.text('Abrir la existente'));
      expect(abiertas, ['ub-a']);
    });

    prueba('dado que el sync cambió la casa mientras la hoja estaba abierta, entonces «Reactivar» '
        'dice «cambió recién», no escribe, y al cerrar y volver a abrir la hoja sí reactiva', (
      tester,
    ) async {
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await motivo('baja-1', _el12, 'Ya no existe');
      });
      await montar(tester);
      await tocar(tester, baja1240());
      await tester.runAsync(() async {
        await (db.update(db.ubicaciones)..where((t) => t.id.equals('baja-1'))).write(
          UbicacionesCompanion(updatedAt: Value(_t0.add(const Duration(hours: 1)))),
        );
      });

      await tocar(tester, botonReactivar());
      expect(
        find.text('Esta ubicación cambió recién. Abrila de nuevo y volvé a reactivarla.'),
        findsOneWidget,
      );
      expect((await guardada(tester, 'baja-1')).auditoria.deletedAt, isNotNull);

      // Reintentar sin volver a abrir: la hoja sigue con la versión vieja y no puede salir bien.
      await tocar(tester, botonReactivar());
      expect(
        find.text('Esta ubicación cambió recién. Abrila de nuevo y volvé a reactivarla.'),
        findsOneWidget,
        reason: 'el mensaje manda a abrirla de nuevo: reintentar con lo mismo vuelve a fallar',
      );
      expect((await guardada(tester, 'baja-1')).auditoria.deletedAt, isNotNull);

      await tocar(tester, find.widgetWithText(TextButton, TextosReactivar.cancelar));
      await tocar(tester, baja1240());
      await tocar(tester, botonReactivar());

      expect((await guardada(tester, 'baja-1')).auditoria.deletedAt, isNull);
    });

    prueba('dado una reactivación rechazada, entonces el log no lleva la dirección ni el motivo '
        '(solo códigos y uuid)', (tester) async {
      await armar(tester, () async {
        await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
        await motivo('baja-1', _el12, 'Se mudó doña Estela');
        await local.insertar(
          ubicacion('viva', calle: 'Av. Italia', numero: '1240', metrosAlNorte: 30),
        );
      });
      await montar(tester, alAbrir: (_, _) {});
      await tocar(tester, bajaDeItalia());

      await tocar(tester, botonReactivar());

      expect(find.text('No se puede reactivar'), findsOneWidget);
      final log = salida.lineas.join('\n');
      expect(log, contains('UBICACION_REACTIVAR_MISMA_DIRECCION'));
      expect(log, isNot(contains('Italia')));
      expect(log, isNot(contains('1240')));
      expect(log, isNot(contains('doña Estela')));
    });
  });
}

String _diaMes(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

/// Deja avanzar la base real (que no avanza con el reloj falso) y los cuadros de la pantalla.
Future<void> _esperarBase(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}
