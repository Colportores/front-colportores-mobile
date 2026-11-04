// QA de la vista 09 «Dar de baja y reactivar» con los adaptadores reales (HU-UBI-005, #330, PR #646): la
// hoja y la Lista reales sobre la base REAL (Drift en memoria) con `PendientesUbicacionDrift`,
// `UltimaVisitaDeLaUbicacionDrift` y el caso de uso. Los tests del PR prueban la hoja con un consultor
// falso y los adaptadores sin pantalla; estos prueban que una persona, tocando, ve lo que la HU promete
// y que del teléfono no se pierde nada. Más: la matriz de tamaños × texto 1,0/2,0 con las fuentes reales
// y las guías de accesibilidad de los estados que trae #330 (09·02 sin plan de cuotas con «Ir a la
// cobranza», la segunda confirmación de las entrevistas y el renglón «Última visita» de 09·03).
//
// Capturas (nunca se commitean): `--dart-define=QA_CAPTURAS=true` las deja en `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ultima_visita_de_la_ubicacion_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/data/services/pendientes_ubicacion_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/campo_falsos.dart' hide t0;
import '../../helpers/duplicados_falsos.dart' show EncoladorMarcarDuplicadoFalso;
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_reactivar_334_arnes.dart';
import '../../helpers/venta_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

const _capturas = bool.fromEnvironment('QA_CAPTURAS');

final _t0 = DateTime.utc(2026, 10, 23, 13, 45, 10, 123);
final _hoy = DateTime.utc(2026, 11, 4, 18);
final _el12 = DateTime.utc(2026, 9, 12, 15);

/// Un consultor que falla las primeras [fallas] veces y después lee la base real.
final class _ConsultorQueFallaYSeRecupera implements ConsultorPendientesUbicacion {
  _ConsultorQueFallaYSeRecupera(this._real, this.fallas);

  final ConsultorPendientesUbicacion _real;
  int fallas;
  int llamadas = 0;

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) {
    llamadas++;
    if (fallas > 0) {
      fallas--;
      return Future.value(const Left(FailurePendientesNoDisponibles()));
    }
    return _real.de(ubicacionId);
  }
}

