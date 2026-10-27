// HU-VIS-005, vista 39, #475: la visita que se guarda desde la hoja de la casa («No contestó»,
// «Rechazo» y «Cobranza») lleva el `jornada_id` de la jornada abierta de la colportora, si tiene una;
// si no, va sin jornada (no se inventa). Se lee al guardar, no al abrir la hoja.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';
import 'registrar_visita_arnes.dart';

const _guardadoNoContesto = 'Guardado. Grecia 3307 quedó como «No contestó».';
const _noPudimosGuardar = 'No pudimos guardar la visita. Probá de nuevo.';

final _pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');

JornadaModel _jornada(String id, {String colportorId = 'col-1', DateTime? fin}) {
  final inicio = DateTime.utc(2026, 10, 25, 12);
  return JornadaModel(
    id: id,
    colportorId: colportorId,
    inicio: inicio,
    fin: fin,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: colportorId),
  );
}

/// Las jornadas locales con una llave: mientras [fallaLaLectura], leer la jornada activa lanza.
final class _JornadasConLlave implements JornadaLocalDataSource {
  _JornadasConLlave(this._dentro);

  final JornadaLocalDataSourceEnMemoria _dentro;
  var fallaLaLectura = false;
  var lecturas = 0;

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    lecturas++;
    if (fallaLaLectura) throw StateError('la base no responde');
    return _dentro.obtenerActiva(colportorId);
  }

  @override
  Future<void> insertar(JornadaModel jornada) => _dentro.insertar(jornada);

  @override
  Future<void> finalizar(JornadaModel jornada) => _dentro.finalizar(jornada);

  @override
  Future<JornadaModel?> siguienteA({required String colportorId, required DateTime inicio}) =>
      _dentro.siguienteA(colportorId: colportorId, inicio: inicio);
}

Finder get _hoja => find.byKey(ClavesQuePaso.hoja);

