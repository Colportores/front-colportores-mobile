import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/cancelar_agenda_use_case.dart';
import 'agenda_providers.dart';
import 'recordatorios_providers.dart';

// Cableado de cancelar una agenda (HU-VIS-004, vista 23C·04 y 23C·05). El repositorio, el reloj y los
// recordatorios son los de `agenda_providers.dart` y `recordatorios_providers.dart`.

/// Cancela una agenda `PROGRAMADA`: la pasa a `CANCELADA`, recalcula el color de la casa y saca el
/// recordatorio local. Todo en el teléfono, sin conexión.
final cancelarAgendaUseCaseProvider = Provider<CancelarAgendaUseCase>(
  (ref) => CancelarAgendaUseCase(
    ref.watch(agendaRepositoryProvider),
    ref.watch(recordatoriosProvider),
    ahora: ref.watch(relojVisitaProvider),
  ),
);
