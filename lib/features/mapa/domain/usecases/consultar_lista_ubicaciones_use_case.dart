import '../../../../core/usecases/use_case.dart';
import '../entities/consulta_lista_ubicaciones.dart';
import '../entities/lista_ubicaciones.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/armador_lista_ubicaciones.dart';

/// HU-UBI-002 — la lista de ubicaciones del colportor, reactiva: cualquier alta, baja o edición
/// vuelve a emitir la lista sin pull manual (§8.8).
///
/// Filtros (tipo, ciudad, proximidad, bajas), búsqueda por calle + número, orden (recientes o
/// cercanía), contadores y página de 50 en 50: ver [ConsultaListaUbicaciones] y
/// `ArmadorListaUbicaciones`. Lista vacía = `ListaUbicaciones.estaVacia`: la vista muestra el
/// empty state con "Registrar tu primera ubicación".
///
/// Todo se resuelve en memoria sobre las ubicaciones del colportor (cientos, no miles). Si la
/// lista crece o la búsqueda se vuelve lenta, el paso siguiente es FTS5 (R17), sin tocar este
/// contrato.
final class ConsultarListaUbicacionesUseCase
    implements StreamUseCase<ListaUbicaciones, ConsultaListaUbicaciones> {
  ConsultarListaUbicacionesUseCase(this._repositorio);

  final UbicacionRepository _repositorio;

  @override
  Stream<ListaUbicaciones> call(ConsultaListaUbicaciones consulta) => _repositorio
      .observarDelColportor(
        colportorId: consulta.colportorId,
        ciudadId: consulta.ciudadId,
        incluirBajas: consulta.incluirBajas,
      )
      .map((ubicaciones) => ArmadorListaUbicaciones.armar(ubicaciones, consulta));
}
