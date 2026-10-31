import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../jornada/presentation/providers/jornadas_por_cerrar_providers.dart';
import '../../domain/services/lector_de_lo_recuperado.dart';
import '../../domain/services/servicio_recuperacion.dart';
import '../textos_recuperacion.dart';
import '../widgets/aviso_drive.dart';
import 'recuperacion_pendiente_providers.dart';
import 'recuperacion_providers.dart';
import 'respaldo_drive_providers.dart';

/// En qué pantalla del asistente está la persona (vista 34).
enum PantallaAsistente {
  /// Mirando qué hay en Drive: el estado de carga del paso 1.
  buscando,

  /// 34·01: hay un respaldo para traer.
  encontrado,

  /// 34·02: hay que conectar Drive para buscar.
  conectar,

  /// 34·09: en este Drive no hay un respaldo.
  sinRespaldo,

  /// 34·10: sin conexión al empezar.
  sinConexion,

  /// La búsqueda falló por otra razón.
  fallaBusqueda,

  /// Hay respaldos de más de un teléfono y no está decidido qué se ofrece (pendiente de Cristian).
  variosRespaldos,

  /// 34·03 y 34·04: la contraseña de la copia.
  contrasena,

  /// 34·05: restaurando.
  restaurando,

  /// 34·06: se cortó la conexión a la mitad.
  interrumpida,

  /// 34·07: una parte dañada; se restauró hasta donde se pudo.
  parcial,

  /// 34·08: listo.
  listo,

  /// El respaldo es de una versión más nueva de la app (HU-SYNC-006, «Edge»).
  versionMasNueva,

  /// Drive no tiene la clave envuelta de este respaldo.
  sinLlave,

  /// La copia está dañada: no hay nada que traer.
  ilegible,

  /// Falló por otra razón.
  fallida,
}

/// Lo que el asistente muestra. Inmutable: cada paso es un estado nuevo.
final class EstadoAsistente extends Equatable {
  const EstadoAsistente({
    this.pantalla = PantallaAsistente.buscando,
    this.respaldo,
    this.respaldos = const [],
    this.progreso,
    this.informe,
    this.resumen,
    this.contrasenaIncorrecta = false,
    this.cancelando = false,
    this.conectando = false,
    this.avisoDeDrive,
    this.sinConexionAlCortarse = false,
    this.terminando = false,
    this.reintentoFallido = false,
  });

  final PantallaAsistente pantalla;

  /// El respaldo que se va a traer (o se trae).
  final RespaldoEnDrive? respaldo;

  /// Los respaldos que se encontraron cuando hay varios.
  final List<RespaldoEnDrive> respaldos;

  /// En qué parte va la restauración.
  final ProgresoRecuperacion? progreso;

  /// Lo que se recuperó, al terminar.
  final InformeRecuperacion? informe;

  /// Cuánto hay de cada cosa en el teléfono, al terminar. `null` si no se pudo leer.
  final ResumenDeLoRecuperado? resumen;

  /// La contraseña no abrió la copia (34·04).
  final bool contrasenaIncorrecta;

  /// Se pidió cancelar y se espera a que la descarga pare.
  final bool cancelando;

  /// La persona está en la pantalla de Google (34·02).
  final bool conectando;

  /// El aviso de 34·02 cuando conectar no salió (cancelado, sin conexión, otra causa) o Drive perdió
  /// el permiso a mitad de la restauración.
  final ({ClaseAvisoDrive clase, String texto})? avisoDeDrive;

  /// 34·06: la restauración terminó sin conexión (no es que siga esperando sola): «Reintentar» la
  /// retoma desde la parte donde quedó.
  final bool sinConexionAlCortarse;

  /// «Ir a mi inicio» (o «Empezar sin recuperar») en curso: no admite otro toque.
  final bool terminando;

  /// 34·07: el «Reintentar» no llegó a terminar y se volvió acá; lo recuperado sigue en el teléfono.
  final bool reintentoFallido;

