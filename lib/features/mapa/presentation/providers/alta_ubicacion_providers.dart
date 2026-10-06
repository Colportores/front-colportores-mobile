import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../data/datasources/ubicacion_local_data_source_drift.dart';
import '../../data/datasources/zona_local_data_source.dart';
import '../../data/repositories/ubicacion_repository_impl.dart';
import '../../data/repositories/zona_repository_impl.dart';
import '../../data/services/fuentes_sin_adaptador_ubicaciones.dart';
import '../../data/services/geocodificador_nominatim.dart';
import '../../data/services/plataforma_gps.dart';
import '../../data/services/plataforma_gps_geolocator.dart';
import '../../data/services/proveedor_gps_plataforma.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/repositories/ubicacion_repository.dart';
import '../../domain/repositories/zona_repository.dart';
import '../../domain/services/activador_gps.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/geocodificador_inverso.dart';
import '../../domain/services/inscripciones_colportor.dart';
import '../../domain/services/proveedor_gps.dart';
import '../../domain/services/ubicador_zona.dart';
import '../../domain/usecases/capturar_posicion_gps_use_case.dart';
import '../../domain/usecases/registrar_ubicacion_use_case.dart';
import '../../domain/value_objects/area_mapa.dart';

// Cableado del alta de ubicación (HU-UBI-001, vistas 03 y 04). Presentation conoce domain; data se
// inyecta acá. Todo lo que todavía no tiene fuente real (ciudades de la campaña, inscripciones,
// motor de sync) usa un `...SinFuente` que no inventa datos: ver `fuentes_sin_adaptador_ubicaciones`.

/// El motor de sync (#178). Hasta que llegue, [EncoladorSyncSinMotor]: encolar falla y el alta no
/// se guarda, en vez de quedar en el teléfono sin subir nunca.
final encoladorSyncProvider = Provider<EncoladorSync>((ref) => const EncoladorSyncSinMotor());

/// La DB local abierta (`dbLocalProvider`). Sin DB abierta no hay dónde guardar: lanza, y quien lo
/// lee lo traduce a una falla.
final ubicacionRepositoryProvider = Provider<UbicacionRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return UbicacionRepositoryImpl(
    UbicacionLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider)),
  );
});

final zonaRepositoryProvider = Provider<ZonaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db));
});

/// Sin fuente de inscripciones hasta coord#20: [InscripcionesColportorSinFuente].
final inscripcionesColportorProvider = Provider<InscripcionesColportor>(
  (ref) => InscripcionesColportorSinFuente(),
);

final ubicadorZonaProvider = Provider<UbicadorZona>(
  (ref) =>
      UbicadorZona(ref.watch(zonaRepositoryProvider), ref.watch(inscripcionesColportorProvider)),
);

/// Cuánto se espera con el punto quieto antes de pedir la dirección y la ciudad (el mapa se
/// mueve con el dedo: no se pregunta en cada fotograma). Un test lo acorta.
final esperaPuntoAltaProvider = Provider<Duration>((ref) => const Duration(milliseconds: 600));

/// Generador de UUID v7 del alta; un test lo reemplaza para fijar los ids.
final generadorIdUbicacionProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// Reloj del alta; un test lo reemplaza.
final relojAltaUbicacionProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final registrarUbicacionUseCaseProvider = Provider<RegistrarUbicacionUseCase>(
  (ref) => RegistrarUbicacionUseCase(
    ref.watch(ubicacionRepositoryProvider),
    generarId: ref.watch(generadorIdUbicacionProvider),
    ubicador: ref.watch(ubicadorZonaProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);

/// El plugin de GPS. Un test lo reemplaza por un fake.
final plataformaGpsProvider = Provider<PlataformaGps>((ref) => const PlataformaGpsGeolocator());

final proveedorGpsPlataformaProvider = Provider<ProveedorGpsPlataforma>(
  (ref) => ProveedorGpsPlataforma(ref.watch(plataformaGpsProvider)),
);

final proveedorGpsProvider = Provider<ProveedorGps>(
  (ref) => ref.watch(proveedorGpsPlataformaProvider),
);

final activadorGpsProvider = Provider<ActivadorGps>(
  (ref) => ref.watch(proveedorGpsPlataformaProvider),
);

final capturarPosicionGpsUseCaseProvider = Provider<CapturarPosicionGpsUseCase>(
  (ref) => CapturarPosicionGpsUseCase(ref.watch(proveedorGpsProvider)),
);

/// Nominatim público como respaldo (ADR-011); el índice offline de Photon llega con la descarga de
/// paquetes (#189).
final geocodificadorInversoProvider = Provider<GeocodificadorInverso>(
  (ref) => GeocodificadorNominatim(lectorHttpIo()),
);

/// Sin réplica local de las ciudades de la campaña hasta el adaptador real (#274, junto al pull de
/// catálogos): [CiudadesParaAltaSinFuente] devuelve la falla de lectura, y toda alta muestra «No
/// pudimos leer las ciudades de tu campaña». La app no sale a producción así.
final ciudadesParaAltaProvider = Provider<CiudadesParaAlta>((ref) => CiudadesParaAltaSinFuente());

/// Las ubicaciones del colportor dentro de [consulta] (colportor y área visible), para el contexto
/// del mapa del alta. Emite vacío si la DB no está abierta.
final marcadoresCercanosProvider = StreamProvider.autoDispose
    .family<List<MarcadorMapa>, ({String colportorId, AreaMapa area})>((ref, consulta) {
      final db = ref.watch(dbLocalProvider);
      if (db == null) return Stream.value(const []);
      return ref
          .watch(ubicacionRepositoryProvider)
          .observarMarcadoresEnArea(colportorId: consulta.colportorId, area: consulta.area);
    });
