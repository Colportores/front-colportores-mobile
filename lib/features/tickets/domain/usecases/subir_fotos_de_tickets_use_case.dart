import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/ticket_repository.dart';
import '../services/puertos_de_fotos.dart';

/// Lo que pasó al correr la cola de subida de fotos.
final class ResumenDeSubidaDeFotos extends Equatable {
  const ResumenDeSubidaDeFotos({this.subidas = 0, this.pendientes = 0, this.rechazadas = 0});

  /// Fotos que quedaron en el bucket en esta pasada.
  final int subidas;

  /// Fotos que siguen esperando (sin red, sin sesión, servidor caído): se reintenta en la próxima.
  final int pendientes;

  /// Fotos que el servidor rechazó y no se reintentan (más de 2 MiB, tipo que no acepta).
  final int rechazadas;

  @override
  List<Object?> get props => [subidas, pendientes, rechazadas];
}

/// HU-COB-007, «Subida exitosa» y «Edge: sin red»: sube las fotos de los tickets que esperan.
///
/// Una foto sube cuando el ticket **ya llegó al servidor** (el motor subió su fila y volvió con
/// `sync_version`) y la copia local sigue ahí: primero la fila, después la foto. Sin red no pasa
/// nada: la foto queda pendiente y el cobro, con «ticket pendiente», hasta la próxima pasada.
///
/// Por cada foto: pide el enlace firmado a `foto-ticket`, la sube, y guarda la ruta en
/// `ticket.url_cloud` (un `update` que sube por el motor). Un fallo de una foto no frena las demás.
/// Si el servidor ya tenía la foto (`409`), se toma como subida. Es idempotente: correrlo dos veces
/// seguidas no sube dos veces (la segunda ya no la ve pendiente).
final class SubirFotosDeTicketsUseCase implements UseCase<ResumenDeSubidaDeFotos, NoParams> {
  SubirFotosDeTicketsUseCase(this._repository, this._servidor);

  final TicketRepository _repository;
  final ServidorDeFotosDeTicket _servidor;

  /// Una pasada a la vez: dos disparadores juntos (volvió la red y se abrió la app) no suben la
  /// misma foto dos veces.
  bool _corriendo = false;

  @override
  Future<Either<Failure, ResumenDeSubidaDeFotos>> call(NoParams params) async {
    if (_corriendo) return const Right(ResumenDeSubidaDeFotos());
    _corriendo = true;
    try {
      final lista = await _repository.fotosPorSubir();
      if (lista.isLeft()) return lista.map((_) => const ResumenDeSubidaDeFotos());
      final porSubir = lista.getOrElse(() => const []);

      var subidas = 0;
      var pendientes = 0;
      var rechazadas = 0;
      for (final item in porSubir) {
        final id = item.ticket.id;
        final bytes = (await _repository.bytesDeLaFoto(id)).getOrElse(() => null);
        if (bytes == null) {
          // La copia local no está: no hay nada que subir. Se anota para que no quede mudo.
          await _repository.anotarIntentoFallido(
            id,
            codigo: 'copia_local_ausente',
            definitivo: true,
          );
          rechazadas++;
          continue;
        }
        final resultado = await _servidor.subir(
          ticketId: id,
          tipo: item.foto.tipoDeImagen,
          bytes: bytes,
        );
        switch (resultado) {
          case FotoSubida(:final ruta) || FotoYaEstaba(:final ruta):
            final marcada = await _repository.marcarFotoSubida(id, ruta);
            if (marcada.isRight()) {
              subidas++;
            } else {
              pendientes++;
            }
          case SubidaFallida(:final codigo, :final reintentable):
            await _repository.anotarIntentoFallido(id, codigo: codigo, definitivo: !reintentable);
            if (reintentable) {
              pendientes++;
            } else {
              rechazadas++;
            }
        }
      }
      return Right(
        ResumenDeSubidaDeFotos(subidas: subidas, pendientes: pendientes, rechazadas: rechazadas),
      );
    } finally {
      _corriendo = false;
    }
  }
}