  EstadoAsistente copyWith({
    PantallaAsistente? pantalla,
    RespaldoEnDrive? respaldo,
    List<RespaldoEnDrive>? respaldos,
    ProgresoRecuperacion? Function()? progreso,
    InformeRecuperacion? informe,
    ResumenDeLoRecuperado? Function()? resumen,
    bool? contrasenaIncorrecta,
    bool? cancelando,
    bool? conectando,
    ({ClaseAvisoDrive clase, String texto})? Function()? avisoDeDrive,
    bool? sinConexionAlCortarse,
    bool? terminando,
    bool? reintentoFallido,
  }) => EstadoAsistente(
    pantalla: pantalla ?? this.pantalla,
    respaldo: respaldo ?? this.respaldo,
    respaldos: respaldos ?? this.respaldos,
    progreso: progreso != null ? progreso() : this.progreso,
    informe: informe ?? this.informe,
    resumen: resumen != null ? resumen() : this.resumen,
    contrasenaIncorrecta: contrasenaIncorrecta ?? this.contrasenaIncorrecta,
    cancelando: cancelando ?? this.cancelando,
    conectando: conectando ?? this.conectando,
    avisoDeDrive: avisoDeDrive != null ? avisoDeDrive() : this.avisoDeDrive,
    sinConexionAlCortarse: sinConexionAlCortarse ?? this.sinConexionAlCortarse,
    terminando: terminando ?? this.terminando,
    reintentoFallido: reintentoFallido ?? this.reintentoFallido,
  );

  @override
  List<Object?> get props => [
    pantalla,
    respaldo,
    respaldos,
    progreso == null
        ? null
        : (progreso!.paso, progreso!.hechas, progreso!.total, progreso!.esperandoConexion),
    informe?.fechaDelRespaldo,
    informe?.parcial,
    resumen?.ubicaciones,
    resumen?.personas,
    resumen?.ventas,
    resumen?.cobros,
    contrasenaIncorrecta,
    cancelando,
    conectando,
    avisoDeDrive?.clase,
    avisoDeDrive?.texto,
    sinConexionAlCortarse,
    terminando,
    reintentoFallido,
  ];
}

/// El asistente de recuperación del primer arranque (HU-SYNC-006, vista 34): la máquina de pasos
/// entre «Encontramos un respaldo» y «Tus datos están de vuelta». Sin lógica de negocio (vive en
/// [ServicioRecuperacion]): traduce sus resultados a la pantalla que sigue.
///
/// Cada acción tiene una guarda propia: un doble toque no busca, conecta ni restaura dos veces. La
/// contraseña vive solo en este objeto, mientras dura el asistente; nunca va al estado, a los logs
/// ni al disco.
final asistenteRecuperacionProvider =
    NotifierProvider.autoDispose<AsistenteRecuperacion, EstadoAsistente>(AsistenteRecuperacion.new);

class AsistenteRecuperacion extends Notifier<EstadoAsistente> {
  bool _buscando = false;
  bool _restaurando = false;
  bool _terminando = false;

  /// Sube con cada búsqueda nueva: la respuesta de una búsqueda que ya no vale se descarta.
  int _generacionDeBusqueda = 0;

  String? _password;
  CancelacionRecuperacion? _cancelacion;

  ServicioRecuperacion get _servicio => ref.read(servicioRecuperacionProvider);

  @override
  EstadoAsistente build() {
    ref.onDispose(() {
      _password = null;
      _cancelacion?.cancelar();
    });
    // La primera búsqueda arranca apenas el asistente se muestra.
    unawaited(Future.microtask(buscar));
    return const EstadoAsistente();
  }

