import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/ticket_repository.dart';

/// HU-COB-007, «Borrado local por usuario»: el colportor borra la copia de la foto que tiene en el
/// teléfono. La nube queda intacta (el ticket vive en el bucket hasta que la foto vence a los 4
/// meses).
///
/// **Solo si la foto ya subió.** Si todavía no subió, la copia es la única que existe: borrarla
/// perdería el ticket, y de un teléfono no se borra una venta ni su comprobante por un toque. En ese
/// caso devuelve [FailureTicketCopiaSinSubir] y no toca nada.
final class BorrarCopiaLocalDeTicketUseCase implements UseCase<Unit, String> {
  BorrarCopiaLocalDeTicketUseCase(this._repository);

  final TicketRepository _repository;

  /// [params] es el id del ticket.
  @override
  Future<Either<Failure, Unit>> call(String params) => _repository.borrarCopiaLocal(params);
}
