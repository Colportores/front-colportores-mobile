import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/config/config_supabase.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../data/datasources/ticket_local_data_source_drift.dart';
import '../../data/repositories/ticket_repository_impl.dart';
import '../../data/services/servidor_de_fotos_supabase.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/repositories/ticket_repository.dart';
import '../../domain/services/captura_de_foto.dart';
import '../../domain/services/politica_de_compresion.dart';
import '../../domain/services/puertos_de_fotos.dart';
import '../../domain/usecases/borrar_copia_local_de_ticket_use_case.dart';
import '../../domain/usecases/registrar_ticket_use_case.dart';
import '../../domain/usecases/subir_fotos_de_tickets_use_case.dart';

// Cableado de los tickets (BACK-HU-COB-007, #426). Presentation conoce domain; data se inyecta acá.

/// La fuente de datos de los tickets: las tablas `ticket` y `ticket_foto_local` de la DB local
/// cifrada. Sin DB abierta no hay dónde leer ni guardar: lanza.
final ticketLocalProvider = Provider<TicketLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return TicketLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

/// Dónde queda la copia local de cada foto. `main.dart` lo reemplaza con `AlmacenDeFotosEnDisco` sobre
/// el directorio privado de la app; sin reemplazo (tests y demo) no hay dónde guardar y guardar o leer
/// lanza, pero armarlo no.
final almacenDeFotosDeTicketProvider = Provider<AlmacenDeFotosDeTicket>(
  (ref) => const _AlmacenSinConfigurar(),
);

final class _AlmacenSinConfigurar implements AlmacenDeFotosDeTicket {
  const _AlmacenSinConfigurar();

  static StateError _error() => StateError('El almacén de fotos de tickets no está configurado');

  @override
  Future<String> guardar(String ticketId, TipoDeImagen tipo, Uint8List bytes) => throw _error();

  @override
  Future<Uint8List?> leer(String ruta) => throw _error();

  @override
  Future<void> borrar(String ruta) => throw _error();
}

/// La subida de la foto por el enlace firmado de `foto-ticket`. Sin Supabase configurado (tests y demo)
/// no hay a dónde subir: la foto queda pendiente.
final servidorDeFotosDeTicketProvider = Provider<ServidorDeFotosDeTicket>(
  (ref) => ConfigSupabase.configurada
      ? ServidorDeFotosSupabase.conCliente(Supabase.instance.client)
      : const _SinServidorDeFotos(),
);

final class _SinServidorDeFotos implements ServidorDeFotosDeTicket {
  const _SinServidorDeFotos();

  @override
  Future<ResultadoDeSubidaDeFoto> subir({
    required String ticketId,
    required TipoDeImagen tipo,
    required Uint8List bytes,
  }) async => const SubidaFallida(codigo: 'sin_servidor', reintentable: true);
}

/// El que achica la imagen. **Sin adaptador todavía**: comprimir a JPEG necesita una librería de
/// imágenes y elegirla es una decisión de stack que espera a Cristian (pendiente del issue #426). Hasta
/// entonces lanza `UnimplementedError`, en vez de mandar una foto sin comprimir; la política de cuánto
/// achicar ([PoliticaDeCompresion]) ya está lista y probada con un compresor de prueba.
final compresorDeImagenProvider = Provider<CompresorDeImagen>(
  (ref) => const _CompresorSinAdaptador(),
);

final class _CompresorSinAdaptador implements CompresorDeImagen {
  const _CompresorSinAdaptador();

  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) => throw UnimplementedError(
    'Falta el adaptador de compresión de imágenes (decisión de stack pendiente, #426)',
  );
}

/// La cámara y la galería (vista 29 C, #427). **Sin adaptador todavía**: elegir la librería de cámara
/// es una decisión de stack que espera a Cristian (pendiente del issue #427), junto con la del
/// compresor. Mientras sea `null` la app no ofrece «Sacar foto del ticket» y el cobro con tarjeta
/// muestra el aviso de guardar el ticket (29A·02). `main.dart` la reemplaza cuando haya adaptador.
final capturadorDeFotoProvider = Provider<CapturadorDeFoto?>((ref) => null);

/// Se puede cargar la foto del ticket: hay cámara y galería. El compresor viene con el mismo
/// adaptador (misma decisión de stack).
final fotoDelTicketDisponibleProvider = Provider<bool>(
  (ref) => ref.watch(capturadorDeFotoProvider) != null,
);

/// Persistencia de los tickets: encola el sync en la misma transacción.
final ticketRepositoryProvider = Provider<TicketRepository>(
  (ref) => TicketRepositoryImpl(
    ref.watch(ticketLocalProvider),
    ref.watch(almacenDeFotosDeTicketProvider),
  ),
);

