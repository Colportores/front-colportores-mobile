// La hoja de la casa con deptos (vista 39, #452): el edificio y sus deptos (C·09), el depto como una
// casa (C·10), el edificio recién registrado sumando deptos (N·04) y eligiendo uno (N·06 → N·07), el
// negocio como un edificio (decisión de Cristian, 09/11) y sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/espacios_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/persona_falsos.dart';

/// El edificio del canvas (C·09): «Grecia 3313».
const _ubicacionId = 'ubi-1';

/// Los deptos del canvas (C·09), desordenados: la hoja los ordena por piso.
final _d4A = espacioDe('d-4a', '4A', piso: '4', orden: 1);
final _d1A = espacioDe('d-1a', '1A', piso: '1', orden: 2);
final _d3B = espacioDe('d-3b', '3B', piso: '3', orden: 3);
final _d2A = espacioDe('d-2a', '2A', piso: '2', orden: 4);

/// «Ahora» de la hoja: el de la gestión de espacios (23/10 15:00 UTC).
final _ahora = hoyEspacios;

/// El resumen de los deptos del canvas: 1A no contestó ayer, 2A tiene una entrevista, 3B debe y 4A
/// está sin visita.
final _resumenDelCanvas = {
  'd-1a': ResumenDelDepto(
    estado: EstadoCasa.noContesto,
    ultimaVisita: _ahora.subtract(const Duration(days: 1)),
  ),
  'd-2a': ResumenDelDepto(
    estado: EstadoCasa.entrevistaAgendada,
    proximaEntrevista: _ahora.add(const Duration(days: 1)),
  ),
  'd-3b': ResumenDelDepto(estado: EstadoCasa.cobranzaPendiente),
  'd-4a': ResumenDelDepto(),
};

/// María Fernández, que vive en el 3B y debe $ 1.200 (C·10).
final PersonaDelEspacio _maria = clienteDePersonas('p-maria', 'María', apellido: 'Fernández');

final class _Montaje {
  _Montaje(this.repo);

  final EspacioRepoFalso repo;
  final lecturas = <ClaveDeLaCasa>[];
  final visitas = <ContextoDeVisita>[];
  var cierres = 0;

  /// Lo que contesta «Registrar visita» (por defecto, `false`: se cerró «¿Qué pasó?» sin elegir).
  Object? salidaVisita = false;

  /// Si no es `null`, «Registrar visita» espera a que se complete.
  Completer<Object?>? esperaVisita;

  /// Si no es `null`, «Registrar visita» lanza esto.
  Object? lanzaVisita;

  /// El resumen de los deptos que lee la hoja (un `Stream` por lectura).
  Stream<Map<String, ResumenDelDepto>> Function() resumen = () => Stream.value(_resumenDelCanvas);

  final atras = ValueNotifier<VoidCallback?>(null);