/// La pantalla que abre la hoja y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.ubicacion, required this.salidas});

  final Ubicacion ubicacion;
  final List<SalidaHojaBaja?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async => salidas.add(await mostrarHojaBaja(context, ubicacion: ubicacion)),
        child: const Text('abrir'),
      ),
    ),
  );
}

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late HouseStatusUpdaterDrift casas;
  late UbicacionLocalDataSourceDrift local;
  late UbicacionRepositoryImpl repositorio;
  late RecordatoriosEnMemoria recordatorios;
  late PendientesUbicacionDrift pendientes;

  UbicacionModel ubicacion(
    String id, {
    TipoUbicacion tipo = TipoUbicacion.casa,
    String calle = 'Av. Italia',
    String numero = '1234',
    double metrosAlNorte = 0,
    DateTime? baja,
  }) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: puntoItalia.lat + metrosAlNorte / 111195.08,
    lon: puntoItalia.lon,
    ciudadId: 'ciu-mvd',
    auditoria: Auditoria(
      createdAt: _t0,
      updatedAt: _t0,
      createdBy: 'col-1',
      deletedAt: baja,
      syncVersion: 3,
    ),
  );

  /// Arma el teléfono: `[inserciones]` corre dentro de `runAsync` (la base real no avanza con el reloj
  /// falso del test).
  Future<void> armar(WidgetTester tester, Future<void> Function() inserciones) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
      estadoDeLasCasas: casas,
    );
    repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
    recordatorios = RecordatoriosEnMemoria();
    pendientes = PendientesUbicacionDrift(
      db,
      cuotas: CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas),
      colportorId: 'col-1',
      logger: loggerMudo(),
    );
    await tester.runAsync(() async {
      await inserciones();
      encolador.encolados.clear();
    });
  }

  /// Cierra el teléfono: desmonta la pantalla (Drift deja un timer al cancelar el stream) y cierra la base.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      await cuerpo(tester);
      await cerrar(tester);
    });
  }

  Future<void> casaConEntrevistas(WidgetTester tester, {int entrevistas = 1}) =>
      armar(tester, () async {
        await local.insertar(ubicacion('ub-1'));
        await sembrarEspacio(db);
        await sembrarVinculo(db);
        for (var i = 1; i <= entrevistas; i++) {
          await insertarAgenda(db, agendaDe('ag-$i'));
        }
        await casas.recalcular('ub-1', ahora: _t0, colportorId: 'col-1');
      });

  Future<void> casaConVentaSinPlan(WidgetTester tester) => armar(tester, () async {
    await local.insertar(ubicacion('ub-1'));
    await sembrarEspacio(db);
    await sembrarVinculo(db);
    await VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    ).registrar(ventaDe('v-1', monto: 145000), [itemDe('i-1', 'v-1', cantidad: 1, precio: 145000)]);
  });

  /// Monta la hoja de baja real sobre la base real y la abre.
  Future<List<SalidaHojaBaja?>> abrirHoja(
    WidgetTester tester, {
    Size tamano = t390x844,
    double escala = 1,
    ConsultorPendientesUbicacion? consultor,
    FutureOr<Object?> Function(CobranzaPendiente)? destino,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final u = (await tester.runAsync(() => local.obtener('ub-1')))!;
    final salidas = <SalidaHojaBaja?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ubicacionRepositoryProvider.overrideWithValue(repositorio),
          relojAltaUbicacionProvider.overrideWithValue(() => _hoy),
          consultorPendientesUbicacionProvider.overrideWithValue(consultor ?? pendientes),
          recordatoriosProvider.overrideWithValue(recordatorios),
          if (destino != null) irALaCobranzaDesdeLaBajaProvider.overrideWithValue(destino),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => RepaintBoundary(
            key: raizCaptura334,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
              child: child!,
            ),
          ),
          home: _Anfitrion(ubicacion: u, salidas: salidas),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await _asentar(tester);
    return salidas;
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await _asentar(tester);
  }

  Finder enElDialogo(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);
  Finder botonDarDeBaja() => find.widgetWithText(FilledButton, TextosBaja.darDeBaja);

  Future<String> estadoDeAgenda(WidgetTester tester, String id) async => (await tester.runAsync(
    () => (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle(),
  ))!.estado;

  Future<UbicacionModel> guardada(WidgetTester tester) async =>
      (await tester.runAsync(() => local.obtener('ub-1')))!;

  group('QA #330 · 09·01 la segunda confirmación de las entrevistas, con la base real', () {
    prueba('dado una entrevista agendada de verdad en el teléfono, cuando da de baja, entonces el '
        'aviso dice el literal de la HU y todavía no se escribe nada', (tester) async {
      await casaConEntrevistas(tester);
      await abrirHoja(tester);

      await tocar(tester, find.text('Ya no existe'));
      await tocar(tester, botonDarDeBaja());

      expect(
        find.text('Esta casa tiene 1 entrevista agendada. Si la das de baja, se cancela.'),
        findsOneWidget,
      );
      expect((await guardada(tester)).auditoria.deletedAt, isNull);
      expect(await estadoDeAgenda(tester, 'ag-1'), EstadoAgenda.programada.codigo);
      expect(encolador.encolados, isEmpty);
    });

    prueba('dado el aviso, cuando confirma, entonces la casa queda de baja, la entrevista queda '
        'CANCELADA (no borrada), se encola una vez y su recordatorio se cancela', (tester) async {
      await casaConEntrevistas(tester, entrevistas: 2);
      final salidas = await abrirHoja(tester);

      await tocar(tester, find.text('Está deshabitada'));
      await tocar(tester, botonDarDeBaja());
      expect(
        find.text('Esta casa tiene 2 entrevistas agendadas. Si la das de baja, se cancelan.'),
        findsOneWidget,
      );
      await tocar(tester, enElDialogo(find.text('Dar de baja')));

      expect(salidas.single, isA<BajaRealizada>());
      expect((await guardada(tester)).auditoria.deletedAt, _hoy);
      expect(await estadoDeAgenda(tester, 'ag-1'), 'CANCELADA');
      expect(await estadoDeAgenda(tester, 'ag-2'), 'CANCELADA');
      final borradas = await tester.runAsync(
        () => (db.select(db.agendas)..where((a) => a.deletedAt.isNotNull())).get(),
      );
      expect(borradas, isEmpty, reason: 'no se borra nada');
      expect(
        [
          for (final c in encolador.encolados)
            if (c.entidad == 'agenda') c.payload['id'],
        ]..sort(),
        ['ag-1', 'ag-2'],
      );
      expect(encolador.encolados.where((c) => c.entidad == 'ubicacion'), hasLength(1));
      expect(recordatorios.llamadas.where((l) => l.startsWith('cancelar:')), hasLength(2));
    });

    prueba('dado el aviso, cuando cancela, entonces no se escribe nada y puede elegir otro motivo '
        'y confirmar después', (tester) async {
      await casaConEntrevistas(tester);
      final salidas = await abrirHoja(tester);
      await tocar(tester, find.text('No quiere visitas'));
      await tocar(tester, botonDarDeBaja());

      await tocar(tester, enElDialogo(find.text('Cancelar')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(salidas, isEmpty);
      expect(await estadoDeAgenda(tester, 'ag-1'), EstadoAgenda.programada.codigo);
      expect(encolador.encolados, isEmpty);

      await tocar(tester, find.text('Otro'));
      await tester.enterText(find.byType(TextField), 'Se mudó 🏠');
      await tocar(tester, botonDarDeBaja());
      await tocar(tester, enElDialogo(find.text('Dar de baja')));

      expect(salidas.single, isA<BajaRealizada>());
      final audit = await tester.runAsync(() => db.select(db.auditLogLocal).get());
      expect(audit!.single.evento, EventoAuditoriaLocal.ubicacionBaja);
      expect(audit.single.motivo, 'Se mudó 🏠');
    });

    prueba('dado que la lectura de lo pendiente falla una vez, cuando toca «Reintentar», entonces '
        'se recupera y llega al motivo sin perder la hoja', (tester) async {
      await casaConEntrevistas(tester);
      final consultor = _ConsultorQueFallaYSeRecupera(pendientes, 1);
      await abrirHoja(tester, consultor: consultor);

      expect(find.text(TextosBaja.noPudimosRevisar), findsOneWidget);
      expect(find.text(TextosBaja.reintentar), findsOneWidget);
      expect(botonDarDeBaja(), findsNothing, reason: 'ante la duda se bloquea');
      expect((await guardada(tester)).auditoria.deletedAt, isNull);

      await tocar(tester, find.text(TextosBaja.reintentar));

      expect(find.text(TextosBaja.noPudimosRevisar), findsNothing);
      expect(find.text('Ya no existe'), findsOneWidget);
      expect(consultor.llamadas, 2);
    });
  });

  group('QA #330 · 09·02 bloqueos con la base real', () {
    prueba('dado una venta con saldo y sin plan de cuotas, entonces el aviso dice solo el monto, '
        'sin «N.ª cuota», y no hay motivos ni «Dar de baja»', (tester) async {
      await casaConVentaSinPlan(tester);
      await abrirHoja(tester);

      expect(find.text(TextosBaja.bloqueadaTitulo), findsOneWidget);
      expect(
        find.text(
          r'Tiene una cobranza pendiente de $U 1.450. Registrá el cobro antes de darla de baja.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('cuota'), findsNothing);
      expect(botonDarDeBaja(), findsNothing);
      expect(find.text('Entendido'), findsOneWidget);
      expect((await guardada(tester)).auditoria.deletedAt, isNull);
    });

    prueba('dado la misma venta y una app con destino, cuando toca «Ir a la cobranza», entonces el '
        'destino recibe la venta, la casa y el vínculo de VERDAD y no se escribe nada', (
      tester,
    ) async {
      await casaConVentaSinPlan(tester);
      final recibidas = <CobranzaPendiente>[];
      final salidas = await abrirHoja(
        tester,
        destino: (c) {
          recibidas.add(c);
          return true;
        },
      );

      expect(find.text('Entendido'), findsNothing);
      await tocar(tester, find.text(TextosBaja.irALaCobranza));

      final salida = salidas.single! as IrALaCobranzaElegido;
      expect(salida.ubicacionId, 'ub-1');
      expect(salida.cobranza?.ventaId, 'v-1');
      expect(salida.cobranza?.espacioId, 'esp-1');
      expect(salida.cobranza?.espacioPersonaId, 'ep-1');
      expect(salida.cobranza?.montoCentavos, 145000);
      expect(
        recibidas,
        isEmpty,
        reason: 'la hoja solo devuelve la salida; la pantalla abre el cobro',
      );
      expect((await guardada(tester)).auditoria.deletedAt, isNull);
      expect(encolador.encolados, isEmpty);
    });

    prueba('dado una visita de otro colportor en la casa, entonces el aviso es el literal de la HU '
        'y la baja no se ofrece', (tester) async {
      await armar(tester, () async {
        await local.insertar(ubicacion('ub-1'));
        await sembrarEspacio(db);
        await sembrarVinculo(db);
        await db
            .into(db.visitas)
            .insert(
              VisitasCompanion.insert(
                id: 'vis-9',
                espacioId: 'esp-1',
                fecha: _t0,
                tipoResultado: TipoResultadoVisita.noContesto.codigo,
                colportorId: 'col-otro',
                createdAt: _t0,
                updatedAt: _t0,
              ),
            );
      });
      await abrirHoja(tester);

      expect(
        find.text(
          'No podés dar de baja esta casa porque tiene ventas o visitas de otro colportor. '
          'Si ya no existe, avisale a tu coordinador.',
        ),
        findsOneWidget,
      );
      expect(botonDarDeBaja(), findsNothing);
    });
  });

  group('QA #330 · 09·03 el renglón «Última visita» con las visitas reales', () {
    Future<void> montarLista(
      WidgetTester tester, {
      Size tamano = t390x844,
      double escala = 1,
    }) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ubicacionRepositoryProvider.overrideWithValue(repositorio),
            lectorUltimaVisitaDeLaUbicacionProvider.overrideWithValue(
              UltimaVisitaDeLaUbicacionDrift(db),
            ),
            ...overridesLista(repo: RepoListaFalso()).skip(1),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => RepaintBoundary(
              key: raizCaptura334,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(alwaysUse24HourFormat: true, textScaler: TextScaler.linear(escala)),
                child: child!,
              ),
            ),
            home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1', activa: true)),
          ),
        ),
      );
      await _asentar(tester);
      await abrirHojaFiltros(tester);
      await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
      await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
      await _asentar(tester);
      await tester.ensureVisible(botonVerUbicaciones);
      await tester.tap(botonVerUbicaciones);
      await _asentar(tester);
    }

    Future<void> bajaConVisitas(
      List<
        ({String id, String espacio, DateTime fecha, TipoResultadoVisita res, DateTime? borrada})
      >
      visitas,
    ) async {
      await local.insertar(ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12));
      await db
          .into(db.auditLogLocal)
          .insert(
            AuditLogLocalCompanion.insert(
              evento: EventoAuditoriaLocal.ubicacionBaja,
              uuid: 'baja-1',
              motivo: const Value('Ya no existe'),
              creadoEn: _el12,
            ),
          );
      await sembrarEspacio(db, id: 'esp-b1', ubicacionId: 'baja-1');
      await sembrarEspacio(db, id: 'esp-b2', ubicacionId: 'baja-1', numeroDepto: '2B');
      for (final v in visitas) {
        await db
            .into(db.visitas)
            .insert(
              VisitasCompanion.insert(
                id: v.id,
                espacioId: v.espacio,
                fecha: v.fecha,
                tipoResultado: v.res.codigo,
                colportorId: 'col-1',
                createdAt: v.fecha,
                updatedAt: v.fecha,
                deletedAt: Value(v.borrada),
              ),
            );
      }
    }

    prueba('dado visitas en dos espacios de la baja (una más nueva dada de baja), cuando abre '
        '«Reactivar», entonces «Última visita» es la más reciente que sigue viva, de cualquier '
        'espacio', (tester) async {
      await armar(
        tester,
        () => bajaConVisitas([
          (
            id: 'v-1',
            espacio: 'esp-b1',
            fecha: DateTime.utc(2026, 8, 20, 15),
            res: TipoResultadoVisita.rechazo,
            borrada: null,
          ),
          (
            id: 'v-2',
            espacio: 'esp-b2',
            fecha: DateTime.utc(2026, 9, 2, 15),
            res: TipoResultadoVisita.noContesto,
            borrada: null,
          ),
          (
            id: 'v-3',
            espacio: 'esp-b1',
            fecha: DateTime.utc(2026, 9, 10, 15),
            res: TipoResultadoVisita.entrevista,
            borrada: DateTime.utc(2026, 9, 11),
          ),
        ]),
      );
      await cargarFuentes205(tester);
      await montarLista(tester);

      await tocar(tester, find.text('Av. Italia 1240'));

      expect(find.byType(HojaReactivarUbicacion), findsOneWidget);
      expect(find.text(TextosReactivar.ultimaVisita), findsOneWidget);
      expect(find.text('No contestó · 02/09'), findsOneWidget);
      expect(find.text('Ya no existe'), findsWidgets);
      if (_capturas) await capturar334(tester, 'hoja_reactivar_ultima_visita_390x844');
    });

    prueba('dado una baja sin visitas, cuando abre «Reactivar», entonces no dibuja «Última visita» '
        'ni inventa una y «Reactivar» funciona', (tester) async {
      await armar(tester, () => bajaConVisitas(const []));
      await montarLista(tester);

      await tocar(tester, find.text('Av. Italia 1240'));

      expect(find.byType(HojaReactivarUbicacion), findsOneWidget);
      expect(find.text(TextosReactivar.ultimaVisita), findsNothing);
      expect(find.widgetWithText(FilledButton, TextosReactivar.reactivar), findsOneWidget);
    });

    prueba(
      'dado que la tabla de visitas no se puede leer, cuando abre «Reactivar», entonces la hoja '
      'abre igual sin el renglón (nunca se inventa) y se puede reactivar',
      (tester) async {
        await armar(tester, () => bajaConVisitas(const []));
        await tester.runAsync(() => db.customStatement('DROP TABLE visita'));
        await montarLista(tester);

        await tocar(tester, find.text('Av. Italia 1240'));

        expect(find.byType(HojaReactivarUbicacion), findsOneWidget);
        expect(find.text(TextosReactivar.ultimaVisita), findsNothing);
        await tocar(tester, find.widgetWithText(FilledButton, TextosReactivar.reactivar));
        final u = await tester.runAsync(() => local.obtener('baja-1'));
        expect(u!.auditoria.deletedAt, isNull);
      },
    );
  });

  group('QA #330 · decisiones del 04/11 (P1, P2 y P4)', () {
    // QA #330 — P1 (04/11): el motivo se busca por el último `ubicacion_baja`, no por igualdad
    // exacta con `deleted_at`; hoy una baja con `creado_en` distinto de `deleted_at` pierde el motivo.
    testWidgets(
      'P1 · dado una baja cuyo evento de auditoría lleva otro instante que deleted_at, entonces la '
      'fila sigue diciendo el motivo',
      (tester) async {
        await armar(tester, () async {
          await local.insertar(
            ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12),
          );
          await db
              .into(db.auditLogLocal)
              .insert(
                AuditLogLocalCompanion.insert(
                  evento: EventoAuditoriaLocal.ubicacionBaja,
                  uuid: 'baja-1',
                  motivo: const Value('Ya no existe'),
                  creadoEn: _el12.add(const Duration(seconds: 7)),
                ),
              );
        });
        tester.view.physicalSize = t390x844;
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
              home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1', activa: true)),
            ),
          ),
        );
        await _asentar(tester);
        await abrirHojaFiltros(tester);
        await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
        await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
        await _asentar(tester);
        await tester.ensureVisible(botonVerUbicaciones);
        await tester.tap(botonVerUbicaciones);
        await _asentar(tester);

        expect(find.text('Casa · baja el 12/09 · Ya no existe'), findsOneWidget);
        await cerrar(tester);
      },
    );

    // QA #330 — P2 (04/11): «Este edificio tiene…» / «Este negocio tiene…»; hoy dice «Esta casa».
    for (final (tipo, sujeto, texto) in [
      (
        TipoUbicacion.edificio,
        'Este edificio',
        'Este edificio tiene 2 entrevistas agendadas. Si la das de baja, se cancelan.',
      ),
      (
        TipoUbicacion.negocio,
        'Este negocio',
        'Este negocio tiene 1 entrevista agendada. Si la das de baja, se cancela.',
      ),
    ]) {
      testWidgets(
        'P2 · dado $sujeto con entrevistas agendadas, cuando da de baja, entonces el aviso dice '
        '«$sujeto tiene…»',
        (tester) async {
          await armar(tester, () async {
            await local.insertar(ubicacion('ub-1', tipo: tipo));
            await sembrarEspacio(db, numeroDepto: tipo == TipoUbicacion.edificio ? '1A' : null);
            await sembrarVinculo(db);
            await insertarAgenda(db, agendaDe('ag-1'));
            if (tipo == TipoUbicacion.edificio) {
              await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
              await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
              await insertarAgenda(db, agendaDe('ag-2', espacio: 'esp-2', vinculo: 'ep-2'));
            }
          });
          await abrirHoja(tester);
          await tocar(tester, find.text('Ya no existe'));
          await tocar(tester, botonDarDeBaja());

          expect(find.text(texto), findsOneWidget);
          await cerrar(tester);
        },
      );
    }

    // QA #330 — P4 (04/11): con 2 o más ventas con saldo el aviso dice cuántas son y muestra la más
    // antigua; hoy muestra solo la más antigua como si fuera la única.
    testWidgets(
      'P4 · dado dos ventas con saldo, cuando abre la hoja de baja, entonces el aviso dice cuántas '
      'cobranzas hay y cuál es la más antigua',
      (tester) async {
        await armar(tester, () async {
          await local.insertar(ubicacion('ub-1'));
          await sembrarEspacio(db);
          await sembrarVinculo(db);
          final ventas = VentaLocalDataSourceDrift(
            db,
            encolador: encolador,
            estadoDeLasCasas: casas,
          );
          await ventas.registrar(
            ventaDe('v-1', monto: 145000, fecha: DateTime.utc(2026, 10, 1, 12)),
            [itemDe('i-1', 'v-1', cantidad: 1, precio: 145000)],
          );
          await ventas.registrar(
            ventaDe('v-2', talonario: 'T-101', monto: 200000, fecha: DateTime.utc(2026, 10, 5, 12)),
            [itemDe('i-2', 'v-2', cantidad: 1, precio: 200000)],
          );
        });
        await abrirHoja(tester);

        expect(find.textContaining('2 cobranzas pendientes'), findsOneWidget);
        expect(find.textContaining('La más antigua'), findsOneWidget);
        expect(find.textContaining(r'$U 1.450'), findsOneWidget);
        await cerrar(tester);
      },
    );
  });

  group('QA #330 · 09·03 «Reactivar» con «Última visita»: tamaños, texto a 200 % y guías', () {
    for (final (tamano, escala) in matriz334) {
      if (tamano.width < 360) continue;
      final sufijo = sufijo334(tamano, escala);
      testWidgets('09·03 en $sufijo', (tester) async {
        await armar(tester, () async {
          await local.insertar(
            ubicacion('baja-1', calle: 'Av. Italia', numero: '1240', baja: _el12),
          );
          await db
              .into(db.auditLogLocal)
              .insert(
                AuditLogLocalCompanion.insert(
                  evento: EventoAuditoriaLocal.ubicacionBaja,
                  uuid: 'baja-1',
                  motivo: const Value('Ya no existe'),
                  creadoEn: _el12,
                ),
              );
          await sembrarEspacio(db, id: 'esp-b1', ubicacionId: 'baja-1');
          await db
              .into(db.visitas)
              .insert(
                VisitasCompanion.insert(
                  id: 'v-2',
                  espacioId: 'esp-b1',
                  fecha: DateTime.utc(2026, 9, 2, 15),
                  tipoResultado: TipoResultadoVisita.noContesto.codigo,
                  colportorId: 'col-1',
                  createdAt: _t0,
                  updatedAt: _t0,
                ),
              );
        });
        await cargarFuentes205(tester);
        final h = tester.ensureSemantics();
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ubicacionRepositoryProvider.overrideWithValue(repositorio),
              lectorUltimaVisitaDeLaUbicacionProvider.overrideWithValue(
                UltimaVisitaDeLaUbicacionDrift(db),
              ),
              ...overridesLista(repo: RepoListaFalso()).skip(1),
            ],
            child: MaterialApp(
              theme: temaClaro(),
              builder: (context, child) => RepaintBoundary(
                key: raizCaptura334,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                  child: child!,
                ),
              ),
              home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1', activa: true)),
            ),
          ),
        );
        await _asentar(tester);
        await abrirHojaFiltros(tester);
        await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
        await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
        await _asentar(tester);
        await tester.ensureVisible(botonVerUbicaciones);
        await tester.tap(botonVerUbicaciones);
        await _asentar(tester);
        await tocar(tester, find.text('Av. Italia 1240'));

        expect(find.text('No contestó · 02/09'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectSinTextoFueraDeLosCostados205(tester, tamano);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        if (_capturas) await capturar334(tester, '09_03_ultima_visita_$sufijo');
        h.dispose();
        await cerrar(tester);
      });
    }
  });

  group('QA #330 · tamaños, texto a 200 % y guías de accesibilidad', () {
    for (final (tamano, escala) in matriz334) {
      if (tamano.width < 360) continue;
      final sufijo = sufijo334(tamano, escala);

      testWidgets('09·02 sin plan de cuotas con «Ir a la cobranza» en $sufijo', (tester) async {
        await casaConVentaSinPlan(tester);
        await cargarFuentes205(tester);
        final h = tester.ensureSemantics();
        await abrirHoja(tester, tamano: tamano, escala: escala, destino: (_) => true);

        expect(find.text(TextosBaja.irALaCobranza), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectSinTextoFueraDeLosCostados205(tester, tamano);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        if (_capturas) await capturar334(tester, '09_02_sin_plan_$sufijo');
        h.dispose();
        await cerrar(tester);
      });

      testWidgets('09·01 segunda confirmación de las entrevistas en $sufijo', (tester) async {
        await casaConEntrevistas(tester, entrevistas: 2);
        await cargarFuentes205(tester);
        final h = tester.ensureSemantics();
        await abrirHoja(tester, tamano: tamano, escala: escala);
        await tocar(tester, find.text('Ya no existe'));
        await tocar(tester, botonDarDeBaja());

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectSinTextoFueraDeLosCostados205(tester, tamano);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        if (_capturas) await capturar334(tester, '09_01_entrevistas_$sufijo');
        h.dispose();
        await cerrar(tester);
      });
    }
  });
}
