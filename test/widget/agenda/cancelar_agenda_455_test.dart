// HU-VIS-004 / issue #455 — cancelar una agenda desde el detalle de verdad (vista 23, 23C·04 y 23C·05),
// de punta a punta: la pestaña «Agenda» real abre el detalle real, el enlace «Cancelar agenda» abre la
// hoja y, al confirmar, la colportora vuelve a la lista con «Agenda cancelada.» y la fila ya no está
// entre las pendientes. Los estados 23C·06 (ya cumplida) y el error al guardar (23C·07), y los casos
// límite de cada flujo: doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, datos
// límite y texto al 200 %.
//
// La hoja y el enlace solos se prueban en `cancelar_agenda_150_test.dart`; acá se prueba que el detalle
// los monta bien y que la lista los ve.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_cancelar_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agendar_visita_arnes.dart' show casaMataojo, mariaFernandez;
import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/persona_falsos.dart';

const _tituloEntrevista = '¿Cancelar la entrevista?';
const _tituloCobranza = '¿Cancelar la cobranza?';
const _cuerpoEntrevista =
    'Queda como cancelada (la ves con el filtro «Canceladas»), se borra el recordatorio y la casa '
    'vuelve a su estado anterior.';
const _canceladaOk = 'Agenda cancelada.';
const _canceladaSinAviso =
    'Agenda cancelada. No pudimos borrar el recordatorio: puede sonar igual.';
const _errorAlGuardar = 'No pudimos guardar el cambio. La agenda sigue como estaba.';
const _yaTieneResultado = 'Esta visita ya tiene resultado: no se puede modificar ni cancelar.';
const _yaNoSePuede = 'Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.';

/// Lo que el montaje deja ver al test.
final class _Montaje {
  _Montaje({
    required this.repo,
    required this.consulta,
    required this.telefono,
    required this.tipo,
  });

  final AgendaRepositorioDetalle repo;
  final ConsultaAgendaFalsa consulta;
  final Telefono telefono;
  final TipoAgenda tipo;

  /// Cuántas veces la lista abrió el detalle.
  var aperturas = 0;
}

/// La fila de la agenda `ag-1` en la lista, como la lee la pestaña.
List<ItemAgenda> _filas(TipoAgenda tipo, EstadoAgenda estado, DateTime ahora) => [
  itemAgenda(
    'ag-1',
    DateTime(2026, 10, 24, 14, 30),
    tipo: tipo,
    estado: estado,
    nombre: 'María',
    apellido: 'Fernández',
    calle: 'Mataojo',
    numero: '2044',
    espacioId: 'esp-1',
    actualizada: estado == EstadoAgenda.programada ? null : ahora,
  ),
];

/// Monta la pestaña «Agenda» real con el detalle real detrás de cada fila. Con [entrar] toca la fila.
Future<_Montaje> _montar(
  WidgetTester tester, {
  TipoAgenda tipo = TipoAgenda.entrevista,
  bool entrar = true,
  bool recordatorioSeQueda = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  String? nota,
}) async {
  final ahora = ahoraDelDetalle();
  final repo = AgendaRepositorioDetalle(
    DetalleDeAgenda(
      agenda: agendaDelDetalle(tipo: tipo),
      nota: nota,
    ),
  );
  final consulta = ConsultaAgendaFalsa(_filas(tipo, EstadoAgenda.programada, ahora));
  final telefono = Telefono();
  telefono.recordatorios.puedeCancelar = !recordatorioSeQueda;
  final montaje = _Montaje(repo: repo, consulta: consulta, telefono: telefono, tipo: tipo);
  repo.alCancelarAgenda = (cancelada) =>
      consulta.emitir(_filas(tipo, EstadoAgenda.cancelada, ahora));
  final navegador = GlobalKey<NavigatorState>();
  final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(repo),
        consultaAgendaRepositoryProvider.overrideWithValue(consulta),
        relojVisitaProvider.overrideWithValue(() => ahora),
        relojAgendaProvider.overrideWithValue(() => ahora),
        ...telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personas),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaMataojo())),
        abrirDetalleDeAgendaProvider.overrideWithValue((agendaId) {
          montaje.aperturas += 1;
          return DetalleAgendaPage.abrir(
            navegador.currentContext!,
            agendaId: agendaId,
            colportorId: 'col-1',
          );
        }),
      ],
      child: MaterialApp(
        navigatorKey: navegador,
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
      ),
    ),
  );
  await asentarDetalle(tester);
  if (entrar) await _entrar(tester);
  return montaje;
}

