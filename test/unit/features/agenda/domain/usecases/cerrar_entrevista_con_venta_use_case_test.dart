// «Sí, registrar la venta» de la entrevista (vista 39, R·06 → vista 27; HU-VIS-005, HU-VEN-001, #428):
// preparar no guarda nada, la visita `VENTA` se guarda dentro de la venta y la entrevista en curso
// se borra recién cuando la venta quedó guardada (R44).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/entrevista_en_curso_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cerrar_entrevista_con_venta_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/finalizar_entrevista_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/entrevista_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  late EntrevistaEnCursoEnMemoria memoria;
  late EntrevistaEnCursoRota almacen;
  late AgendaFalsa agenda;
  late DestinoFalso destino;
  late CerrarEntrevistaConVentaUseCase caso;

  setUp(() {
    memoria = EntrevistaEnCursoEnMemoria();
    almacen = EntrevistaEnCursoRota(memoria);
    agenda = AgendaFalsa();
    destino = DestinoFalso();
    caso = CerrarEntrevistaConVentaUseCase(
      RegistrarResultadoVisitaUseCase(
        agenda,
        generarId: () => 'x-1',
        ahora: () => ahoraEntrevista.toUtc(),
      ),
      almacen,
      destino,
      ahora: () => ahoraEntrevista,
      logger: loggerMudo(),
    );
  });

  FinalizarEntrevistaParams params({
    DateTime? entrada,
    DateTime? salida,
    String nota = '',
    String espacioId = 'esp-1',
    String espacioPersonaId = 'ep-1',
  }) => FinalizarEntrevistaParams.de(
    entrevistaDePrueba(espacioId: espacioId, espacioPersonaId: espacioPersonaId),
    entrada: entrada ?? inicioEntrevista,
    salida: salida ?? ahoraEntrevista,
    nota: nota,
  );

  Future<VentaDeLaEntrevista> preparada({String nota = ''}) async {
    await memoria.guardar(entrevistaDePrueba());
    final r = await caso.preparar(params(nota: nota));
    return r.getOrElse(() => throw StateError('debía poder prepararse'));
  }

  group('preparar', () {
    test('arma la visita VENTA con los ids de la entrevista y no guarda nada', () async {
      final venta = await preparada(nota: 'volver con la esposa');

      expect(venta.visita.resultado, TipoResultadoVisita.venta);
      expect(venta.visitaId, 'vis-1');
      expect(venta.espacioId, 'esp-1');
      expect(venta.espacioPersonaId, 'ep-1');
      expect(venta.colportorId, 'col-1');
      expect(venta.visita.nota, 'volver con la esposa');
      expect(agenda.recibidas, isEmpty);
      expect(memoria.guardadas, hasLength(1));
    });

    test('si la persona se unió a otra, la venta cuelga del vínculo y el espacio vivos', () async {
      destino.destino = const DestinoDeEntrevista(espacioId: 'esp-2', espacioPersonaId: 'ep-9');

      final venta = await preparada();

      expect(venta.espacioId, 'esp-2');
      expect(venta.espacioPersonaId, 'ep-9');
      expect(venta.visita.espacioId, 'esp-2');
    });

    test(
      'sin la casa en el teléfono devuelve un aviso que dice qué hacer y no toca nada',
      () async {
        destino.sinDestino = true;
        await memoria.guardar(entrevistaDePrueba());

        final r = await caso.preparar(params());

        expect(r.swap().getOrElse(() => throw StateError('debía fallar')), ventaSinLugar);
        expect(ventaSinLugar.mensaje, contains('cerrala con «No, guardar y volver al mapa»'));
        expect(agenda.recibidas, isEmpty);
        expect(memoria.guardadas, hasLength(1));
      },
    );

    test('sin la persona en el teléfono no hay a quién venderle', () async {
      destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');
      await memoria.guardar(entrevistaDePrueba());

      final r = await caso.preparar(params());

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), ventaSinPersona);
      expect(memoria.guardadas, hasLength(1));
    });

    test('una salida antes de la entrada no se acepta', () async {
      await memoria.guardar(entrevistaDePrueba());

      final r = await caso.preparar(params(salida: DateTime(2026, 10, 23, 14, 10)));

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), isA<FailureValidacion>());
      expect(memoria.guardadas, hasLength(1));
    });

    test('una salida que todavía no pasó no se acepta', () async {
      await memoria.guardar(entrevistaDePrueba());

      final r = await caso.preparar(params(salida: DateTime(2026, 10, 23, 15)));

      expect(r.isLeft(), isTrue);
    });

    test('sin ids de casa o de persona valida antes de leer nada', () async {
      final r = await caso.preparar(params(espacioId: ' ', espacioPersonaId: ''));

      final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
      expect(falla, isA<FailureValidacion>());
      expect(destino.consultas, isEmpty);
    });

    test('si no se puede leer dónde cuelga la venta, falla sin guardar nada', () async {
      destino.falla = true;
      await memoria.guardar(entrevistaDePrueba());

      final r = await caso.preparar(params());

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), isA<FailureInesperado>());
      expect(agenda.recibidas, isEmpty);
      expect(memoria.guardadas, hasLength(1));
    });
  });

  group('guardarVisita (dentro de la transacción de la venta)', () {
    test('guarda la visita como VENTA', () async {
      final venta = await preparada();

      await caso.guardarVisita(venta);

      expect(agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.venta);
      expect(agenda.recibidas.single.visita.id, 'vis-1');
    });

    test('si no se pudo guardar lanza, para que la venta se revierta', () async {
      final venta = await preparada();
      agenda.falla = const FailureInesperado();

      await expectLater(caso.guardarVisita(venta), throwsA(isA<VisitaDeLaVentaNoGuardada>()));
      expect(memoria.guardadas, hasLength(1), reason: 'la entrevista no se tocó');
    });

    test('el toString de la excepción no lleva datos de la persona', () async {
      final venta = await preparada(nota: 'perro suelto en lo de Pedro Gómez');
      agenda.falla = const FailureInesperado();

      try {
        await caso.guardarVisita(venta);
        fail('debía lanzar');
      } on VisitaDeLaVentaNoGuardada catch (e) {
        expect(e.toString(), isNot(contains('Pedro')));
        expect(e.toString(), isNot(contains('perro')));
      }
    });
  });

  group('soltar (después de que la venta quedó guardada)', () {
    test('borra la entrevista en curso', () async {
      final venta = await preparada();

      final r = await caso.soltar(venta);

      expect(r.isRight(), isTrue);
      expect(memoria.guardadas, isEmpty);
    });

    test('si el almacén falla devuelve la falla y no lanza', () async {
      final venta = await preparada();
      almacen.fallaAlBorrar = true;

      final r = await caso.soltar(venta);

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), isA<FailureInesperado>());
      expect(memoria.guardadas, hasLength(1));
    });

    test('un reintento lleva los mismos ids de la visita', () async {
      final venta = await preparada();

      await caso.guardarVisita(venta);
      await caso.guardarVisita(venta);

      expect(agenda.recibidas.map((r) => r.visita.id).toSet(), {'vis-1'});
    });
  });
}