  /// Busca el respaldo en el Drive conectado (pasos 1, 2, 9 y 10 de la vista 34).
  Future<void> buscar() async {
    if (!ref.mounted || _buscando || _restaurando) return;
    _buscando = true;
    final generacion = ++_generacionDeBusqueda;
    state = state.copyWith(
      pantalla: PantallaAsistente.buscando,
      avisoDeDrive: () => null,
      progreso: () => null,
    );
    try {
      final resultado = await _servicio.buscar();
      if (!ref.mounted || generacion != _generacionDeBusqueda) return;
      state = switch (resultado) {
        RespaldoEncontrado(:final respaldo) => state.copyWith(
          pantalla: PantallaAsistente.encontrado,
          respaldo: respaldo,
        ),
        SinRespaldoEnDrive() => state.copyWith(pantalla: PantallaAsistente.sinRespaldo),
        VariosRespaldosEnDrive(:final respaldos) => state.copyWith(
          pantalla: PantallaAsistente.variosRespaldos,
          respaldos: respaldos,
        ),
        DriveSinPermiso() => state.copyWith(pantalla: PantallaAsistente.conectar),
        BusquedaSinConexion() => state.copyWith(pantalla: PantallaAsistente.sinConexion),
        BusquedaFallida() => state.copyWith(pantalla: PantallaAsistente.fallaBusqueda),
      };
    } on Object catch (e) {
      _registrarFallo('RECUPERACION_BUSCAR', e);
      if (ref.mounted && generacion == _generacionDeBusqueda) {
        state = state.copyWith(pantalla: PantallaAsistente.fallaBusqueda);
      }
    } finally {
      _buscando = false;
    }
  }

  /// 34·02: abre la pantalla de Google. Con el permiso, sigue con la búsqueda. Una sola conexión a la
  /// vez.
  Future<void> conectarDrive() async {
    if (state.conectando) return;
    state = state.copyWith(conectando: true, avisoDeDrive: () => null);
    ResultadoConexionDrive resultado;
    try {
      // El estado de Drive cuelga de la sesión: se espera a tenerla para no abrir Google sin saber
      // de quién es la cuenta.
      await ref.read(sesionProvider.future);
      resultado = await ref.read(estadoRespaldoDriveProvider.notifier).conectar();
    } on Object {
      resultado = const DriveNoQuedoConectado(FailureDriveNoConectado());
    }
    if (!ref.mounted) return;
    state = state.copyWith(conectando: false);
    switch (resultado) {
      case DriveQuedoConectado():
        await buscar();
      case DriveNoQuedoConectado(:final falla):
        state = state.copyWith(
          avisoDeDrive: () => (
            clase: switch (falla) {
              FailureDriveCancelado() => ClaseAvisoDrive.info,
              FailureSinConexion() => ClaseAvisoDrive.sinConexion,
              _ => ClaseAvisoDrive.error,
            },
            texto: falla.mensaje,
          ),
        );
      case DriveOcupado():
        break;
    }
  }

  /// 34·09: «Probar con otra cuenta»: se desconecta la cuenta que no tenía respaldo y se vuelve a
  /// pedir una.
  Future<void> probarConOtraCuenta() async {
    if (state.conectando) return;
    state = state.copyWith(conectando: true, avisoDeDrive: () => null);
    try {
      await ref.read(sesionProvider.future);
      await ref.read(estadoRespaldoDriveProvider.notifier).desconectar();
    } on Object catch (e) {
      _registrarFallo('RECUPERACION_OTRA_CUENTA', e);
    }
    if (!ref.mounted) return;
    state = state.copyWith(conectando: false, pantalla: PantallaAsistente.conectar);
    await conectarDrive();
  }

  /// 34·01: «Recuperar mis datos» lleva a pedir la contraseña.
  void elegirRecuperar() {
    if (state.pantalla != PantallaAsistente.encontrado || state.respaldo == null) return;
    state = state.copyWith(pantalla: PantallaAsistente.contrasena, contrasenaIncorrecta: false);
  }

  /// La persona escribió otra contraseña: el aviso de 34·04 ya no corresponde.
  void contrasenaEditada() {
    if (state.contrasenaIncorrecta) state = state.copyWith(contrasenaIncorrecta: false);
  }

  /// 34·03: «Abrir copia». Restaura [respaldo] con [password]; el resultado decide la pantalla que
  /// sigue. Una sola restauración a la vez.
  Future<void> abrirCopia(String password) async {
    final respaldo = state.respaldo;
    if (password.isEmpty || respaldo == null) return;
    _password = password;
    await _restaurar(respaldo);
  }

