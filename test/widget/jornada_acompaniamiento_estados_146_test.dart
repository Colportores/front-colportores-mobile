// Los estados de «¿Te acompañó alguien?» que el canvas no dibuja pero la HU pide (HU-JOR-003, #146):
// cargando, error al leer y la lista que cambia mientras se elige.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/fakes/acompaniamiento_repository_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/acompaniante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/tendencia_de_la_jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/repositories/acompaniamiento_repository.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/acompaniamiento_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/widgets/seccion_acompaniamiento.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _inicio = DateTime.utc(2026, 11, 20, 11, 10);

final _jornada = Jornada(
  id: 'jor-1',
  colportorId: 'col-1',
  inicio: _inicio,
  auditoria: Auditoria(createdAt: _inicio, updatedAt: _inicio, createdBy: 'col-1'),
);

/// Un acompañamiento cuyas lecturas se programan: la lista tarda o falla, y lo guardado falla al leer.
final class _Programable implements AcompaniamientoRepository {
  final lista = StreamController<List<CoordinadorDeCampania>>.broadcast();
  bool fallaLaLectura = false;
  int lecturas = 0;

  @override
  Stream<List<CoordinadorDeCampania>> observarLista({
    required String colportorId,
    Set<String>? campaniaIds,
  }) => lista.stream;

  @override
  Stream<List<Acompaniante>> observarDe(String jornadaId) {
    lecturas++;
    return fallaLaLectura ? Stream.error(StateError('no se pudo leer')) : Stream.value(const []);
  }

  @override
  Future<Either<Failure, Unit>> guardar({
    required String jornadaId,
    required String colportorId,
    required Set<String> usuarioIds,
  }) async => const Right(unit);

  @override
  Stream<TendenciaDeLaJornada?> observarTendencia({
    required String colportorId,
    required String jornadaId,
    required DateTime inicio,
    DateTime? fin,
    ({String desde, String? hasta})? campania,
  }) => Stream.value(null);
}

Future<void> _montar(WidgetTester tester, AcompaniamientoRepository repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [acompaniamientoRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: temaClaro(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SeccionAcompaniamiento(colportorId: 'col-1', jornada: _jornada),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'dado que la lista todavía se está leyendo, la hoja dice «Cargando la lista…» y no deja elegir',
    (tester) async {
      final repo = _Programable();
      addTearDown(repo.lista.close);
      await _montar(tester, repo);

      await tester.tap(find.byKey(const Key('acompaniamiento_interruptor')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Cargando la lista…'), findsOneWidget);
      expect(find.byKey(const Key('hoja_acompaniantes_listo')), findsNothing);

      repo.lista.add(const [
        CoordinadorDeCampania(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Cargando la lista…'), findsNothing);
      expect(find.byKey(const Key('acompaniante_u-marta')), findsOneWidget);
    },
  );

  testWidgets('dado que la lista falla al leer, dice qué pasó y qué hacer, y se puede cerrar', (
    tester,
  ) async {
    final repo = _Programable();
    addTearDown(repo.lista.close);
    await _montar(tester, repo);
    await tester.tap(find.byKey(const Key('acompaniamiento_interruptor')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    repo.lista.addError(StateError('base cerrada'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hoja_acompaniantes_error')), findsOneWidget);
    expect(find.textContaining('avisale a tu coordinador'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hoja_acompaniantes_cerrar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hoja_acompaniantes')), findsNothing);
  });

  testWidgets(
    'dado que no se puede leer quién acompaña, no afirma nada y «Reintentar» lo vuelve a leer',
    (tester) async {
      final repo = _Programable()..fallaLaLectura = true;
      addTearDown(repo.lista.close);
      await _montar(tester, repo);

      expect(find.byKey(const Key('acompaniamiento_error_lectura')), findsOneWidget);
      expect(find.byKey(const Key('acompaniamiento_interruptor')), findsNothing);

      repo.fallaLaLectura = false;
      await tester.tap(find.byKey(const Key('acompaniamiento_releer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('acompaniamiento_error_lectura')), findsNothing);
      expect(find.byKey(const Key('acompaniamiento_interruptor')), findsOneWidget);
    },
  );

  testWidgets(
    'dado un coordinador que deja de contar mientras la hoja está abierta, sale de la lista',
    (tester) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        lista: const [
          CoordinadorDeCampania(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez'),
          CoordinadorDeCampania(usuarioId: 'u-daniel', nombre: 'Daniel', apellido: 'Ruiz'),
        ],
      );
      await _montar(tester, repo);
      await tester.tap(find.byKey(const Key('acompaniamiento_interruptor')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acompaniante_u-daniel')), findsOneWidget);

      repo.lista = const [
        CoordinadorDeCampania(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez'),
      ];
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('acompaniante_u-daniel')), findsNothing);
      expect(find.byKey(const Key('acompaniante_u-marta')), findsOneWidget);
    },
  );
}