  /// Si es `true`, el contexto de un depto no se puede leer.
  var contextoDelDeptoFalla = false;
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  TipoUbicacion tipo = TipoUbicacion.edificio,
  List<Espacio>? espacios,
  bool recien = false,
  bool arriba = false,
  bool conRegistrar = true,
  bool conAtras = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  double? metros = 35,
  DateTime? baja,
  void Function(_Montaje m)? antes,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ubicacion = ubicacionGuardada(
    id: _ubicacionId,
    tipo: tipo,
    calle: 'Grecia',
    numero: '3313',
    deBajaDesde: baja,
  );
  final m = _Montaje(EspacioRepoFalso(ubicacion, espacios: espacios ?? [_d4A, _d1A, _d3B, _d2A]));
  antes?.call(m);
  addTearDown(m.atras.dispose);
  var secuencia = 0;
  final item = ItemListaUbicacion(
    ubicacion: ubicacion,
    estado: EstadoCasa.cobranzaPendiente,
    distanciaMetros: metros,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaFalsa()),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        contextoDeLaCasaProvider.overrideWith((ref, clave) {
          m.lecturas.add(clave);
          final espacioId = clave.espacioId;
          if (m.contextoDelDeptoFalla && espacioId != null) {
            return Stream<ContextoDeLaCasa>.error(const FailureDatosLocalesIlegibles());
          }
          return Stream.value(
            espacioId == null
                ? const ContextoDeLaCasa()
                : ContextoDeLaCasa(
                    espacioId: espacioId,
                    personas: espacioId == 'd-3b' ? [_maria] : const [],
                    saldosCentavos: const {'p-maria': 120000},
                  ),
          );
        }),
        registrarVisitaDesdeLaCasaProvider.overrideWithValue(
          conRegistrar
              ? (contexto) async {
                  m.visitas.add(contexto);
                  final lanza = m.lanzaVisita;
                  if (lanza != null) throw lanza;
                  final espera = m.esperaVisita;
                  if (espera != null) return espera.future;
                  return m.salidaVisita;
                }
              : null,
        ),
        espacioRepositoryProvider.overrideWithValue(m.repo),
        ubicacionRepositoryProvider.overrideWithValue(RepoEdicionFalso(ubicacion)),
        contadorPersonasEspacioProvider.overrideWithValue(ContadorPersonasFalso()),
        generadorIdEspacioProvider.overrideWithValue(() => 'nuevo-${++secuencia}'),
        relojEspaciosProvider.overrideWithValue(() => _ahora),
        resumenDeLosDeptosProvider.overrideWith((ref, clave) => m.resumen()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: HojaCasa(
            item: item,
            ahora: _ahora,
            alCerrar: () => m.cierres++,
            colportorId: 'col-1',
            arriba: arriba,
            recienRegistrada: recien,
            atras: conAtras ? m.atras : null,
          ),
        ),
      ),
    ),
  );
  await _asentar(tester);
  return m;
}

