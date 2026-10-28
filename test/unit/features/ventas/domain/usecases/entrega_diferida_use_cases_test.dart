// «Entrega diferida» y «Cumplir entrega pendiente» (HU-VEN-003, #433): qué valida el caso de uso sin
// guardar nada, qué le pide al repositorio y qué hace con el recordatorio de la cita.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/cumplir_entrega_use_case.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/diferir_entrega_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/entrega_falsos.dart';

void main() {
  late EntregasEnMemoria repo;
  late RecordatoriosEnMemoria recordatorios;
  late DiferirEntregaUseCase diferir;
  late CumplirEntregaUseCase cumplir;
  // Miércoles 28/10, 12:00 en Montevideo (UTC-3) = 15:00 UTC.
  final ahora = DateTime.utc(2026, 10, 28, 15);
  final sabado = DateTime.utc(2026, 10, 31, 13);
  final lunes = DateTime.utc(2026, 11, 2, 13);
  var ids = 0;

  EntregaDiferida diferida({DateTime? cuando, bool yaEstaba = false}) => EntregaDiferida(
    entregas: [entregaDe('e-1', 'p-1', pendiente: true, fechaPrevista: cuando ?? sabado)],
    cita: agendaDe(
      'c-1',
      tipo: TipoAgenda.entrega,
      ventaId: 'v-1',
      entregaId: 'e-1',
      fecha: cuando ?? sabado,
    ),
    direccion: 'Grecia 3310',
    yaEstaba: yaEstaba,
  );

  setUp(() {
    repo = EntregasEnMemoria()..respuestaDeDiferir = diferida();
    recordatorios = RecordatoriosEnMemoria();
    ids = 0;
    diferir = DiferirEntregaUseCase(
      repo,
      recordatorios,
      generarId: () => 'id-${++ids}',
      ahora: () => ahora,
    );
    cumplir = CumplirEntregaUseCase(
      repo,
      recordatorios,
      generarId: () => 'id-${++ids}',
      ahora: () => ahora,
    );
  });

  DiferirEntregaParams params({
    DateTime? fecha,
    String venta = 'v-1',
    String colportor = 'col-1',
    List<ComponenteVendido> productos = const [ComponenteVendido(productoId: 'p-1')],
  }) => DiferirEntregaParams(
    ventaId: venta,
    colportorId: colportor,
    fechaPrevista: fecha ?? sabado,
    productos: productos,
  );

  Failure? falla(Either<Failure, Object?> r) => r.fold((f) => f, (_) => null);

  group('diferir', () {
    test('arma una fila pendiente por producto con la fecha prevista y agenda el aviso', () async {
      final r = await diferir(
        params(
          productos: const [
            ComponenteVendido(productoId: 'p-1'),
            ComponenteVendido(productoId: 'p-2', cantidad: 3),
          ],
        ),
      );

      expect(r.isRight(), isTrue);
      final llamada = repo.diferidas.single;
      expect(llamada.fechaPrevista, sabado);
      expect(
        llamada.filasNuevas.map(
          (f) => [f.id, f.productoId, f.cantidad, f.pendiente, f.fechaPrevista, f.fechaEntrega],
        ),
        [
          ['id-1', 'p-1', 1, true, sabado, null],
          ['id-2', 'p-2', 3, true, sabado, null],
        ],
      );
      expect(llamada.filasNuevas.first.auditoria.createdBy, 'col-1');
      expect(llamada.idDeLaCita, 'id-3');
      expect(recordatorios.llamadas, ['programar:c-1']);
      final aviso = recordatorios.programados['c-1']!;
      expect(
        [aviso.tipo, aviso.direccion, aviso.fechaProgramada],
        [TipoAgenda.entrega, 'Grecia 3310', sabado],
      );
    });

    test('el mismo producto en varias filas es una sola con la suma', () async {
      await diferir(
        params(
          productos: const [
            ComponenteVendido(productoId: 'p-1'),
            ComponenteVendido(productoId: 'p-1', cantidad: 2),
          ],
        ),
      );

      expect(repo.diferidas.single.filasNuevas.map((f) => f.cantidad), [3]);
    });

    test(
      'sin productos (Poner fecha a lo que ya estaba) pide al repositorio sin filas nuevas',
      () async {
        await diferir(params(productos: const []));

        expect(repo.diferidas.single.filasNuevas, isEmpty);
        expect(recordatorios.llamadas, ['programar:c-1']);
      },
    );

    test('una fecha de un día que ya pasó no guarda nada ni avisa', () async {
      final r = await diferir(params(fecha: DateTime.utc(2026, 10, 27, 20)));

      expect((falla(r)! as FailureValidacion).campos['fecha'], DiferirEntregaUseCase.fechaPasada);
      expect(repo.diferidas, isEmpty);
      expect(recordatorios.llamadas, isEmpty);
    });

    test('hoy vale: más tarde, con aviso', () async {
      repo.respuestaDeDiferir = diferida(cuando: DateTime.utc(2026, 10, 28, 20));

      final r = await diferir(params(fecha: DateTime.utc(2026, 10, 28, 20)));

      expect(r.isRight(), isTrue);
      expect(recordatorios.llamadas, ['programar:c-1']);
    });

    test(
      'hoy, pero a una hora que ya pasó: se agenda sin aviso y se saca el que hubiera',
      () async {
        repo.respuestaDeDiferir = diferida(cuando: DateTime.utc(2026, 10, 28, 13));

        final r = await diferir(params(fecha: DateTime.utc(2026, 10, 28, 13)));

        expect(r.isRight(), isTrue);
        expect(r.getOrElse(() => throw StateError('x')).recordatorio, isNull);
        expect(recordatorios.llamadas, ['cancelar:c-1']);
      },
    );

    test('sin venta, sin colportor o con una cantidad inválida no guarda nada', () async {
      final r = await diferir(
        params(
          venta: ' ',
          colportor: '',
          productos: const [ComponenteVendido(productoId: 'p-1', cantidad: 0)],
        ),
      );

      expect((falla(r)! as FailureValidacion).campos.keys, ['venta', 'colportorId', 'productos']);
      expect(repo.diferidas, isEmpty);
    });

    test('si no se pudo guardar, devuelve la falla y no toca el aviso', () async {
      repo.fallasAlDiferir.add(const FailureEntregaNoGuardada());

      final r = await diferir(params());

      expect(falla(r), isA<FailureEntregaNoGuardada>());
      expect(recordatorios.llamadas, isEmpty);
    });

    test(
      'falla a mitad: el reintento vuelve a guardar y programa el aviso (nada quedó trabado)',
      () async {
        repo.fallasAlDiferir.add(const FailureEntregaNoGuardada());

        final primera = await diferir(params());
        final segunda = await diferir(params());

        expect(primera.isLeft(), isTrue);
        expect(segunda.isRight(), isTrue);
        expect(repo.diferidas, hasLength(2));
        expect(recordatorios.llamadas, ['programar:c-1']);
      },
    );

    test('el aviso sin permiso no deshace la entrega: se informa en el resultado', () async {
      recordatorios.permisoConcedido = false;

      final r = (await diferir(params())).getOrElse(() => throw StateError('x'));

      expect(r.recordatorio, ResultadoRecordatorio.sinPermiso);
      expect(r.entrega.cita.id, 'c-1');
    });

    test('si el plugin de avisos revienta, la entrega ya guardada se conserva', () async {
      final r = await DiferirEntregaUseCase(
        repo,
        _RecordatoriosQueFallan(),
        generarId: () => 'x',
        ahora: () => ahora,
      )(params());

      expect(r.getOrElse(() => throw StateError('x')).recordatorio, ResultadoRecordatorio.noSePudo);
    });

    test(
      'dos fechas seguidas: cada una llega al repositorio, en orden, y el aviso queda en la última',
      () async {
        repo.respuestaDeDiferir = diferida();
        await diferir(params());
        repo.respuestaDeDiferir = diferida(cuando: lunes);
        await diferir(params(fecha: lunes));

        expect(repo.diferidas.map((d) => d.fechaPrevista), [sabado, lunes]);
        expect(recordatorios.programados['c-1']!.fechaProgramada, lunes);
      },
    );
  });

  group('cumplir', () {
    EntregaCumplida cumplida({
      bool citaCumplida = true,
      bool conFechaNueva = false,
      bool hayCita = true,
    }) => EntregaCumplida(
      entregas: [entregaDe('e-1', 'p-1')],
      entregadas: [entregaDe('e-1', 'p-1')],
      cita: hayCita
          ? agendaDe(
              'c-1',
              tipo: TipoAgenda.entrega,
              ventaId: 'v-1',
              entregaId: 'e-1',
              fecha: lunes,
            )
          : null,
      citaCumplida: citaCumplida,
      citaConFechaNueva: conFechaNueva,
      direccion: 'Grecia 3310',
    );

    test(
      '«Entregado hoy» pide todo lo pendiente con la hora de ahora y saca el aviso de la cita',
      () async {
        repo.respuestaDeCumplir = cumplida();
        await recordatorios.programar(_aviso('c-1', sabado));
        recordatorios.llamadas.clear();

        final r = await cumplir(const CumplirEntregaParams(ventaId: 'v-1'));

        expect(r.isRight(), isTrue);
        final llamada = repo.cumplidas.single;
        expect([llamada.ventaId, llamada.entregaIds, llamada.nuevaFecha], ['v-1', null, null]);
        expect(recordatorios.llamadas, ['cancelar:c-1']);
        expect(recordatorios.programados, isEmpty);
        expect(r.getOrElse(() => throw StateError('x')).recordatorioCancelado, isTrue);
      },
    );

    test('parcial con fecha nueva: reprograma el aviso a la fecha nueva', () async {
      repo.respuestaDeCumplir = cumplida(citaCumplida: false, conFechaNueva: true);

      final r = await cumplir(
        CumplirEntregaParams(ventaId: 'v-1', entregaIds: const {'e-1'}, nuevaFecha: lunes),
      );

      expect(r.isRight(), isTrue);
      expect(repo.cumplidas.single.entregaIds, {'e-1'});
      expect(repo.cumplidas.single.nuevaFecha, lunes);
      expect(recordatorios.programados['c-1']!.fechaProgramada, lunes);
    });

    test('sin cita (la entrega salió de una inmediata) no toca ningún aviso', () async {
      repo.respuestaDeCumplir = cumplida(hayCita: false, citaCumplida: false);

      final r = await cumplir(const CumplirEntregaParams(ventaId: 'v-1'));

      expect(r.isRight(), isTrue);
      expect(recordatorios.llamadas, isEmpty);
    });

    test('una fecha nueva de un día que ya pasó, o ningún producto, no guarda nada', () async {
      final fecha = await cumplir(
        CumplirEntregaParams(ventaId: 'v-1', nuevaFecha: DateTime.utc(2026, 10, 1)),
      );
      final vacio = await cumplir(const CumplirEntregaParams(ventaId: 'v-1', entregaIds: {}));

      expect((falla(fecha)! as FailureValidacion).campos.keys, ['fecha']);
      expect(
        (falla(vacio)! as FailureValidacion).campos['productos'],
        CumplirEntregaUseCase.sinProductos,
      );
      expect(repo.cumplidas, isEmpty);
    });

    test('si no se pudo guardar, el aviso sigue como estaba', () async {
      await recordatorios.programar(_aviso('c-1', sabado));
      recordatorios.llamadas.clear();
      repo.fallasAlCumplir.add(const FailureEntregaNoGuardada());

      final r = await cumplir(const CumplirEntregaParams(ventaId: 'v-1'));

      expect(r.isLeft(), isTrue);
      expect(recordatorios.llamadas, isEmpty);
      expect(recordatorios.programados.keys, ['c-1']);
    });

    test('un aviso que no se puede sacar no deshace la entrega: se informa', () async {
      repo.respuestaDeCumplir = cumplida();
      recordatorios.puedeCancelar = false;

      final r = (await cumplir(
        const CumplirEntregaParams(ventaId: 'v-1'),
      )).getOrElse(() => throw StateError('x'));

      expect(r.recordatorioCancelado, isFalse);
    });

    test(
      'dos toques seguidos llegan al repositorio, que es el que los hace idempotentes',
      () async {
        repo.respuestaDeCumplir = cumplida();

        final a = cumplir(const CumplirEntregaParams(ventaId: 'v-1'));
        final b = cumplir(const CumplirEntregaParams(ventaId: 'v-1'));
        await Future.wait([a, b]);

        expect(repo.cumplidas, hasLength(2));
        expect(repo.cumplidas.map((c) => c.idDeLaCita).toSet(), hasLength(2));
      },
    );
  });
}

RecordatorioDeVisita _aviso(String agendaId, DateTime cuando) => RecordatorioDeVisita(
  agendaId: agendaId,
  tipo: TipoAgenda.entrega,
  direccion: 'Grecia 3310',
  fechaProgramada: cuando,
);

/// Un puerto de avisos que revienta, como un plugin roto: la entrega no se puede perder por eso.
final class _RecordatoriosQueFallan implements Recordatorios {
  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) =>
      throw StateError('plugin roto');

  @override
  Future<bool> cancelar(String agendaId) => throw StateError('plugin roto');

  @override
  Future<bool> puedeAvisar() async => true;
}
