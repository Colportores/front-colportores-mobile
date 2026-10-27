import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../notificaciones/domain/entities/preferencias_recordatorios.dart';
import '../../../notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/usecases/modificar_agenda_use_case.dart';
import 'agenda_providers.dart';
import 'recordatorios_providers.dart';

// Cableado del detalle y de «Modificar agenda» (vista 23, grupo C, HU-VIS-003).

/// Riverpod 3 reintenta 10 veces lo que falla: el detalle muestra el error enseguida y el «Reintentar»
/// es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// HU-VIS-003: modificar una agenda y reprogramar su recordatorio. «Modificar agenda» (23C·02) lo usa.
final modificarAgendaUseCaseProvider = Provider<ModificarAgendaUseCase>(
  (ref) => ModificarAgendaUseCase(
    ref.watch(agendaRepositoryProvider),
    ref.watch(recordatoriosProvider),
    ahora: ref.watch(relojVisitaProvider),
  ),
);

/// La agenda [agendaId] con su nota y la visita que la cerró (23C·01); `null` si ya no está en el
/// teléfono. Una falla al leer sale como error del provider; quien lo toca vuelve a leer con
/// `ref.invalidate`.
final detalleDeAgendaProvider = FutureProvider.autoDispose.family<DetalleDeAgenda?, String>((
  ref,
  agendaId,
) async {
  final lectura = await ref.watch(agendaRepositoryProvider).obtenerDetalle(agendaId);
  return lectura.fold((falla) => throw falla, (detalle) => detalle);
}, retry: _sinReintentos);

/// Las preferencias de los recordatorios (HU-NOT-004) para decir a qué hora suena el aviso en el
/// detalle. Si no se pueden leer, `null`: se muestran con los valores de fábrica.
final preferenciasDelAvisoProvider = FutureProvider.autoDispose<PreferenciasRecordatorios?>((
  ref,
) async {
  try {
    return await ref.watch(preferenciasRecordatoriosRepositoryProvider).leer();
  } on Object {
    return null;
  }
});