void main() {
  group('la visita lleva la jornada abierta', () {
    testWidgets('dado una jornada abierta, cuando se toca «No contestó», la visita lleva su id', (
      tester,
    ) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await elegir(tester, OpcionQuePaso.noContesto);

      final v = a.repo.recibidas.single.visita;
      expect(v.tipoResultado, TipoResultadoVisita.noContesto);
      expect(v.jornadaId, 'jor-1');
      expect(a.resultados, [true]);
      expect(find.text(_guardadoNoContesto), findsOneWidget);
    });

    testWidgets('dado una jornada abierta, cuando se toca «Rechazo», la visita lleva su id', (
      tester,
    ) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await elegir(tester, OpcionQuePaso.rechazo);

      final v = a.repo.recibidas.single.visita;
      expect(v.tipoResultado, TipoResultadoVisita.rechazo);
      expect(v.jornadaId, 'jor-1');
    });

    testWidgets('dado una jornada abierta y un cobro hecho, cuando se guarda la «Cobranza», la '
        'visita lleva su id', (tester) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
      final a = await montarQuePaso(
        tester,
        personas: [_pedro],
        saldos: {'pedro': 120000},
        cobrar: true,
        jornadas: jornadas,
      );

      await elegir(tester, OpcionQuePaso.cobranza);

      final v = a.repo.recibidas.single.visita;
      expect(v.tipoResultado, TipoResultadoVisita.cobranza);
      expect(v.jornadaId, 'jor-1');
      expect(a.resultados, [true]);
    });
  });

  group('sin jornada abierta la visita va sin jornada', () {
    testWidgets(
      'dado que no hay ninguna jornada, cuando se toca «No contestó», la visita se guarda '
      'sin jornada',
      (tester) async {
        final a = await montarQuePaso(tester);

        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.repo.recibidas.single.visita.jornadaId, isNull);
        expect(a.resultados, [true]);
        expect(find.text(_guardadoNoContesto), findsOneWidget);
      },
    );

    testWidgets('dado que la única jornada ya está cerrada, cuando se toca «Rechazo», la visita va '
        'sin jornada', (tester) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(
        iniciales: [_jornada('jor-1', fin: DateTime.utc(2026, 10, 25, 18))],
      );
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await elegir(tester, OpcionQuePaso.rechazo);

      expect(a.repo.recibidas.single.visita.jornadaId, isNull);
    });

    testWidgets(
      'dado la jornada abierta de OTRA persona, cuando se toca «No contestó», la visita va '
      'sin jornada',
      (tester) async {
        final jornadas = JornadaLocalDataSourceEnMemoria(
          iniciales: [_jornada('jor-ajena', colportorId: 'otra')],
        );
        final a = await montarQuePaso(tester, jornadas: jornadas);

        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.repo.recibidas.single.visita.jornadaId, isNull);
      },
    );

    testWidgets('dado que no hay jornada y un cobro hecho, cuando se guarda la «Cobranza», la '
        'visita va sin jornada', (tester) async {
      final a = await montarQuePaso(
        tester,
        personas: [_pedro],
        saldos: {'pedro': 120000},
        cobrar: true,
      );

      await elegir(tester, OpcionQuePaso.cobranza);

      expect(a.repo.recibidas.single.visita.jornadaId, isNull);
      expect(a.resultados, [true]);
    });
  });

  group('la jornada se lee al guardar', () {
    testWidgets(
      'dado que la jornada se inicia con la hoja abierta, cuando se toca «No contestó», la '
      'visita lleva la jornada nueva',
      (tester) async {
        final jornadas = JornadaLocalDataSourceEnMemoria();
        final a = await montarQuePaso(tester, jornadas: jornadas);

        await jornadas.insertar(_jornada('jor-nueva'));
        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.repo.recibidas.single.visita.jornadaId, 'jor-nueva');
      },
    );

    testWidgets('dado que la jornada se cierra con la hoja abierta, cuando se toca «Rechazo», la '
        'visita va sin jornada (no se ata a una que ya terminó)', (tester) async {
      final abierta = _jornada('jor-1');
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [abierta]);
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await jornadas.finalizar(
        JornadaModel.fromEntity(
          abierta.finalizada(
            fin: DateTime.utc(2026, 10, 25, 18),
            actualizadaEn: DateTime.utc(2026, 10, 25, 18),
          ),
        ),
      );
      await elegir(tester, OpcionQuePaso.rechazo);

      expect(a.repo.recibidas.single.visita.jornadaId, isNull);
    });
  });

  group('casos límite', () {
    testWidgets('dado que no se puede leer la jornada, cuando se toca «No contestó», la visita se '
        'guarda igual, sin jornada, y la hoja no queda trabada', (tester) async {
      final jornadas = _JornadasConLlave(
        JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]),
      )..fallaLaLectura = true;
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(jornadas.lecturas, 1);
      expect(a.repo.recibidas.single.visita.jornadaId, isNull);
      expect(a.resultados, [true]);
      expect(_hoja, findsNothing);
      expect(find.text(_guardadoNoContesto), findsOneWidget);
      expect(find.text(_noPudimosGuardar), findsNothing);
    });

    testWidgets(
      'dado que se cobró, la lectura de la jornada falla y el guardado también, cuando se '
      'reintenta con la base de vuelta, el cobro no se repite y la visita lleva la jornada',
      (tester) async {
        final jornadas = _JornadasConLlave(
          JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]),
        )..fallaLaLectura = true;
        final repo = AgendaRepositorioFalso()
          ..resultados.add(const FailureInesperado(causa: 'StateError'));
        final a = await montarQuePaso(
          tester,
          repo: repo,
          personas: [_pedro],
          saldos: {'pedro': 120000},
          cobrar: true,
          jornadas: jornadas,
        );

        await elegir(tester, OpcionQuePaso.cobranza);

        expect(find.text(_noPudimosGuardar), findsOneWidget);
        expect(_hoja, findsOneWidget);
        expect(a.enganches.cobros, hasLength(1));

        jornadas.fallaLaLectura = false;
        await elegir(tester, OpcionQuePaso.cobranza);

        expect(a.enganches.cobros, hasLength(1), reason: 'el cobro ya estaba hecho');
        expect(a.repo.recibidas.map((r) => r.visita.id), ['id-1', 'id-1'], reason: 'mismos ids');
        expect(a.repo.recibidas.first.visita.jornadaId, isNull);
        expect(a.repo.recibidas.last.visita.jornadaId, 'jor-1');
        expect(a.resultados, [true]);
      },
    );

    testWidgets('dado un doble toque, cuando termina de guardar, hay una sola visita y lleva la '
        'jornada', (tester) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await tester.tap(renglon(OpcionQuePaso.noContesto));
      await tester.tap(renglon(OpcionQuePaso.noContesto), warnIfMissed: false);
      await asentar(tester);

      expect(a.repo.recibidas, hasLength(1));
      expect(a.repo.recibidas.single.visita.jornadaId, 'jor-1');
    });

    testWidgets('dado una falla al guardar con jornada abierta, cuando se reintenta, los renglones '
        'vuelven a poder tocarse y el reintento lleva la misma jornada', (tester) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
      final repo = AgendaRepositorioFalso()
        ..resultados.add(const FailureInesperado(causa: 'StateError'));
      final a = await montarQuePaso(tester, repo: repo, jornadas: jornadas);

      await elegir(tester, OpcionQuePaso.rechazo);

      expect(find.text(_noPudimosGuardar), findsOneWidget);
      expect(find.text('Guardando…'), findsNothing);

      await elegir(tester, OpcionQuePaso.rechazo);

      expect(a.repo.recibidas.map((r) => r.visita.jornadaId), ['jor-1', 'jor-1']);
      expect(a.repo.recibidas.map((r) => r.visita.id), ['id-1', 'id-1']);
      expect(a.resultados, [true]);
    });

    testWidgets('dado que se guardó una visita y se vuelve a abrir la hoja, cuando se guarda otra, '
        'las dos llevan la jornada abierta', (tester) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
      final a = await montarQuePaso(tester, jornadas: jornadas);

      await elegir(tester, OpcionQuePaso.noContesto);
      await abrirQuePaso(tester);
      await elegir(tester, OpcionQuePaso.rechazo);

      expect(a.repo.recibidas.map((r) => r.visita.jornadaId), ['jor-1', 'jor-1']);
      expect(a.repo.recibidas.map((r) => r.visita.tipoResultado), [
        TipoResultadoVisita.noContesto,
        TipoResultadoVisita.rechazo,
      ]);
    });

    testWidgets(
      'dado el texto al 200 %, cuando se guarda con jornada abierta, la visita la lleva',
      (tester) async {
        final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_jornada('jor-1')]);
        final a = await montarQuePaso(
          tester,
          jornadas: jornadas,
          escala: 2,
          tamano: const Size(320, 568),
        );

        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.repo.recibidas.single.visita.jornadaId, 'jor-1');
      },
    );
  });
}