  /// 34·06: «Reintentar»: retoma desde donde quedó, con la misma contraseña.
  Future<void> reintentarRestauracion() async {
    final respaldo = state.respaldo;
    final password = _password;
    if (respaldo == null || password == null) {
      // Sin la contraseña en memoria (no debería pasar) se vuelve a pedirla.
      state = state.copyWith(pantalla: PantallaAsistente.contrasena);
      return;
    }
    await _restaurar(respaldo);
  }

  /// 34·07 «Reintentar»: vuelve a correr la recuperación entera con la misma contraseña. Lo ya
  /// recuperado sigue en el teléfono: si el nuevo intento no termina (se corta, se cancela o falla)
  /// se vuelve a 34·07 como estaba; si termina, manda su resultado (34·08 o un nuevo 34·07).
  Future<void> reintentarDesdeParcial() async {
    final respaldo = state.respaldo;
    if (state.pantalla != PantallaAsistente.parcial || _restaurando || _terminando) return;
    if (respaldo == null || _password == null) return;
    await _restaurar(respaldo, volverA: state.copyWith(reintentoFallido: false));
  }

  Future<void> _restaurar(RespaldoEnDrive respaldo, {EstadoAsistente? volverA}) async {
    final password = _password;
    if (_restaurando || password == null) return;
    _restaurando = true;
    final cancelacion = _cancelacion = CancelacionRecuperacion();
    state = state.copyWith(
      pantalla: PantallaAsistente.restaurando,
      contrasenaIncorrecta: false,
      cancelando: false,
      sinConexionAlCortarse: false,
      progreso: () => ProgresoRecuperacion(
        PasoRecuperacion.bajando,
        hechas: state.progreso?.hechas ?? 0,
        total: respaldo.partes,
      ),
    );
    try {
      final resultado = await _servicio.recuperar(
        respaldo: respaldo,
        password: password,
        alAvanzar: _alAvanzar,
        cancelar: cancelacion,
      );
      if (!ref.mounted) return;
      if (volverA != null && resultado is! RecuperacionHecha) {
        _volverAlParcial(volverA);
      } else {
        await _alTerminar(resultado);
      }
    } on Object catch (e) {
      _registrarFallo('RECUPERACION_RESTAURAR', e);
      if (ref.mounted) {
        if (volverA != null) {
          _volverAlParcial(volverA);
        } else {
          state = state.copyWith(pantalla: PantallaAsistente.fallida);
        }
      }
    } finally {
      _restaurando = false;
      if (identical(_cancelacion, cancelacion)) _cancelacion = null;
    }
  }

  void _volverAlParcial(EstadoAsistente parcial) {
    state = parcial.copyWith(
      reintentoFallido: true,
      cancelando: false,
      sinConexionAlCortarse: false,
      progreso: () => null,
    );
  }

  void _alAvanzar(ProgresoRecuperacion progreso) {
    if (!ref.mounted || !_restaurando) return;
    // Se cortó la conexión y el servicio sigue solo: 34·06 con «Reintentar» apagado.
    state = state.copyWith(
      pantalla: progreso.esperandoConexion
          ? PantallaAsistente.interrumpida
          : PantallaAsistente.restaurando,
      progreso: () => progreso,
      sinConexionAlCortarse: false,
    );
  }

