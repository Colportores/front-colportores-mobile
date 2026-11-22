// «Cuenta antes» (HU-AUTH-008, #62; decisión de Cristian del 23/10): la cuenta de quien está inscripto
// en una campaña por empezar es activa, pero «Hoy» le dice cuándo empieza y no le deja iniciar
// jornada hasta ese día. Y, si el servidor no aceptó una jornada por haber empezado antes (decisión
// del 27/10, backend-supabase#184), un solo aviso con sus visitas, sin el error técnico.
//
// Un test por estado (con la campaña por empezar, en curso, sin saber, sin conexión a la réplica) y
// por cada caso límite: doble toque, la lectura que no contesta, dos acciones seguidas, volver y
// reentrar, el día que empieza la campaña, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/campanias_inscriptas_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/campanias_inscriptas_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornadas_rechazadas_data_source.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada_rechazada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornadas_rechazadas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Viernes 20/11/2026, 12:00 en Montevideo (15:00 UTC).
final _ahora = DateTime.utc(2026, 11, 20, 15);

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'agustin@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

const _textoVerano =
    'Tu campaña Verano 2027 empieza el 01/12. Hasta entonces podés bajar el mapa y las casas; '
    'la jornada y las ventas se habilitan ese día.';

CampaniaInscripta _porEmpezar({String nombre = 'Verano 2027', String inicio = '2026-12-01'}) =>
    CampaniaInscripta(
      campaniaId: 'camp-$nombre',
      nombre: nombre,
      fechaInicio: inicio,
      fechaFin: '2027-02-28',
    );

CampaniaInscripta _enCurso() => const CampaniaInscripta(
  campaniaId: 'camp-curso',
  nombre: 'Primavera 2026',
  fechaInicio: '2026-09-01',
  fechaFin: '2026-12-15',
);

/// La réplica que nunca contesta: el stream no emite.
final class _NuncaContesta implements CampaniasInscriptasDataSource {
  @override
  Stream<List<CampaniaInscripta>?> observar(String usuarioId) =>
      StreamController<List<CampaniaInscripta>?>().stream;
}

/// Las jornadas rechazadas, con una perilla para publicarlas como lo hace el motor al rechazar.
final class _Rechazadas implements JornadasRechazadasDataSource {
  _Rechazadas([List<JornadaRechazada> iniciales = const []]) : _actuales = iniciales;

  List<JornadaRechazada> _actuales;
  final _suscriptores = <StreamController<List<JornadaRechazada>>>[];

  @override
  Stream<List<JornadaRechazada>> observar(String colportorId) {
    final c = StreamController<List<JornadaRechazada>>();
    c.onCancel = () => _suscriptores.remove(c);
    _suscriptores.add(c);
    c.add(_actuales);
    return c.stream;
  }

  void publicar(List<JornadaRechazada> jornadas) {
    _actuales = jornadas;
    for (final c in List.of(_suscriptores)) {
      c.add(jornadas);
    }
  }
}

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

final class _Mundo {
  _Mundo({List<CampaniaInscripta>? campanias, List<JornadaRechazada>? rechazadas})
    : replica = CampaniasInscriptasEnMemoria(campanias),
      rechazadas = _Rechazadas(rechazadas ?? const []);

  final CampaniasInscriptasEnMemoria replica;
  final _Rechazadas rechazadas;
  final jornadas = JornadaLocalDataSourceEnMemoria();
  CampaniasInscriptasDataSource? replicaPropia;
  DateTime ahora = _ahora;
}

Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _montar(WidgetTester tester, _Mundo m, {double escala = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(m.jornadas),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => m.ahora),
        relojCampaniaProvider.overrideWithValue(() => m.ahora),
        campaniasInscriptasDataSourceProvider.overrideWithValue(m.replicaPropia ?? m.replica),
        jornadasRechazadasDataSourceProvider.overrideWithValue(m.rechazadas),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(body: JornadaPage(sesion: _sesion)),
      ),
    ),
  );
  await _asentar(tester);
}