Future<void> _asentar(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

String _texto(WidgetTester tester, Key clave) => tester.widget<Text>(find.byKey(clave)).data!;

Finder _fila(Espacio e) => find.byKey(ClavesDeptosDeLaCasa.fila(e.id));
final _subtitulo = find.byKey(ClavesHojaCasa.subtitulo);
final _registrar = find.byKey(ClavesHojaCasa.registrarVisita);
final _agregar = find.byKey(ClavesDeptosDeLaCasa.agregar);
final _volver = find.byKey(ClavesDeptosDeLaCasa.volver);

/// El texto que el lector de pantalla dice de la fila de [e].
String _lecturaDe(WidgetTester tester, Espacio e) => tester.getSemantics(_fila(e)).label;

void main() {
  group('C·09 «Edificio: sus deptos»', () {
    testWidgets('dado un edificio, la hoja muestra sus deptos por piso, con su estado y cuándo, y '
        '«+ Agregar depto»; no muestra «Registrar visita» ni lee una casa sin depto', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = await _montar(tester);

      expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313');
      expect(_texto(tester, ClavesHojaCasa.subtitulo), 'Edificio · 4 deptos · a 35\u00A0m de vos');
      expect(_texto(tester, ClavesDeptosDeLaCasa.rotulo), '4 DEPTOS');
      expect(find.text('+ Agregar depto'), findsOneWidget);
      final ys = [
        for (final e in [_d1A, _d2A, _d3B, _d4A]) tester.getTopLeft(_fila(e)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'del piso 1 al 4');
      expect(_lecturaDe(tester, _d1A), 'Depto 1A. No contestó · ayer');
      expect(_lecturaDe(tester, _d2A), startsWith('Depto 2A. Entrevista agendada · '));
      expect(_lecturaDe(tester, _d3B), 'Depto 3B. Cobranza pendiente');
      expect(_lecturaDe(tester, _d4A), 'Depto 4A. Sin visita');
      expect(_registrar, findsNothing);
      expect(m.lecturas, isEmpty, reason: 'sin depto elegido no hay contexto de casa que leer');
      semantica.dispose();
    });

    testWidgets('sin el resumen de los deptos (falla), las filas no afirman ningún estado', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, antes: (m) => m.resumen = () => Stream.error(StateError('sin DB')));

      expect(_lecturaDe(tester, _d1A), 'Depto 1A. Piso 1');
      expect(find.text('No contestó · ayer'), findsNothing);
      semantica.dispose();
    });

    testWidgets('sin deptos, lo dice y qué hacer', (tester) async {
      await _montar(tester, espacios: const []);

      expect(_texto(tester, ClavesDeptosDeLaCasa.rotulo), '0 DEPTOS');
      expect(find.text(TextosDeptosDeLaCasa.sinDeptos), findsOneWidget);
      expect(find.text(TextosDeptosDeLaCasa.sinDeptosQueHacer), findsOneWidget);
      expect(_agregar, findsOneWidget);
    });

    testWidgets(
      'mientras lee, el esqueleto (E·01); si falla, el aviso con «Reintentar» (E·02), y al '
      'reintentar se ven los deptos',
      (tester) async {
        final espera = Completer<void>();
        final m = await _montar(tester, antes: (m) => m.repo.esperaAlListar = espera);

        expect(find.byKey(ClavesDeptosDeLaCasa.lista), findsNothing);
        expect(_subtitulo, findsNothing);

        m.repo.fallaAlListar = const FailureInesperado(causa: 'sin DB');
        espera.complete();
        await _asentar(tester);
        expect(find.byKey(ClavesDeptosDeLaCasa.error), findsOneWidget);
        expect(find.text(TextosDeptosDeLaCasa.errorLectura), findsOneWidget);

        m.repo.fallaAlListar = null;
        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.reintentar));
        await _asentar(tester);
        expect(find.byKey(ClavesDeptosDeLaCasa.error), findsNothing);
        expect(_fila(_d1A), findsOneWidget);
      },
    );

    testWidgets(
      'dado de baja (E·04): el aviso, sin «+ Agregar depto», y el depto se abre solo para '
      'ver (sin «Registrar visita»)',
      (tester) async {
        await _montar(tester, baja: DateTime.utc(2026, 10, 18, 12));

        expect(find.byKey(ClavesEstadosHojaCasa.avisoDadaDeBaja), findsOneWidget);
        expect(_agregar, findsNothing);

        await tester.tap(_fila(_d3B));
        await _asentar(tester);
        expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 3B');
        expect(_registrar, findsNothing);
      },
    );

    testWidgets('una lista larga se desplaza hasta el último depto', (tester) async {
      final muchos = [
        for (var i = 1; i <= 24; i++) espacioDe('d-$i', '${i}A', piso: '$i', orden: i),
      ];
      await _montar(tester, espacios: muchos, tamano: const Size(360, 640));

      final ultimo = _fila(muchos.last);
      await tester.dragUntilVisible(
        ultimo,
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.tap(ultimo);
      await _asentar(tester);
      expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 24A');
    });
  });

  group('C·10 «Depto: como una casa»', () {
    testWidgets('tocar un depto lo abre como una casa: «Grecia 3313 · Depto 3B», su estado y piso, '
        '«Registrar visita», «PERSONAS» con María y su «\$ Cobrar»', (tester) async {
      final m = await _montar(tester);

      await tester.tap(_fila(_d3B));
      await _asentar(tester);

      expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 3B');
      expect(_texto(tester, ClavesHojaCasa.subtitulo), 'Cobranza pendiente · piso 3');
      expect(_volver, findsOneWidget);
      expect(_registrar, findsOneWidget);
      expect(find.text(TextosDeptosDeLaCasa.personas), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.listaDePersonas), findsOneWidget);
      expect(m.lecturas.last, (
        ubicacionId: _ubicacionId,
        tipo: TipoUbicacion.edificio,
        espacioId: 'd-3b',
      ));
      // El edificio se edita desde su lista: en el depto no va «Editar edificio».
      expect(find.byKey(ClavesHojaCasa.editar), findsNothing);
    });

    testWidgets('«Registrar visita» del depto lleva el depto a «¿Qué pasó?»', (tester) async {
      final m = await _montar(tester);
      await tester.tap(_fila(_d3B));
      await _asentar(tester);

      await tester.tap(_registrar);
      await _asentar(tester);

      expect(m.visitas.single, (ubicacionId: _ubicacionId, espacioId: 'd-3b', agendaId: null));
    });

    testWidgets(
      'la «‹» vuelve a la lista de deptos, y el atrás del teléfono también, de a un paso',
      (tester) async {
        final m = await _montar(tester);

        await tester.tap(_fila(_d3B));
        await _asentar(tester);
        await tester.tap(_volver);
        await _asentar(tester);
        expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313');
        expect(_fila(_d3B), findsOneWidget);

        await tester.tap(_fila(_d1A));
        await _asentar(tester);
        await tester.binding.handlePopRoute();
        await _asentar(tester);
        expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313');
        expect(
          m.cierres,
          0,
          reason: 'el atrás no cierra la hoja mientras tiene un paso para atrás',
        );
      },
    );

    testWidgets(
      'con el atrás en manos del mapa, la hoja deja ahí su paso para atrás (y lo saca en la '
      'lista)',
      (tester) async {
        final m = await _montar(tester, conAtras: true);
        expect(m.atras.value, isNull);

        await tester.tap(_fila(_d3B));
        await _asentar(tester);
        expect(m.atras.value, isNotNull);

        m.atras.value!();
        await _asentar(tester);
        expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313');
        expect(m.atras.value, isNull);
      },
    );

    testWidgets('volver a la lista y entrar a otro depto no arrastra el aviso de una falla', (
      tester,
    ) async {
      final m = await _montar(tester);
      await tester.tap(_fila(_d3B));
      await _asentar(tester);
      m.lanzaVisita = StateError('no abrió');
      await tester.tap(_registrar);
      await _asentar(tester);
      expect(find.text(TextosHojaCasa.noPudimosAbrirVisita), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_registrar).onPressed,
        isNotNull,
        reason: 'vuelve a andar',
      );

      await tester.tap(_volver);
      await _asentar(tester);
      await tester.tap(_fila(_d2A));
      await _asentar(tester);
      expect(find.text(TextosHojaCasa.noPudimosAbrirVisita), findsNothing);
      expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 2A');
    });

    testWidgets('con la hoja arriba (C·02), el depto tiene las mismas pestañas que una casa', (
      tester,
    ) async {
      await _montar(tester, arriba: true);

      await tester.tap(_fila(_d3B));
      await _asentar(tester);

      expect(find.byKey(ClavesHojaCasa.pestanas), findsOneWidget);
      expect(_registrar, findsOneWidget);
    });
  });

  group('N·04 a N·07: el edificio recién registrado', () {
    testWidgets(
      'N·04: «Edificio en Grecia 3313», «Sumá los deptos…», DEPTOS con la cuenta, las filas '
      'con el piso, «Agregar depto · Número y piso» y «Seguir»',
      (tester) async {
        await _montar(tester, recien: true, espacios: [_d1A]);

        expect(_texto(tester, ClavesHojaCasa.titulo), 'Edificio en Grecia 3313');
        expect(find.text(TextosDeptosDeLaCasa.sumaLosDeptos), findsOneWidget);
        expect(_texto(tester, ClavesDeptosDeLaCasa.rotulo), 'DEPTOS');
        expect(_texto(tester, ClavesDeptosDeLaCasa.cuenta), '1');
        expect(find.text('Piso 1'), findsOneWidget);
        expect(find.byKey(ClavesDeptosDeLaCasa.tarjetaAgregar), findsOneWidget);
        expect(find.byKey(ClavesDeptosDeLaCasa.seguir), findsOneWidget);
        expect(_agregar, findsNothing, reason: 'en N·04 se agrega con la tarjeta');
      },
    );

    testWidgets(
      '«Seguir» pasa a N·06 (recién registrado, «Piso 1 · Sin visita»), tocar un depto abre '
      '«¿Qué pasó?» para ese depto (N·07) y, si se guardó, la hoja se cierra',
      (tester) async {
        final m = await _montar(
          tester,
          recien: true,
          espacios: [_d1A, _d2A],
          antes: (m) =>
              m.resumen = () =>
                  Stream.value({'d-1a': ResumenDelDepto(), 'd-2a': ResumenDelDepto()}),
        );

        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.seguir));
        await _asentar(tester);
        expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313');
        expect(_texto(tester, ClavesHojaCasa.subtitulo), 'Edificio · 2 deptos · recién registrado');
        expect(find.text('Piso 1 · Sin visita'), findsOneWidget);
        expect(_texto(tester, ClavesDeptosDeLaCasa.rotulo), '2 DEPTOS');

        m.salidaVisita = true;
        await tester.tap(_fila(_d2A));
        await _asentar(tester);
        expect(m.visitas.single, (ubicacionId: _ubicacionId, espacioId: 'd-2a', agendaId: null));
        expect(m.cierres, 1, reason: 'tras guardar, el mapa queda libre (05/11)');
      },
    );

    testWidgets(
      '«Volver» de N·04 cierra la hoja como la ✕, sin deshacer el alta (P1, decisión §2 del '
      '11/11)',
      (tester) async {
        final m = await _montar(tester, recien: true, espacios: [_d1A]);

        expect(find.byKey(ClavesDeptosDeLaCasa.volverDeN04), findsOneWidget);
        expect(
          tester.getSize(find.byKey(ClavesDeptosDeLaCasa.volverDeN04)).height,
          greaterThanOrEqualTo(48),
        );
        await tester.ensureVisible(find.byKey(ClavesDeptosDeLaCasa.volverDeN04));
        await tester.pump();
        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.volverDeN04));
        await _asentar(tester);

        expect(m.cierres, 1);
        expect(m.repo.llamadas, isEmpty, reason: 'no se borra ni se toca nada');
      },
    );

    testWidgets('«Volver» no está en N·06', (tester) async {
      await _montar(tester, recien: true, espacios: [_d1A]);
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.seguir));
      await _asentar(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.volverDeN04), findsNothing);
    });

    testWidgets('un edificio que ya estaba (C·09) no lleva «Volver»', (tester) async {
      await _montar(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.volverDeN04), findsNothing);
    });

    testWidgets('el atrás en N·06 vuelve a N·04, sin cerrar la hoja', (tester) async {
      final m = await _montar(tester, recien: true, espacios: [_d1A]);
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.seguir));
      await _asentar(tester);

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(_texto(tester, ClavesHojaCasa.titulo), 'Edificio en Grecia 3313');
      expect(m.cierres, 0);
    });

    testWidgets(
      'doble toque en un depto de N·06: abre «¿Qué pasó?» una sola vez; si falla, avisa y '
      'las filas vuelven a andar',
      (tester) async {
        final m = await _montar(tester, recien: true, espacios: [_d1A, _d2A]);
        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.seguir));
        await _asentar(tester);
        final espera = Completer<Object?>();
        m.esperaVisita = espera;

        await tester.tap(_fila(_d1A));
        await tester.tap(_fila(_d1A));
        await tester.tap(_fila(_d2A));
        await tester.pump();
        expect(m.visitas, hasLength(1));

        m.esperaVisita = null;
        espera.completeError(StateError('no abrió'));
        await _asentar(tester);
        expect(find.text(TextosHojaCasa.noPudimosAbrirVisita), findsOneWidget);

        await tester.tap(_fila(_d2A));
        await _asentar(tester);
        expect(m.visitas, hasLength(2));
        expect(m.visitas.last.espacioId, 'd-2a');
      },
    );

    testWidgets('un negocio recién registrado no pasa por N·04: abre sus deptos como C·09', (
      tester,
    ) async {
      await _montar(
        tester,
        tipo: TipoUbicacion.negocio,
        recien: true,
        espacios: [espacioDe('e-unico', null)],
      );

      expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313');
      expect(find.byKey(ClavesDeptosDeLaCasa.seguir), findsNothing);
      expect(_texto(tester, ClavesDeptosDeLaCasa.rotulo), '1 DEPTO');
    });
  });

  group('negocio como un edificio (Cristian, 09/11, «Negocio mapa»)', () {
    testWidgets('el negocio abre sus espacios como el edificio y cada uno como una casa', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        tipo: TipoUbicacion.negocio,
        espacios: [espacioDe('e-a', null, orden: 1), espacioDe('e-b', 'B', orden: 2)],
        antes: (m) => m.resumen = () => Stream.value({'e-a': ResumenDelDepto()}),
      );

      expect(_texto(tester, ClavesHojaCasa.subtitulo), 'Negocio · 2 deptos · a 35\u00A0m de vos');
      expect(find.text('Sin número'), findsOneWidget);
      expect(_registrar, findsNothing);

      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.fila('e-b')));
      await _asentar(tester);
      expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto B');
      await tester.tap(_registrar);
      await _asentar(tester);
      expect(m.visitas.single.espacioId, 'e-b');
    });
  });

  group('«+ Agregar depto» (N·05, el alta de la vista 11)', () {
    testWidgets('abre el alta del depto con la ubicación y, al agregar, vuelve a la lista con el '
        'depto nuevo', (tester) async {
      final m = await _montar(tester, espacios: [_d1A]);

      await tester.tap(_agregar);
      await _asentar(tester);
      expect(find.byKey(ClavesHojaDepto.hoja), findsOneWidget);
      await tester.enterText(
        find.descendant(of: find.byKey(ClavesHojaDepto.numero), matching: find.byType(TextField)),
        '5C',
      );
      await tester.tap(find.byKey(ClavesHojaDepto.agregar));
      await _asentar(tester, 10);

      expect(find.byKey(ClavesHojaDepto.hoja), findsNothing);
      expect(m.repo.llamadas, ['agregar:nuevo-1']);
      expect(_texto(tester, ClavesDeptosDeLaCasa.rotulo), '2 DEPTOS');
      expect(find.byKey(ClavesDeptosDeLaCasa.fila('nuevo-1')), findsOneWidget);
    });

    testWidgets('dos toques seguidos abren una sola alta', (tester) async {
      await _montar(tester, espacios: [_d1A]);

      await tester.tap(_agregar);
      await tester.tap(_agregar, warnIfMissed: false);
      await _asentar(tester);

      expect(find.byKey(ClavesHojaDepto.hoja), findsOneWidget);
    });

    testWidgets(
      'un número que ya existe avisa como 11·03 y «Ver depto 3B ›» abre ese depto (C·10)',
      (tester) async {
        await _montar(tester);

        await tester.tap(_agregar);
        await _asentar(tester);
        await tester.enterText(
          find.descendant(of: find.byKey(ClavesHojaDepto.numero), matching: find.byType(TextField)),
          '3 b',
        );
        await tester.tap(find.byKey(ClavesHojaDepto.agregar));
        await _asentar(tester);
        expect(find.byKey(ClavesHojaDepto.repetido), findsOneWidget);

        await tester.tap(find.byKey(ClavesHojaDepto.verRepetido));
        await _asentar(tester, 12);
        expect(_texto(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 3B');
      },
    );

    testWidgets('desde N·04, la tarjeta «Agregar depto» abre la misma alta y el depto queda en la '
        'lista', (tester) async {
      final m = await _montar(tester, recien: true, espacios: const []);

      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.tarjetaAgregar));
      await _asentar(tester);
      await tester.enterText(
        find.descendant(of: find.byKey(ClavesHojaDepto.numero), matching: find.byType(TextField)),
        '1A',
      );
      await tester.tap(find.byKey(ClavesHojaDepto.agregar));
      await _asentar(tester, 10);

      expect(m.repo.llamadas, ['agregar:nuevo-1']);
      expect(_texto(tester, ClavesDeptosDeLaCasa.cuenta), '1');
      expect(_texto(tester, ClavesHojaCasa.titulo), 'Edificio en Grecia 3313');
    });
  });

  group('texto grande y teléfono chico', () {
    for (final (nombre, recien) in [('C·09', false), ('N·04', true)]) {
      testWidgets('$nombre al 200 % en 320×568: nada se desborda', (tester) async {
        await _montar(tester, recien: recien, escala: 2, tamano: const Size(320, 568));

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesDeptosDeLaCasa.lista), findsOneWidget);
      });
    }

    testWidgets('C·10 al 200 % en 320×568: nada se desborda y la «‹» mide 48 dp de alto', (
      tester,
    ) async {
      await _montar(tester, escala: 2, tamano: const Size(320, 568));
      await tester.ensureVisible(_fila(_d3B));
      await tester.pump();
      await tester.tap(_fila(_d3B));
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_volver).height, greaterThanOrEqualTo(48));
    });

    testWidgets('las filas de los deptos miden 54 dp o más', (tester) async {
      await _montar(tester);

      expect(tester.getSize(_fila(_d1A)).height, greaterThanOrEqualTo(54));
    });
  });

  group('casa con más de un espacio activo (P1 de 452-qa-261111-1635)', () {
    testWidgets('se muestra como un edificio (C·09), sin «+ Agregar depto», y cada espacio se abre '
        'como una casa', (tester) async {
      final m = await _montar(
        tester,
        tipo: TipoUbicacion.casa,
        espacios: [espacioDe('e-a', 'A', orden: 1), espacioDe('e-b', 'B', orden: 2)],
      );

      expect(find.byKey(ClavesDeptosDeLaCasa.fila('e-a')), findsOneWidget);
      expect(find.byKey(ClavesDeptosDeLaCasa.fila('e-b')), findsOneWidget);
      expect(_registrar, findsNothing);
      expect(_agregar, findsNothing);
      // La hoja no tomó un espacio por el colportor.
      expect(m.lecturas.where((c) => c.espacioId != null), isEmpty);

      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.fila('e-b')));
      await _asentar(tester);
      await tester.tap(_registrar);
      await _asentar(tester);
      expect(m.visitas.single.espacioId, 'e-b');

      await tester.tap(_volver);
      await _asentar(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.fila('e-a')), findsOneWidget);
    });

    testWidgets('con un solo espacio sigue siendo la hoja de una casa', (tester) async {
      await _montar(tester, tipo: TipoUbicacion.casa, espacios: [espacioDe('e-a', null, orden: 1)]);

      expect(find.byKey(ClavesDeptosDeLaCasa.fila('e-a')), findsNothing);
      expect(_registrar, findsOneWidget);
    });
  });

  group('los avisos dicen el lugar (P2 de 452-qa-261111-1635)', () {
    test('textos: casa como el canvas; edificio, negocio y depto con su nombre', () {
      expect(
        TextosEstadosHojaCasa.dadaDeBajaDe(TipoUbicacion.casa),
        TextosEstadosHojaCasa.dadaDeBaja,
      );
      expect(
        TextosEstadosHojaCasa.dadaDeBajaDe(TipoUbicacion.edificio),
        'Este edificio está dado de baja: podés ver lo que pasó, pero no registrar nada.',
      );
      expect(
        TextosEstadosHojaCasa.dadaDeBajaDe(TipoUbicacion.negocio),
        'Este negocio está dado de baja: podés ver lo que pasó, pero no registrar nada.',
      );
      expect(
        TextosEstadosHojaCasa.errorAlLeerDe(TextosEstadosHojaCasa.esteLugar(TipoUbicacion.casa)),
        TextosEstadosHojaCasa.errorAlLeer,
      );
      expect(
        TextosEstadosHojaCasa.errorAlLeerDe(TextosEstadosHojaCasa.esteDepto),
        'No pudimos leer este depto en tu teléfono.',
      );
    });

    testWidgets('el edificio dado de baja dice «Este edificio», también en su depto', (
      tester,
    ) async {
      await _montar(tester, baja: _ahora.subtract(const Duration(days: 2)));
      final texto = TextosEstadosHojaCasa.dadaDeBajaDe(TipoUbicacion.edificio);
      expect(find.text(texto), findsOneWidget);
      expect(find.text(TextosEstadosHojaCasa.dadaDeBaja), findsNothing);

      await tester.tap(_fila(_d3B));
      await _asentar(tester);
      expect(find.text(texto), findsOneWidget);
    });

    testWidgets('el depto que no se puede leer dice «este depto»', (tester) async {
      await _montar(tester, antes: (m) => m.contextoDelDeptoFalla = true);
      await tester.tap(_fila(_d3B));
      await _asentar(tester);

      expect(find.text('No pudimos leer este depto en tu teléfono.'), findsOneWidget);
      expect(find.text(TextosEstadosHojaCasa.errorAlLeer), findsNothing);
    });
  });

  group('«¿Qué pasó?» en un depto (N·07)', () {
    test('el título lleva el número del depto; sin número, «este depto»', () {
      expect(TextosRegistrarVisita.tituloDelDepto('2A'), '¿Qué pasó en el 2A?');
      expect(TextosRegistrarVisita.tituloDelDepto(' '), '¿Qué pasó en este depto?');
      expect(TextosRegistrarVisita.tituloDelDepto(null), '¿Qué pasó en este depto?');
    });
  });
}