  Future<void> _alTerminar(ResultadoRecuperacion resultado) async {
    switch (resultado) {
      case RecuperacionHecha(:final informe):
        // Con una parte dañada la contraseña queda en memoria para el «Reintentar» de 34·07.
        if (!informe.parcial) _password = null;
        final usuarioId = ref.read(sesionProvider).value?.usuarioId;
        if (usuarioId != null) {
          // Ya hay datos recuperados: aunque la app se cierre acá, el asistente no se vuelve a ofrecer.
          // Si no se pudo anotar, lo recuperado sigue ahí y la pantalla no puede decir lo contrario.
          try {
            await ref.read(recuperacionResueltaRepositoryProvider).marcarResuelta(usuarioId);
          } on Object catch (e) {
            _registrarFallo('RECUPERACION_MARCA', e);
          }
        }
        ResumenDeLoRecuperado? resumen;
        try {
          resumen = await ref.read(lectorDeLoRecuperadoProvider).resumen();
        } on Object catch (e) {
          // El resumen es lo que se cuenta; que no se pueda leer no deshace lo recuperado.
          _registrarFallo('RECUPERACION_RESUMEN', e);
        }
        if (!ref.mounted) return;
        state = state.copyWith(
          pantalla: informe.parcial ? PantallaAsistente.parcial : PantallaAsistente.listo,
          informe: informe,
          resumen: () => resumen,
          progreso: () => null,
          reintentoFallido: false,
        );
      case ContrasenaNoAbreElRespaldo():
        _password = null;
        state = state.copyWith(
          pantalla: PantallaAsistente.contrasena,
          contrasenaIncorrecta: true,
          progreso: () => null,
        );
      case SinLlaveParaElRespaldo():
        _password = null;
        state = state.copyWith(pantalla: PantallaAsistente.sinLlave, progreso: () => null);
      case RespaldoDeVersionMasNueva():
        _password = null;
        state = state.copyWith(pantalla: PantallaAsistente.versionMasNueva, progreso: () => null);
      case RespaldoIlegible():
        _password = null;
        state = state.copyWith(pantalla: PantallaAsistente.ilegible, progreso: () => null);
      case RecuperacionSinConexion(:final hechas, :final total):
        state = state.copyWith(
          pantalla: PantallaAsistente.interrumpida,
          sinConexionAlCortarse: true,
          progreso: () =>
              ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: hechas, total: total),
        );
      case RecuperacionCancelada():
        _password = null;
        state = state.copyWith(
          pantalla: PantallaAsistente.encontrado,
          cancelando: false,
          progreso: () => null,
        );
      case RecuperacionSinPermiso():
        _password = null;
        state = state.copyWith(
          pantalla: PantallaAsistente.conectar,
          progreso: () => null,
          avisoDeDrive: () => (clase: ClaseAvisoDrive.error, texto: TextosRecuperacion.sinPermiso),
        );
      case RecuperacionFallida():
        _password = null;
        state = state.copyWith(pantalla: PantallaAsistente.fallida, progreso: () => null);
    }
  }

  /// «Cancelar» mientras se baja: corta la descarga sin tocar la base (HU-SYNC-006, «Cancelación por
  /// el usuario»). Con la restauración ya aplicándose no se puede. Cortada a media espera de
  /// conexión (34·06 sin restauración en curso), vuelve a 34·01.
  void cancelar() {
    if (_restaurando) {
      final progreso = state.progreso;
      if (progreso != null && !progreso.sePuedeCancelar) return;
      if (state.cancelando) return;
      state = state.copyWith(cancelando: true);
      _cancelacion?.cancelar();
      return;
    }
    if (state.pantalla == PantallaAsistente.interrumpida) {
      _password = null;
      state = state.copyWith(
        pantalla: PantallaAsistente.encontrado,
        sinConexionAlCortarse: false,
        progreso: () => null,
      );
    }
  }

  /// «Empezar sin recuperar», «Seguir con lo recuperado» e «Ir a mi inicio»: el asistente termina y
  /// la app sigue a la pantalla siguiente. Una sola vez.
  Future<void> terminar() async {
    if (_terminando || _restaurando) return;
    _terminando = true;
    _password = null;
    state = state.copyWith(terminando: true);
    try {
      // Las jornadas que quedaron abiertas con otra después (HU-JOR-002) se leen recién ahora: la
      // base que había al empezar no es la recuperada.
      final usuarioId = ref.read(sesionProvider).value?.usuarioId;
      if (usuarioId != null) ref.invalidate(jornadasPorCerrarProvider(usuarioId));
      await ref.read(recuperacionPendienteProvider.notifier).terminar();
    } finally {
      _terminando = false;
      if (ref.mounted) state = state.copyWith(terminando: false);
    }
  }

  void _registrarFallo(String operacion, Object error) {
    AppLogger.instance.warn(LogModulo.backup, operacion, 'falló un paso del asistente', {
      'error': error.runtimeType.toString(),
    });
  }
}