/// Generador de UUID v7 del ticket; un test lo reemplaza para fijar los ids.
final generadorIdTicketProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj del ticket («ahora» y la fecha máxima); un test lo reemplaza.
final relojTicketProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Cómo se achica la foto antes de la vista previa «¿Se lee bien el ticket?» (HU-COB-007, S42).
final politicaDeCompresionProvider = Provider<PoliticaDeCompresion>(
  (ref) => PoliticaDeCompresion(ref.watch(compresorDeImagenProvider)),
);

/// Registra un ticket con su foto (HU-COB-007). La pantalla «Foto del ticket» (vista 29 C, #427) lo usa.
final registrarTicketUseCaseProvider = Provider<RegistrarTicketUseCase>(
  (ref) => RegistrarTicketUseCase(
    ref.watch(ticketRepositoryProvider),
    ahora: ref.watch(relojTicketProvider),
  ),
);

/// Sube las fotos de los tickets que esperan.
final subirFotosDeTicketsUseCaseProvider = Provider<SubirFotosDeTicketsUseCase>(
  (ref) => SubirFotosDeTicketsUseCase(
    ref.watch(ticketRepositoryProvider),
    ref.watch(servidorDeFotosDeTicketProvider),
  ),
);

/// «Borrar copia local» (supuesto S41): solo con la foto ya subida.
final borrarCopiaLocalDeTicketUseCaseProvider = Provider<BorrarCopiaLocalDeTicketUseCase>(
  (ref) => BorrarCopiaLocalDeTicketUseCase(ref.watch(ticketRepositoryProvider)),
);

/// Un ticket con su copia local, mientras la pantalla de la vista 29 C está abierta: de ahí salen
/// «subiendo», «subido», «en cola» y el error.
final ticketObservadoProvider = StreamProvider.autoDispose.family<TicketRegistrado?, String>(
  (ref, ticketId) => ref.watch(ticketRepositoryProvider).observarTicket(ticketId),
);

/// Los ids de los cobros cuyo ticket todavía no subió su foto (el cobro con «ticket pendiente»).
final cobrosConTicketPendienteProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(ticketRepositoryProvider).cobrosConTicketPendiente(),
);

/// Cada cuánto se reintenta la subida mientras haya fotos esperando y conexión.
const esperaEntreReintentosDeSubida = Duration(minutes: 2);

/// La cola de subida de fotos (HU-COB-007, «Edge: sin red»): sube las fotos pendientes cuando hay red
/// y el ticket ya llegó al servidor.
///
/// Corre cuando **cambia lo que hay para subir** (el motor terminó de subir la fila de un ticket, o se
/// registró uno) o **vuelve la conexión**, y se reintenta cada [esperaEntreReintentosDeSubida] mientras
/// quede algo. Una pasada a la vez. Sin conexión no hace nada: la foto espera.
///
/// Lo observa la pantalla principal mientras la DB está abierta.
final colaDeSubidaDeFotosProvider = Provider<void>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return;
  final repositorio = ref.watch(ticketRepositoryProvider);
  final subir = ref.watch(subirFotosDeTicketsUseCaseProvider);

  var porSubir = 0;
  var conexion = TipoConexion.sinConexion;
  var conexionConocida = false;
  var cerrada = false;

  Future<void> correr() async {
    if (cerrada || porSubir == 0 || (conexionConocida && conexion == TipoConexion.sinConexion)) {
      return;
    }
    try {
      await subir(const NoParams());
    } on Object catch (e, st) {
      AppLogger.instance.error(
        LogModulo.net,
        'TICKET_COLA_FOTOS_FAIL',
        'falló una pasada de la cola de fotos',
        {'tipo': e.runtimeType.toString()},
        null,
        st,
      );
    }
  }

  // El reintento periódico solo existe mientras haya fotos esperando: sin nada por subir no hay timer.
  Timer? temporizador;
  final escucha = repositorio.cantidadDeFotosPorSubir().listen((cantidad) {
    porSubir = cantidad;
    if (cantidad > 0) {
      temporizador ??= Timer.periodic(esperaEntreReintentosDeSubida, (_) => unawaited(correr()));
    } else {
      temporizador?.cancel();
      temporizador = null;
    }
    unawaited(correr());
  }, onError: (Object _) {});
  ref
    ..listen(conexionProvider, (anterior, siguiente) {
      final tipo = siguiente.value;
      if (tipo == null) return;
      conexion = tipo;
      conexionConocida = true;
      unawaited(correr());
    })
    ..onDispose(() {
      cerrada = true;
      temporizador?.cancel();
      unawaited(escucha.cancel());
    });
});