Future<void> _entrar(WidgetTester tester) async {
  final fila = find.text('María Fernández');
  // Con el texto al 200 % en una pantalla chica la fila queda más abajo de lo que se ve.
  await tester.scrollUntilVisible(fila, 100, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(fila);
  await tester.pump();
  await tester.tap(fila);
  await asentarDetalle(tester);
}

/// Cierra la pantalla: el temporizador del minuto de la lista se cancela en `dispose`.
Future<void> _desmontar(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

Finder get _enlace => find.descendant(
  of: find.byType(DetalleAgendaPage),
  matching: find.widgetWithText(TextButton, 'Cancelar agenda'),
);
Finder get _hoja => find.byType(HojaCancelarAgenda);
Finder get _confirmar => find.descendant(of: _hoja, matching: find.byType(FilledButton));
Finder get _volver => find.descendant(of: _hoja, matching: find.byType(OutlinedButton));
Finder get _detalle => find.byType(DetalleAgendaPage);

Future<void> _abrirHoja(WidgetTester tester) async {
  await tester.ensureVisible(_enlace);
  await tester.tap(_enlace);
  await asentarDetalle(tester);
}

Future<void> _confirmarCancelacion(WidgetTester tester) async {
  await tester.ensureVisible(_confirmar);
  await tester.tap(_confirmar);
  await asentarDetalle(tester);
}

Future<void> _filtrarCanceladas(WidgetTester tester) async {
  await tester.tap(find.text('Pendientes ▾'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('agenda_estado_canceladas')));
  await tester.tap(find.text('Aplicar'));
  await tester.pumpAndSettle();
}

void main() {
  group('23C·01 → 23C·04 · El enlace del detalle abre la hoja de confirmar', () {
    testWidgets('dado el detalle de una entrevista programada, cuando toco «Cancelar agenda», se '
        'abre «¿Cancelar la entrevista?» con el texto del canvas y no se escribe nada', (
      tester,
    ) async {
      final m = await _montar(tester);

      expect(_enlace, findsOneWidget);
      await _abrirHoja(tester);

      expect(_hoja, findsOneWidget);
      expect(find.text(_tituloEntrevista), findsOneWidget);
      expect(find.text(_cuerpoEntrevista), findsOneWidget);
      expect(find.descendant(of: _confirmar, matching: find.text('Cancelar agenda')), findsOne);
      expect(find.descendant(of: _volver, matching: find.text('Volver')), findsOneWidget);
      // El detalle sigue detrás, sin tocar.
      expect(_detalle, findsOneWidget);
      expect(m.repo.canceladas, isEmpty);
      await _desmontar(tester);
    });

    testWidgets('dado una cobranza, cuando abro la hoja, el título dice cobranza', (tester) async {
      await _montar(tester, tipo: TipoAgenda.cobranza);

      await _abrirHoja(tester);

      expect(find.text(_tituloCobranza), findsOneWidget);
      expect(find.text(_tituloEntrevista), findsNothing);
      await _desmontar(tester);
    });

    testWidgets('dado la hoja abierta, cuando toco «Volver», se cierra y la agenda sigue '
        'programada: el detalle conserva todas sus salidas', (tester) async {
      final m = await _montar(tester);
      await _abrirHoja(tester);

      await tester.tap(_volver);
      await asentarDetalle(tester);

      expect(_hoja, findsNothing);
      expect(_detalle, findsOneWidget);
      expect(m.repo.canceladas, isEmpty);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(_enlace, findsOneWidget);
      expect(find.text(_canceladaOk), findsNothing);
      await _desmontar(tester);
    });

    testWidgets('dado la hoja abierta, cuando uso «atrás» del sistema, se cierra la hoja y no el '
        'detalle', (tester) async {
      final m = await _montar(tester);
      await _abrirHoja(tester);

      await tester.binding.handlePopRoute();
      await asentarDetalle(tester);

      expect(_hoja, findsNothing);
      expect(_detalle, findsOneWidget);
      expect(m.repo.canceladas, isEmpty);
      await _desmontar(tester);
    });
  });

  group('23C·05 · Cancelada (éxito)', () {
    testWidgets('dado que confirmo, cuando termina, vuelvo a la lista con «Agenda cancelada.», la '
        'fila ya no está entre las pendientes y el recordatorio se fue', (tester) async {
      final m = await _montar(tester);
      await m.telefono.recordatorios.programar(_recordatorio(m.tipo));
      m.telefono.recordatorios.llamadas.clear();
      await _abrirHoja(tester);

      await _confirmarCancelacion(tester);

      expect(m.repo.canceladas, ['ag-1']);
      expect(_detalle, findsNothing);
      expect(_hoja, findsNothing);
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      expect(find.text(_canceladaOk), findsOneWidget);
      // La lista, que lee en vivo, ya no la muestra entre las pendientes (que es el filtro de siempre).
      expect(find.text('María Fernández'), findsNothing);
      expect(m.telefono.recordatorios.llamadas, ['cancelar:ag-1']);
      expect(m.telefono.recordatorios.programados, isEmpty);
      await _desmontar(tester);
    });

    testWidgets('dado que cancelé, cuando miro «Canceladas», la agenda está ahí, tachada, con su '
        'etiqueta (no se borró)', (tester) async {
      await _montar(tester);
      await _abrirHoja(tester);
      await _confirmarCancelacion(tester);

      await _filtrarCanceladas(tester);

      expect(find.text('Cancelada el 23/10'), findsOneWidget);
      final titulo = tester.widget<Text>(find.text('María Fernández'));
      expect(titulo.style?.decoration, TextDecoration.lineThrough);
      await _desmontar(tester);
    });

    testWidgets('dado que el teléfono no puede sacar el recordatorio, cuando cancelo, la agenda '
        'queda cancelada y el aviso dice que el recordatorio puede sonar', (tester) async {
      final m = await _montar(tester, recordatorioSeQueda: true);
      await _abrirHoja(tester);

      await _confirmarCancelacion(tester);

      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(_canceladaSinAviso), findsOneWidget);
      expect(find.text(_canceladaOk), findsNothing);
      expect(find.text('María Fernández'), findsNothing);
      await _desmontar(tester);
    });

    testWidgets(
      'dado que cancelé y vuelvo a entrar a esa agenda desde «Canceladas», cuando miro el '
      'detalle, dice que está cancelada y no ofrece ni «Modificar» ni «Cancelar agenda»',
      (tester) async {
        final m = await _montar(tester);
        await _abrirHoja(tester);
        await _confirmarCancelacion(tester);
        await _filtrarCanceladas(tester);

        await _entrar(tester);

        expect(m.aperturas, 2);
        expect(_detalle, findsOneWidget);
        expect(find.text('Esta agenda está cancelada: no se puede modificar.'), findsOneWidget);
        expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
        expect(find.text('Cancelar agenda'), findsNothing);
        await _desmontar(tester);
      },
    );
  });

  group('Error al guardar (aviso de 23C·07)', () {
    testWidgets('dado que la base falla, cuando confirmo, la hoja muestra el aviso del canvas, '
        'la agenda sigue programada y el botón vuelve a poder tocarse como «Reintentar»', (
      tester,
    ) async {
      final m = await _montar(tester);
      m.repo.fallasAlCancelar.add(const FailureInesperado(causa: 'StateError'));
      await m.telefono.recordatorios.programar(_recordatorio(m.tipo));
      await _abrirHoja(tester);

      await _confirmarCancelacion(tester);

      expect(_hoja, findsOneWidget);
      expect(find.text(_errorAlGuardar), findsOneWidget);
      expect(find.descendant(of: _confirmar, matching: find.text('Reintentar')), findsOneWidget);
      expect(tester.widget<FilledButton>(_confirmar).onPressed, isNotNull);
      expect(find.text('Cancelando…'), findsNothing);
      // Nada cambió: el recordatorio sigue y la lista todavía la tiene.
      expect(m.telefono.recordatorios.programados, contains('ag-1'));
      expect(find.text(_canceladaOk), findsNothing);
      await _desmontar(tester);
    });

    testWidgets('dado una falla, cuando toco «Reintentar», se cancela, el aviso rojo se va y se '
        'vuelve a la lista', (tester) async {
      final m = await _montar(tester);
      m.repo.fallasAlCancelar.add(const FailureInesperado(causa: 'StateError'));
      await _abrirHoja(tester);
      await _confirmarCancelacion(tester);

      await _confirmarCancelacion(tester);

      expect(m.repo.canceladas, ['ag-1', 'ag-1']);
      expect(_hoja, findsNothing);
      expect(_detalle, findsNothing);
      expect(find.text(_errorAlGuardar), findsNothing);
      expect(find.text(_canceladaOk), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('dado una excepción que se escapa del repositorio, cuando confirmo, es una falla '
        'más: el aviso sale y nada queda en «Cancelando…»', (tester) async {
      final m = await _montar(tester);
      m.repo.lanzarAlCancelar = StateError('se cayó la base');
      await _abrirHoja(tester);

      await _confirmarCancelacion(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(_errorAlGuardar), findsOneWidget);
      expect(find.text('Cancelando…'), findsNothing);
      expect(tester.widget<FilledButton>(_confirmar).onPressed, isNotNull);
      await _desmontar(tester);
    });

    testWidgets('dado una falla y «Volver», cuando miro el detalle, todo sigue como estaba y se '
        'puede abrir la hoja de nuevo', (tester) async {
      final m = await _montar(tester);
      m.repo.fallasAlCancelar.add(const FailureInesperado(causa: 'StateError'));
      await _abrirHoja(tester);
      await _confirmarCancelacion(tester);

      await tester.tap(_volver);
      await asentarDetalle(tester);
      expect(_hoja, findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);

      await _abrirHoja(tester);
      expect(_hoja, findsOneWidget);
      expect(find.text(_errorAlGuardar), findsNothing, reason: 'la hoja nueva arranca limpia');
      await _desmontar(tester);
    });
  });

  group('23C·06 · La agenda se cumplió mientras la hoja estaba abierta', () {
    testWidgets('dado que la agenda ya tiene resultado, cuando confirmo, el aviso dice por qué y '
        'queda solo «Volver»; al volver, el detalle ya muestra 23C·06 sin salidas', (tester) async {
      final m = await _montar(tester);
      await _abrirHoja(tester);
      // La visita se registró mientras la hoja estaba abierta.
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.cumplida));
      m.repo.fallasAlCancelar.add(const FailureValidacion(campos: {'agenda': _yaNoSePuede}));

      await _confirmarCancelacion(tester);

      expect(find.text(_yaNoSePuede), findsOneWidget);
      expect(_confirmar, findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      expect(_volver, findsOneWidget);

      await tester.tap(_volver);
      await asentarDetalle(tester);

      expect(_hoja, findsNothing);
      expect(find.text(_yaTieneResultado), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
      expect(find.text('Cancelar agenda'), findsNothing);
      expect(find.text(_canceladaOk), findsNothing);
      await _desmontar(tester);
    });

    testWidgets('dado que cierro la hoja con «atrás» después de ese aviso, cuando vuelvo al '
        'detalle, también se vuelve a leer', (tester) async {
      final m = await _montar(tester);
      await _abrirHoja(tester);
      m.repo.detalle = DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.noCumplida));
      m.repo.fallasAlCancelar.add(const FailureValidacion(campos: {'agenda': _yaNoSePuede}));
      await _confirmarCancelacion(tester);

      await tester.binding.handlePopRoute();
      await asentarDetalle(tester);

      expect(find.text(_yaTieneResultado), findsOneWidget);
      expect(find.text('Cancelar agenda'), findsNothing);
      await _desmontar(tester);
    });

    testWidgets('dado «Volver» sin haber cancelado y sin cambios, cuando vuelvo, el detalle se '
        'vuelve a leer una vez y sigue igual (sin parpadeo de «cargando»)', (tester) async {
      final m = await _montar(tester);
      final lecturas = m.repo.lecturas;
      await _abrirHoja(tester);

      await tester.tap(_volver);
      await tester.pump();
      expect(find.byKey(ClavesDetalleAgenda.cargando), findsNothing);
      await asentarDetalle(tester);

      expect(m.repo.lecturas, lecturas + 1);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      await _desmontar(tester);
    });
  });

  group('Doble toque, dos acciones seguidas y volver atrás', () {
    testWidgets('dado un doble toque en «Cancelar agenda», cuando llega el segundo, se abre una '
        'sola hoja', (tester) async {
      await _montar(tester);
      await tester.ensureVisible(_enlace);

      await tester.tap(_enlace);
      await tester.tap(_enlace, warnIfMissed: false);
      await asentarDetalle(tester);

      expect(_hoja, findsOneWidget);
      await tester.tap(_volver);
      await asentarDetalle(tester);
      expect(_hoja, findsNothing);
      expect(_detalle, findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('dado un doble toque en el botón de confirmar, cuando llega el segundo, se cancela '
        'una sola vez', (tester) async {
      final m = await _montar(tester);
      m.repo.compuertaAlCancelar = Completer<void>();
      await _abrirHoja(tester);

      await tester.tap(_confirmar);
      await tester.tap(_confirmar, warnIfMissed: false);
      await tester.pump();
      m.repo.compuertaAlCancelar!.complete();
      await asentarDetalle(tester);

      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(_canceladaOk), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('dado que la cancelación está en curso, cuando miro la hoja, dice «Cancelando…», '
        'no se puede tocar «Volver» y el «atrás» no la cierra', (tester) async {
      final m = await _montar(tester);
      m.repo.compuertaAlCancelar = Completer<void>();
      await _abrirHoja(tester);

      await tester.tap(_confirmar);
      await tester.pump();

      expect(find.text('Cancelando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(_confirmar).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_volver).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_hoja, findsOneWidget);

      m.repo.compuertaAlCancelar!.complete();
      await asentarDetalle(tester);
      expect(_hoja, findsNothing);
      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(_canceladaOk), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('dado que mientras se cancela toco «Modificar» y «Registrar» del detalle, cuando '
        'termina, no se abrió nada más y la lista queda limpia', (tester) async {
      final m = await _montar(tester);
      m.repo.compuertaAlCancelar = Completer<void>();
      await _abrirHoja(tester);
      await tester.tap(_confirmar);
      await tester.pump();

      // La hoja tapa el detalle: un toque sobre «Modificar» cae en la barrera, no en el botón.
      await tester.tap(find.byKey(ClavesDetalleAgenda.modificar), warnIfMissed: false);
      await tester.pump();
      m.repo.compuertaAlCancelar!.complete();
      await asentarDetalle(tester);

      expect(find.text('Modificar agenda'), findsNothing);
      expect(m.repo.canceladas, ['ag-1']);
      expect(_detalle, findsNothing);
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('dado que entro, salgo con «atrás» y reentro, cuando cancelo, funciona igual y '
        'cada apertura lee de nuevo', (tester) async {
      final m = await _montar(tester);
      await tester.tap(find.byKey(ClavesDetalleAgenda.volver));
      await asentarDetalle(tester);
      expect(_detalle, findsNothing);

      await _entrar(tester);
      expect(m.aperturas, 2);
      await _abrirHoja(tester);
      await _confirmarCancelacion(tester);

      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(_canceladaOk), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _desmontar(tester);
    });
  });

  group('Sin conexión', () {
    testWidgets('dado un teléfono sin red, cuando cancelo, funciona igual: todo es local', (
      tester,
    ) async {
      final m = await _montar(tester);
      m.telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await _abrirHoja(tester);

      await _confirmarCancelacion(tester);

      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(_canceladaOk), findsOneWidget);
      expect(find.text(_errorAlGuardar), findsNothing);
      await _desmontar(tester);
    });
  });

  group('Datos límite: texto al 200 % y pantallas chicas', () {
    for (final tamano in const [Size(390, 844), Size(320, 568)]) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}';

      testWidgets('dado el texto al 200 % en $etiqueta y una nota larguísima, cuando cancelo '
          'desde el detalle, el enlace y la hoja se alcanzan y no hay desbordes', (tester) async {
        final m = await _montar(tester, escala: 2, tamano: tamano, nota: 'Nota muy larga ' * 40);
        expect(tester.takeException(), isNull);

        await _abrirHoja(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_confirmar);
        await tester.pump();
        await tester.ensureVisible(_volver);
        await tester.pump();
        await tester.ensureVisible(_confirmar);
        await tester.tap(_confirmar);
        await asentarDetalle(tester);

        expect(tester.takeException(), isNull);
        expect(m.repo.canceladas, ['ag-1']);
        expect(find.text(_canceladaOk), findsOneWidget);
        await _desmontar(tester);
      });

      testWidgets('dado el texto al 200 % en $etiqueta y una falla, cuando miro la hoja, el aviso '
          'entero y los dos botones se alcanzan', (tester) async {
        final m = await _montar(tester, escala: 2, tamano: tamano, tipo: TipoAgenda.cobranza);
        m.repo.fallasAlCancelar.add(const FailureInesperado(causa: 'StateError'));
        await _abrirHoja(tester);
        await tester.ensureVisible(_confirmar);
        await tester.tap(_confirmar);
        await asentarDetalle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(_errorAlGuardar), findsOneWidget);
        await tester.ensureVisible(_confirmar);
        await tester.pump();
        expect(tester.getRect(_confirmar).bottom, lessThanOrEqualTo(tamano.height));
        await tester.ensureVisible(_volver);
        await tester.pump();
        expect(tester.getRect(_volver).bottom, lessThanOrEqualTo(tamano.height));
        await _desmontar(tester);
      });
    }

    testWidgets('dado varias agendas en la lista, cuando cancelo una, las demás siguen y solo '
        'esa sale de las pendientes', (tester) async {
      final ahora = ahoraDelDetalle();
      final m = await _montar(tester, entrar: false);
      final otras = [
        ..._filas(TipoAgenda.entrevista, EstadoAgenda.programada, ahora),
        itemAgenda(
          'ag-2',
          DateTime(2026, 10, 24, 16),
          nombre: 'Luis',
          apellido: 'Pérez',
          calle: 'Rivera',
          numero: '77',
        ),
      ];
      m.consulta.emitir(otras);
      m.repo.alCancelarAgenda = (cancelada) => m.consulta.emitir([otras.last]);
      await asentarDetalle(tester);
      expect(find.text('Luis Pérez'), findsOneWidget);

      await _entrar(tester);
      await _abrirHoja(tester);
      await _confirmarCancelacion(tester);

      expect(find.text('María Fernández'), findsNothing);
      expect(find.text('Luis Pérez'), findsOneWidget);
      expect(find.text(_canceladaOk), findsOneWidget);
      await _desmontar(tester);
    });
  });

  group('Accesibilidad', () {
    testWidgets('dado el detalle con el enlace y la hoja abierta, cuando los miro, tienen objetivo '
        'táctil de 48, etiqueta y contraste', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await _abrirHoja(tester);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await _desmontar(tester);
    });

    testWidgets('dado que cancelé, cuando llega «Agenda cancelada.», el aviso se lee (es un '
        'SnackBar con su región viva) sobre la lista', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester);
      await _abrirHoja(tester);
      await _confirmarCancelacion(tester);

      expect(find.bySemanticsLabel(_canceladaOk), findsOneWidget);
      handle.dispose();
      await _desmontar(tester);
    });
  });
}

/// El recordatorio de `ag-1`, tal como lo programó agendar.
RecordatorioDeVisita _recordatorio(TipoAgenda tipo) => RecordatorioDeVisita(
  agendaId: 'ag-1',
  tipo: tipo,
  direccion: 'Mataojo 2044',
  fechaProgramada: DateTime(2026, 10, 24, 14, 30).toUtc(),
);
