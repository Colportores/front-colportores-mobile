import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../auth/domain/entities/aviso_zona.dart';
import '../../../auth/presentation/providers/avisos_zona_notifier.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../../domain/services/puertos_descarga.dart';
import '../../domain/usecases/descarga_paquete_tiles_use_cases.dart';
import 'mapas_offline_providers.dart';
import 'tiles_providers.dart';

/// El mapa que se le sugiere bajar al colportor porque le asignaron una zona (vista 35, 35-10).
final class SugerenciaMapa extends Equatable {
  const SugerenciaMapa({required this.paquete, this.zonaNombre, this.ciudadNombre, this.falla});

  final PaqueteTiles paquete;
  final String? zonaNombre;
  final String? ciudadNombre;

  /// Por qué no se pudo empezar la descarga (por ejemplo, sin lugar en el teléfono).
  final Failure? falla;

  SugerenciaMapa conFalla(Failure? nueva) => SugerenciaMapa(
    paquete: paquete,
    zonaNombre: zonaNombre,
    ciudadNombre: ciudadNombre,
    falla: nueva,
  );

  @override
  List<Object?> get props => [paquete, zonaNombre, ciudadNombre, falla];
}

/// HU-SYNC-010 + HU-CAM-005/006: cuando el pull trae una zona asignada o cambiada, y el teléfono
/// está con Wi-Fi y le alcanza el lugar, sugiere bajar el mapa de esa zona (o, si el catálogo no
/// trae paquete de zona, el de la ciudad que la cubre). Una vez por zona y por sesión: «Ahora no»
/// no vuelve a preguntar hasta la próxima sesión, mientras el aviso de zona siga pendiente.
class SugerenciaMapaNotifier extends Notifier<SugerenciaMapa?> {
  SugerenciaMapaNotifier(this.colportorId);

  final String colportorId;

  /// Las zonas que ya se evaluaron en esta sesión.
  final _vistas = <String>{};

  @override
  SugerenciaMapa? build() {
    ref.listen(avisosZonaProvider(colportorId), (_, avisos) => unawaited(_evaluar(avisos)));
    unawaited(Future<void>.microtask(() => _evaluar(ref.read(avisosZonaProvider(colportorId)))));
    return null;
  }

  Future<void> _evaluar(List<AvisoZona> avisos) async {
    for (final aviso in avisos) {
      if (aviso is! ZonaAsignada) continue;
      if (!_vistas.add('${aviso.inscripcionId}:${aviso.zonaId}')) continue;
      try {
        final sugerencia = await _sugerir(aviso);
        if (ref.mounted && sugerencia != null && state == null) state = sugerencia;
      } on Object {
        // Sin sugerencia: «Mapas offline» sigue ofreciendo el mapa cuando el colportor lo busque.
      }
    }
  }

  Future<SugerenciaMapa?> _sugerir(ZonaAsignada aviso) async {
    final conexion = await ref.read(monitorConectividadProvider).actual();
    if (conexion != TipoConexion.wifi) return null;
    final lugar = (await ref.read(fuenteLugarDeTrabajoProvider).leer()).fold((_) => null, (l) => l);
    if (lugar == null) return null;
    final ambito = AmbitoTrabajo(
      zonaId: aviso.zonaId,
      ciudadId: lugar.ambito.ciudadId,
      departamentoId: lugar.ambito.departamentoId,
    );
    final resultado = await ref.read(sugerirPaqueteTilesUseCaseProvider)(ambito);
    final sugerido = resultado.fold((_) => null, (p) => p);
    if (sugerido == null) return null;
    final libres = await ref.read(medidorEspacioDiscoProvider).bytesLibres();
    if (libres < sugerido.tamanoBytes) return null;
    return SugerenciaMapa(
      paquete: sugerido,
      zonaNombre: aviso.zonaNombre,
      ciudadNombre: lugar.ciudadNombre,
    );
  }

  /// «Descargar»: arranca con Wi-Fi (o queda en cola hasta que vuelva). Con una falla la deja en
  /// la sugerencia para que se vea y se pueda reintentar.
  Future<bool> descargar() async {
    final actual = state;
    if (actual == null) return false;
    final resultado = await ref.read(descargarPaqueteTilesUseCaseProvider)(
      DescargarPaqueteTilesParams(paquete: actual.paquete, esperarConexion: true),
    );
    if (!ref.mounted) return false;
    return resultado.fold(
      (f) {
        state = actual.conFalla(f);
        return false;
      },
      (_) {
        state = null;
        return true;
      },
    );
  }

  /// «Ahora no» (o cerrar la hoja): no se vuelve a sugerir esta zona en la sesión.
  void ahoraNo() => state = null;
}

final sugerenciaMapaProvider = NotifierProvider.autoDispose
    .family<SugerenciaMapaNotifier, SugerenciaMapa?, String>(SugerenciaMapaNotifier.new);
