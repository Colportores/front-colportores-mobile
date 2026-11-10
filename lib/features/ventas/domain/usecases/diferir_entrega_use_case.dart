import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/domain/services/recordatorios.dart';
import '../entities/componente_vendido.dart';
import '../entities/entrega.dart';
import '../entities/entrega_diferida.dart';
import '../repositories/entrega_repository.dart';

/// Parámetros de [DiferirEntregaUseCase].
final class DiferirEntregaParams extends Equatable {
  const DiferirEntregaParams({
    required this.ventaId,
    required this.colportorId,
    required this.fechaPrevista,
    this.productos = const [],
  });

  final String ventaId;

  /// Quién entrega: el `created_by` de las filas.
  final String colportorId;

  /// Cuándo se acordó entregar: el día y la hora de la cita (hora local). La hora es de quien llama:
  /// con ella suena el aviso.
  final DateTime fechaPrevista;

  /// Lo que se vendió y queda para esa fecha, **solo si la venta todavía no tiene filas de entrega**
  /// («Entrega en otra fecha» recién vendido). Si ya las tiene (una entrega inmediata que dejó algo
  /// pendiente, 27C·02 «Poner fecha»), se pone la fecha a lo pendiente y esto no se usa.
  final List<ComponenteVendido> productos;

  @override
  List<Object?> get props => [ventaId, colportorId, fechaPrevista, productos];
}

/// Lo que devuelve [DiferirEntregaUseCase]: la entrega guardada y qué pasó con el aviso de la cita.
final class ResultadoDiferirEntrega extends Equatable {
  const ResultadoDiferirEntrega({required this.entrega, required this.recordatorio});

  final EntregaDiferida entrega;

  /// Qué pasó con el recordatorio. `null`: no se intentó, porque la hora de la cita ya pasó (hoy,
  /// más temprano): la entrega queda agendada, sin aviso.
  final ResultadoRecordatorio? recordatorio;

  @override
  List<Object?> get props => [entrega, recordatorio];
}

/// HU-VEN-003, «Entrega diferida»: deja lo que falta entregar de una venta para otra fecha, sin
/// pantalla.
///
/// 1. Valida y **no guarda nada** si algo está mal: la fecha no puede ser de un día que ya pasó
///    (hoy vale) y, si hay productos, cantidades de 1 o más.
/// 2. Guarda, en **una transacción local** (el repositorio): las filas de `entrega` pendientes con la
///    `fecha_prevista` (`estado = PENDIENTE`), la cita `ENTREGA` de la agenda con la venta y la
///    entrega que la originan, sus jobs de sync y el color de la casa (entrega y cobranza
///    pendientes, prioridad 1).
/// 3. Programa el recordatorio de la cita, salvo que su hora ya haya pasado. Va **después** de la
///    transacción y nunca hace fallar el guardado: lo que pasó va en
///    [ResultadoDiferirEntrega.recordatorio].
///
/// Es idempotente: repetir la misma fecha no escribe nada, y una fecha distinta **mueve** la cita que
/// ya había (nunca hay dos citas vivas de la misma venta). Todo es local: sin red se completa.
final class DiferirEntregaUseCase
    implements UseCase<ResultadoDiferirEntrega, DiferirEntregaParams> {
  DiferirEntregaUseCase(
    this._repository,
    this._recordatorios, {
    required this._generarId,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final EntregaRepository _repository;
  final Recordatorios _recordatorios;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Lo más que se puede entregar de un producto (igual que lo más que se vende de una línea).
  static const maximoPorProducto = 99999;

  /// La fecha prevista es de un día que ya pasó. Texto a confirmar: dice qué pasa y qué hacer, con
  /// las palabras de «Elegí hoy o un día más adelante» del servidor para las cuotas.
  static const fechaPasada = 'Esa fecha ya pasó. Elegí hoy o un día más adelante.';

  @override
  Future<Either<Failure, ResultadoDiferirEntrega>> call(DiferirEntregaParams params) async {
    final ventaId = params.ventaId.trim();
    final colportorId = params.colportorId.trim();
    final ahora = _ahora();
    final productos = _sumar(params.productos);

    final campos = <String, String>{
      if (ventaId.isEmpty) 'venta': 'Falta la venta que se entrega.',
      if (colportorId.isEmpty) 'colportorId': 'No hay un colportor para guardar la entrega.',
      if (esDiaPasado(params.fechaPrevista, ahora)) 'fecha': fechaPasada,
      if (productos.values.any((c) => c < 1 || c > maximoPorProducto))
        'productos': 'La cantidad de un producto no es válida.',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final filasNuevas = [
      for (final MapEntry(:key, :value) in productos.entries)
        Entrega(
          id: _generarId(),
          ventaId: ventaId,
          productoId: key,
          cantidad: value,
          pendiente: true,
          fechaPrevista: params.fechaPrevista,
          auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId),
        ),
    ];
    final guardada = await _repository.diferir(
      ventaId,
      fechaPrevista: params.fechaPrevista,
      ahora: ahora,
      filasNuevas: filasNuevas,
      idDeLaCita: _generarId(),
    );
    return guardada.fold(
      (falla) async => Left<Failure, ResultadoDiferirEntrega>(falla),
      (entrega) async => Right(
        ResultadoDiferirEntrega(entrega: entrega, recordatorio: await _programar(entrega, ahora)),
      ),
    );
  }

  /// La fecha cae en un día anterior a hoy (hora local). Hoy, a cualquier hora, vale.
  static bool esDiaPasado(DateTime fecha, DateTime ahora) {
    final dia = fecha.toLocal();
    final hoy = ahora.toLocal();
    return DateTime(dia.year, dia.month, dia.day).isBefore(DateTime(hoy.year, hoy.month, hoy.day));
  }

  Future<ResultadoRecordatorio?> _programar(EntregaDiferida entrega, DateTime ahora) async {
    final cita = entrega.cita;
    try {
      if (cita.fechaProgramada.isBefore(_alMinuto(ahora))) {
        // Hoy, pero la hora ya pasó: sin aviso, y el que hubiera de antes no tiene que sonar.
        await _recordatorios.cancelar(cita.id);
        return null;
      }
      return await _recordatorios.programar(
        RecordatorioDeVisita(
          agendaId: cita.id,
          tipo: cita.tipo,
          direccion: entrega.direccion,
          fechaProgramada: cita.fechaProgramada,
        ),
      );
    } on Object catch (e) {
      // El puerto no lanza; si lo hiciera, la entrega ya está guardada y no se pierde por eso. Nada de
      // la dirección al log (convenciones §7.5).
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREGA_RECORDATORIO',
        'no se pudo programar el recordatorio de la entrega',
        {'agenda_id': cita.id, 'error': e.runtimeType.toString()},
      );
      return ResultadoRecordatorio.noSePudo;
    }
  }

  /// Una cantidad por producto, en el orden en que aparecen.
  static Map<String, int> _sumar(List<ComponenteVendido> componentes) {
    final suma = <String, int>{};
    for (final c in componentes) {
      suma[c.productoId] = (suma[c.productoId] ?? 0) + c.cantidad;
    }
    return suma;
  }

  /// [t] sin los segundos (la hora se elige al minuto): elegir el minuto en curso no es «pasada».
  static DateTime _alMinuto(DateTime t) => t.subtract(
    Duration(seconds: t.second, milliseconds: t.millisecond, microseconds: t.microsecond),
  );
}
