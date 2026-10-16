import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';

/// Lo de la sesión deslizante (HU-AUTH-007) para los remotos de test que no la ejercitan: sin red
/// para renovar, nunca expira, nada vencido al arrancar.
mixin RemotoSinSesionDeslizante implements AuthRemoteDataSource {
  @override
  Future<SesionModel> renovarSesion() async => throw const SinConexionException();

  @override
  Stream<MotivoExpiracion> get expiraciones => const Stream.empty();

  @override
  bool tomarVencimientoPorInactividad() => false;
}