Finder get _aviso => find.byKey(const Key('jornada_campania_por_empezar'));
Finder get _snack => find.byKey(const Key('campania_por_empezar_aviso'));
Finder get _iniciar => find.byKey(const Key('jornada_iniciar'));

Future<void> _tocarIniciar(WidgetTester tester) async {
  await tester.ensureVisible(_iniciar);
  await tester.tap(_iniciar);
  await _asentar(tester);
}

bool _iniciarHabilitado(WidgetTester tester) =>
    tester.widget<FilledButton>(_iniciar).onPressed != null;

JornadaRechazada _rechazada(String id, {int visitas = 0, DateTime? inicio}) =>
    JornadaRechazada(id: id, inicio: inicio ?? DateTime.utc(2026, 11, 19, 14), visitas: visitas);

Finder _textoRechazada(String id) => find.byKey(Key('jornada_rechazada_$id'));

void main() {
  group('con la campaña por empezar (18A, «Cuenta antes»)', () {
    testWidgets('«Hoy» dice cuándo empieza la campaña, con el texto de la decisión', (
      tester,
    ) async {
      await _montar(tester, _Mundo(campanias: [_porEmpezar()]));

      expect(_aviso, findsOneWidget);
      expect(find.text(_textoVerano), findsOneWidget);
      expect(find.text('Sin jornada en curso'), findsOneWidget);
    });

    testWidgets('«Iniciar jornada» no inicia: avisa lo mismo, no crea nada y el botón sigue '
        'habilitado', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()]);
      await _montar(tester, m);

      await _tocarIniciar(tester);

      expect(_snack, findsOneWidget);
      expect(find.descendant(of: _snack, matching: find.text(_textoVerano)), findsOneWidget);
      expect(m.jornadas.jornadas, isEmpty);
      expect(find.text('Jornada activa'), findsNothing);
      expect(_iniciarHabilitado(tester), isTrue);
      expect(find.text('Iniciando…'), findsNothing);
    });

    testWidgets('doble toque: un solo aviso y nunca queda «Iniciando…» trabado', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()]);
      await _montar(tester, m);

      await tester.ensureVisible(_iniciar);
      await tester.tap(_iniciar);
      await tester.tap(_iniciar);
      await _asentar(tester);

      expect(_snack, findsOneWidget);
      expect(m.jornadas.jornadas, isEmpty);
      expect(_iniciarHabilitado(tester), isTrue);
    });

    testWidgets('dos toques seguidos, uno después del otro: el aviso se renueva y no se acumula', (
      tester,
    ) async {
      final m = _Mundo(campanias: [_porEmpezar()]);
      await _montar(tester, m);

      await _tocarIniciar(tester);
      await _tocarIniciar(tester);

      expect(_snack, findsOneWidget);
      expect(m.jornadas.jornadas, isEmpty);
    });

    testWidgets('el aviso lleva la ✕ y dura lo suficiente para leerlo con el texto grande', (
      tester,
    ) async {
      await _montar(tester, _Mundo(campanias: [_porEmpezar()]));

      await _tocarIniciar(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(_snack, findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_snack, findsNothing);
    });

    testWidgets('con varias por empezar dice la que empieza primero', (tester) async {
      await _montar(
        tester,
        _Mundo(
          campanias: [
            _porEmpezar(nombre: 'Invierno 2027', inicio: '2027-06-01'),
            _porEmpezar(nombre: 'Verano 2027'),
          ],
        ),
      );

      expect(find.text(_textoVerano), findsOneWidget);
    });

    testWidgets('el día que empieza la campaña el aviso se va y se puede iniciar', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()]);
      await _montar(tester, m);
      expect(_aviso, findsOneWidget);

      // Medianoche del 30/11 al 1/12 en Montevideo: sin pull ni reiniciar la app.
      m.ahora = DateTime.utc(2026, 12, 1, 4);
      await tester.pump(const Duration(minutes: 1));
      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(_snack, findsNothing);
    });

    testWidgets('el último día antes de empezar todavía frena', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()])..ahora = DateTime.utc(2026, 12, 1, 2, 59);
      await _montar(tester, m);

      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, isEmpty);
      expect(_snack, findsOneWidget);
    });

    testWidgets('un pull que trae la campaña con la pantalla abierta pone el aviso, y otro que la '
        'saca lo quita', (tester) async {
      final m = _Mundo(campanias: const []);
      await _montar(tester, m);
      expect(_aviso, findsNothing);

      m.replica.publicar([_porEmpezar()]);
      await _asentar(tester);
      expect(_aviso, findsOneWidget);

      m.replica.publicar([_enCurso()]);
      await _asentar(tester);
      expect(_aviso, findsNothing);
    });

    testWidgets('volver atrás y reentrar: el aviso y el freno siguen', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()]);
      await _montar(tester, m);
      await _tocarIniciar(tester);

      await tester.pumpWidget(const SizedBox());
      await _montar(tester, m);

      expect(_aviso, findsOneWidget);
      await _tocarIniciar(tester);
      expect(_snack, findsOneWidget);
      expect(m.jornadas.jornadas, isEmpty);
    });

    testWidgets('textos largos y letra al 200 %: el aviso se lee entero y no desborda', (
      tester,
    ) async {
      final m = _Mundo(
        campanias: [_porEmpezar(nombre: 'Campaña especial de invierno para estudiantes 2027')],
      );
      await _montar(tester, m, escala: 2);

      expect(tester.takeException(), isNull);
      expect(_aviso, findsOneWidget);
      await _tocarIniciar(tester);
      expect(tester.takeException(), isNull);
      expect(_snack, findsOneWidget);
    });

    testWidgets('el aviso se anuncia a quien usa lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, _Mundo(campanias: [_porEmpezar()]));

      expect(tester.getSemantics(find.text(_textoVerano)).label, _textoVerano);
      final region = tester.getSemantics(find.descendant(of: _aviso, matching: find.byType(Row)));
      expect(region.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });
  });

  group('lo que no frena nada', () {
    testWidgets('con una campaña en curso (aunque haya otra por empezar) no hay aviso y la '
        'jornada se inicia', (tester) async {
      final m = _Mundo(campanias: [_enCurso(), _porEmpezar()]);
      await _montar(tester, m);

      expect(_aviso, findsNothing);
      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
      expect(find.text('Jornada activa'), findsOneWidget);
    });

    testWidgets('sin inscripciones no se afirma nada de la campaña: la jornada se inicia', (
      tester,
    ) async {
      final m = _Mundo(campanias: const []);
      await _montar(tester, m);

      expect(_aviso, findsNothing);
      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
    });

    testWidgets(
      'si el teléfono todavía no sabe cuál es la campaña (el pull no la trajo) no frena',
      (tester) async {
        final m = _Mundo(campanias: null);
        await _montar(tester, m);

        expect(_aviso, findsNothing);
        await _tocarIniciar(tester);

        expect(m.jornadas.jornadas, hasLength(1));
      },
    );

    testWidgets('si leer la réplica falla no frena (el servidor respalda) ni deja el botón '
        'trabado', (tester) async {
      final m = _Mundo()..replica.falla = StateError('lectura rota');
      await _montar(tester, m);

      expect(_aviso, findsNothing);
      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('si la réplica no contesta, a los 3 s sigue con el inicio y no se traba', (
      tester,
    ) async {
      final m = _Mundo()..replicaPropia = _NuncaContesta();
      await _montar(tester, m);

      await tester.ensureVisible(_iniciar);
      await tester.tap(_iniciar);
      await tester.pump();
      expect(find.text('Iniciando…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await _asentar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
      expect(find.text('Iniciando…'), findsNothing);
    });

    testWidgets('el primer día de la campaña no frena', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()])..ahora = DateTime.utc(2026, 12, 1, 15);
      await _montar(tester, m);

      expect(_aviso, findsNothing);
      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
    });
  });

  group('la jornada que el servidor no aceptó (decisión del 27/10, backend-supabase#184)', () {
    testWidgets('con sus visitas: un solo aviso, con el texto de la decisión y sin el error '
        'técnico', (tester) async {
      final m = _Mundo(campanias: [_porEmpezar()], rechazadas: [_rechazada('j-1', visitas: 4)]);
      await _montar(tester, m);

      const texto =
          'Esta jornada y sus 4 visitas no se enviaron: tu campaña Verano 2027 empieza el 01/12. '
          'No se borró nada; quedan guardadas en este teléfono.';
      expect(find.text(texto), findsOneWidget);
      expect(find.textContaining('23503'), findsNothing);
      expect(find.textContaining('42501'), findsNothing);
      expect(_textoRechazada('j-1'), findsOneWidget);
    });

    testWidgets('con una sola visita y sin visitas el texto va en singular', (tester) async {
      final m = _Mundo(
        campanias: [_porEmpezar()],
        rechazadas: [_rechazada('j-1', visitas: 1), _rechazada('j-2')],
      );
      await _montar(tester, m);

      expect(
        find.text(
          'Esta jornada y su visita no se enviaron: tu campaña Verano 2027 empieza el 01/12. '
          'No se borró nada; quedan guardadas en este teléfono.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Esta jornada no se envió: tu campaña Verano 2027 empieza el 01/12. '
          'No se borró nada; queda guardada en este teléfono.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin el nombre ni la fecha de la campaña dice «tu campaña todavía no empezó»', (
      tester,
    ) async {
      final m = _Mundo(campanias: null, rechazadas: [_rechazada('j-1', visitas: 2)]);
      await _montar(tester, m);

      expect(
        find.text(
          'Esta jornada y sus 2 visitas no se enviaron: tu campaña todavía no empezó. '
          'No se borró nada; quedan guardadas en este teléfono.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con la campaña ya empezada (la jornada era de antes) dice cuándo empezó', (
      tester,
    ) async {
      final m = _Mundo(campanias: [_porEmpezar()], rechazadas: [_rechazada('j-1', visitas: 2)])
        ..ahora = DateTime.utc(2026, 12, 3, 15);
      await _montar(tester, m);

      expect(
        find.text(
          'Esta jornada y sus 2 visitas no se enviaron: tu campaña Verano 2027 empezó el 01/12. '
          'No se borró nada; quedan guardadas en este teléfono.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('el aviso no frena nada: con la campaña en curso se inicia la jornada de hoy', (
      tester,
    ) async {
      final m = _Mundo(campanias: [_enCurso()], rechazadas: [_rechazada('j-1', visitas: 1)]);
      await _montar(tester, m);

      expect(_textoRechazada('j-1'), findsOneWidget);
      await _tocarIniciar(tester);

      expect(m.jornadas.jornadas, hasLength(1));
      // La jornada nueva está en curso y el aviso de la vieja sigue a la vista.
      expect(find.text('Jornada activa'), findsOneWidget);
      expect(_textoRechazada('j-1'), findsOneWidget);
    });

    testWidgets('dos jornadas rechazadas: un aviso por cada una', (tester) async {
      final m = _Mundo(
        campanias: [_porEmpezar()],
        rechazadas: [_rechazada('j-1', visitas: 2), _rechazada('j-2', visitas: 5)],
      );
      await _montar(tester, m);

      expect(_textoRechazada('j-1'), findsOneWidget);
      expect(_textoRechazada('j-2'), findsOneWidget);
    });

    testWidgets('el motor rechaza una jornada con la pantalla abierta: el aviso aparece solo', (
      tester,
    ) async {
      final m = _Mundo(campanias: [_porEmpezar()]);
      await _montar(tester, m);
      expect(_textoRechazada('j-1'), findsNothing);

      m.rechazadas.publicar([_rechazada('j-1', visitas: 3)]);
      await _asentar(tester);

      expect(_textoRechazada('j-1'), findsOneWidget);
    });

    testWidgets('con muchas visitas y letra al 200 % se lee entero y no desborda', (tester) async {
      final m = _Mundo(
        campanias: [_porEmpezar(nombre: 'Campaña especial de invierno para estudiantes 2027')],
        rechazadas: [_rechazada('j-1', visitas: 1250)],
      );
      await _montar(tester, m, escala: 2);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('sus 1250 visitas'), findsOneWidget);
    });
  });
}
