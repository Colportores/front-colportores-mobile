import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/domain/entities/resumen_datos_locales.dart';
import '../../../auth/domain/usecases/borrar_datos_locales_use_case.dart' show PasoBorrado;
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/borrado_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../jornada/presentation/providers/jornada_providers.dart';
import '../widgets/confirmacion_final_borrado.dart';
import '../widgets/progreso_borrado.dart';
import '../widgets/resumen_borrado.dart';
import 'configuracion_page.dart' show colorEncabezado;

/// Configuración → Privacidad y datos → "Borrar datos locales" (HU-AUTH-010, vista 19).
///
/// Es el único flujo donde el colportor borra a propósito los datos del teléfono, así que **no
/// deja perder nada sin avisar**: con operaciones sin sincronizar (o sin poder contarlas) bloquea
/// el borrado y ofrece sincronizar. Después, dos casillas, una confirmación final a pantalla
/// completa (frase y contraseña) y el borrado con sus pasos. Si algo falla, lo dice con lo que
/// pasó de verdad: qué se borró y qué no.
class BorrarDatosLocalesPage extends ConsumerStatefulWidget {
  const BorrarDatosLocalesPage({super.key});

  static Route<void> ruta() =>
      MaterialPageRoute<void>(builder: (_) => const BorrarDatosLocalesPage());

  @override
  ConsumerState<BorrarDatosLocalesPage> createState() => _BorrarDatosLocalesPageState();
}

/// Textos literales de HU-AUTH-010 y de la vista 19 (los marcados «propuesta» no están en la HU ni
/// en el canvas: se confirman con Cristian).
abstract final class TextosBorrado {
  static const explicacion =
      'Borraremos todos los datos que tengas en este dispositivo y cerraremos tu sesión. Tu '
      'cuenta seguirá existiendo en nuestro sistema (puede ser reactivada si te asignan a una '
      'campaña nueva). Si querés eliminar definitivamente tu cuenta, contactá a tu coordinador '
      'para una baja administrativa.';
  static const encabezadoResumen = 'Esto se borra de este teléfono y no se puede deshacer:';
  static const datosDelSistema =
      'Los datos del sistema (estado de las ubicaciones, estadísticas) no se borran con esta '
      'acción.';
  static const limiteBorrado =
      'El archivo se pisa con ceros antes de borrarse. En la memoria del teléfono eso no garantiza '
      'que desaparezca físicamente; lo que sí lo protege es que siempre estuvo cifrado.';
  static const casillaSoloEsteTelefono =
      'Entiendo que solo se borran los datos de este teléfono. Mi coordinador conserva mis ventas.';
  static const casillaIrreversible = 'Entiendo que no se puede deshacer.';
  static const faltanCasillas = 'Marcá las dos casillas para continuar.';

  /// Aviso de lo que bloquea el borrado (artboard 02).
  static String pendientes(int n) => n == 1
      ? 'Tenés 1 operación sin sincronizar. Sincronizala antes de borrar los datos de este '
            'teléfono.'
      : 'Tenés $n operaciones sin sincronizar. Sincronizalas antes de borrar los datos de este '
            'teléfono.';
  static const leyendaBloqueo = '“Continuar” se habilita cuando no quedan operaciones pendientes.';
  static const noSePudieronContar = 'No se pudieron contar';

  /// Propuesta (el canvas dice «Podés seguir igual», que no va: decisión de Cristian del 29/09).
  static const reintentarConteo = 'Reintentá. Hasta poder contarlas, no se puede borrar.';

  /// Propuesta: lo que queda después de sincronizar y seguir con operaciones que no suben (las
  /// `INVALID` no se destraban sincronizando).
  static const quedanSinSubir =
      'Algunas operaciones no se pudieron subir. Las que tienen datos para corregir no se suben '
      'solas: revisalas y corregilas, y después volvé a sincronizar.';

  static const subtituloConfirmacion = 'Se cierra tu sesión y no se puede deshacer.';
  static const conservarDrive = 'No, conservar mi backup en Drive';
  static const borrarDrive = 'Sí, borrar también mi backup en Drive';
  static const confirmarFinal = 'Sí, borrar datos locales';
  static const fraseNoCoincide = 'El texto no coincide. Copialo tal cual.';
  static const ingresaPassword = 'Ingresá tu contraseña';
  static String passwordIncorrecta(int restantes) => restantes == 1
      ? 'Contraseña incorrecta. Te queda 1 intento.'
      : 'Contraseña incorrecta. Te quedan $restantes intentos.';
  static const sinConexion =
      'Sin conexión. La contraseña se valida en este teléfono y los datos se borran igual.';

  /// Propuesta: cuenta de Google sin envoltorio por contraseña (la HU y el issue dicen «solo la
  /// frase»; el texto es nuestro).
  static const sinPassword =
      'Tu cuenta entra con Google y no tiene contraseña en este teléfono: alcanza con la frase.';

  /// Propuesta: sin nombre no se puede armar la frase (el nombre de la cuenta llega con #243).
  static const sinNombre =
      'No pudimos armar la frase de confirmación porque todavía no tenemos tu nombre en este '
      'teléfono. Por ahora no se puede borrar desde acá.';

  static const noCierresLaApp = 'No cierres la app.';
  static const driveSinConexion =
      'No pudimos borrar el backup remoto; intentalo más tarde desde Drive.';
  static const driveFallo =
      'Tus datos locales se eliminaron. No pudimos borrar el backup en Drive; eliminalo '
      'manualmente desde drive.google.com o reintentá.';

  /// Artboard 08, solo cuando es cierto: no se tocó nada.
  static const errorNoSeBorroNada = 'No se borró nada y tu sesión sigue abierta. Probá de nuevo.';

  /// Artboard 08 cuando el borrado pudo haber empezado: no se promete que no se borró nada.
  static const errorBorrado =
      'No pudimos terminar de borrar los datos de este teléfono. Reintentá.';
}

enum _Fase { resumen, confirmacion, borrando, fallaDrive, error }

class _BorrarDatosLocalesPageState extends ConsumerState<BorrarDatosLocalesPage> {
  _Fase _fase = _Fase.resumen;

  ResumenDatosLocales? _resumen;
  Failure? _falloResumen;
  bool _recontando = false;
  int _cargaActual = 0;

  bool _soloEsteTelefono = false;
  bool _irreversible = false;

  bool _sincronizando = false;
  String? _avisoSincronizacion;

  bool _incluirDrive = false;
  PasoBorrado _paso = PasoBorrado.borrandoDatos;
  ResultadoBorradoDatosLocales? _resultado;
  String _mensajeError = TextosBorrado.errorBorrado;

  /// El borrado ya empezó y falló a mitad: el reintento no vuelve a contar pendientes.
  bool _yaEmpezo = false;

  @override
  void initState() {
    super.initState();
    // Un borrado que ya empezó y falló a mitad (el usuario tocó «Volver» y reentró): la DB puede
    // estar cerrada y el conteo daría «no se pudo contar» sin salida. Se sigue en «terminar el
    // borrado», que es idempotente.
    final empezado = ref.read(borradoEmpezadoProvider);
    if (empezado != null) {
      _yaEmpezo = true;
      _incluirDrive = empezado.incluirBackupDrive;
      _fase = _Fase.error;
      return;
    }
    unawaited(_cargar());
  }

  /// Cuenta lo que hay en el teléfono. Si llegan dos conteos seguidos, vale el último.
  Future<void> _cargar() async {
    final id = ++_cargaActual;
    setState(() {
      _recontando = true;
      _falloResumen = null;
    });
    final r = await ref.read(obtenerResumenDatosLocalesUseCaseProvider)(const NoParams());
    if (!mounted || id != _cargaActual) return;
    setState(() {
      _recontando = false;
      r.fold((f) {
        // Sin conteo nuevo no se queda mostrando el viejo: sería un número que ya no es cierto.
        _falloResumen = f;
        _resumen = null;
      }, (resumen) => _resumen = resumen);
    });
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() {
      _sincronizando = true;
      _avisoSincronizacion = null;
    });
    final r = await ref.read(sincronizarAhoraUseCaseProvider)(const NoParams());
    if (!mounted) return;
    setState(() {
      _sincronizando = false;
      _avisoSincronizacion = r.fold((f) => f.mensaje, (_) => null);
    });
    // Termine como termine, se vuelve a contar: lo que importa es lo que quedó.
    await _cargar();
    if (!mounted) return;
    final quedan = _resumen?.operacionesSinSincronizar;
    if (r.isRight() && quedan != null && quedan > 0) {
      setState(() => _avisoSincronizacion = TextosBorrado.quedanSinSubir);
    }
  }

  Future<void> _borrar({required bool incluirBackupDrive, required bool reintento}) async {
    if (_fase == _Fase.borrando) return;
    setState(() {
      _fase = _Fase.borrando;
      _paso = PasoBorrado.borrandoDatos;
      _incluirDrive = incluirBackupDrive;
    });
    final resultado = await ref
        .read(sesionProvider.notifier)
        .borrarDatosLocales(
          incluirBackupDrive: incluirBackupDrive,
          reintento: reintento,
          alAvanzar: (paso) {
            if (mounted) setState(() => _paso = paso);
          },
        );
    if (!mounted) return;
    _alTerminar(resultado);
  }

  void _alTerminar(Either<Failure, ResultadoBorradoDatosLocales> resultado) {
    resultado.fold(
      (falla) {
        if (falla is FailureBorradoConPendientes) {
          // Se sumó una operación entre el resumen y la confirmación: no se borró nada. Vuelve al
          // resumen, ya con el conteo nuevo y el bloqueo.
          setState(() {
            _fase = _Fase.resumen;
            _avisoSincronizacion = falla.mensaje;
          });
          unawaited(_cargar());
          return;
        }
        // Solo se promete que no se borró nada si no pudo empezar: la guarda del caso de uso.
        final nadaEmpezo = !_yaEmpezo && falla is FailureDatosLocalesIlegibles;
        // Que sobreviva a salir de la pantalla: al reentrar no hay que volver a contar.
        final empezado = ref.read(borradoEmpezadoProvider.notifier);
        if (nadaEmpezo) {
          empezado.limpiar();
        } else {
          empezado.marcar(incluirBackupDrive: _incluirDrive);
        }
        setState(() {
          _fase = _Fase.error;
          _yaEmpezo = !nadaEmpezo;
          _mensajeError = nadaEmpezo
              ? TextosBorrado.errorNoSeBorroNada
              : TextosBorrado.errorBorrado;
        });
      },
      (r) {
        // Lo local terminó de borrarse: ya no hay un borrado a medias que retomar.
        ref.read(borradoEmpezadoProvider.notifier).limpiar();
        // Si la jornada quedó en memoria (sin DB abierta, ver `jornadaLocalDataSourceProvider`),
        // sin esto el próximo login mostraría datos que la pantalla acaba de decir que se
        // borraron. Con la DB, borrarla ya se los llevó. Después del frame: en este, la pantalla de
        // jornada que está debajo reanuda sus providers mientras se reconstruye, y una
        // invalidación en el medio dispara un rebuild durante el build.
        final container = ProviderScope.containerOf(context, listen: false);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => container.invalidate(jornadaLocalDataSourceProvider),
        );
        if (r == ResultadoBorradoDatosLocales.completo) {
          _irAlLogin();
          return;
        }
        // Lo local ya se borró y no se restaura: de acá solo se reintenta Drive o se va al login.
        setState(() {
          _fase = _Fase.fallaDrive;
          _resultado = r;
          _yaEmpezo = true;
        });
      },
    );
  }

  /// La raíz ya muestra el login (la sesión es `null`); solo queda sacar esta pantalla.
  void _irAlLogin() => Navigator.of(context).popUntil((route) => route.isFirst);

  void _alVolver(bool didPop, Object? resultado) {
    if (didPop) return;
    switch (_fase) {
      case _Fase.confirmacion:
        setState(() => _fase = _Fase.resumen);
      case _Fase.fallaDrive:
        _irAlLogin();
      case _Fase.resumen || _Fase.borrando || _Fase.error:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final enBorrado = _fase == _Fase.borrando || _fase == _Fase.fallaDrive;

    // Mientras borra no se puede salir: el "atrás" dejaría el borrado corriendo sin nadie que
    // muestre cómo terminó. Con los datos ya borrados (falla de Drive) tampoco hay a dónde volver
    // que no sea el login.
    return PopScope(
      canPop: _fase == _Fase.resumen || _fase == _Fase.error,
      onPopInvokedWithResult: _alVolver,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (!enBorrado) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    key: const Key('borrar_datos_atras'),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _fase == _Fase.confirmacion
                      ? 'PRIVACIDAD Y DATOS · CONFIRMACIÓN FINAL'
                      : 'PRIVACIDAD Y DATOS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorEncabezado(theme, colores),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  header: true,
                  child: Text(
                    _fase == _Fase.confirmacion ? 'Confirmá el borrado' : 'Borrar datos locales',
                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 48),
              _cuerpo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    final resumen = _resumen;
    return switch (_fase) {
      _Fase.resumen when resumen == null && _falloResumen == null => const _Cargando(
        key: Key('borrar_datos_cargando'),
      ),
      _Fase.resumen when resumen == null => _ErrorResumen(
        mensaje: const FailureDatosLocalesIlegibles().mensaje,
        recontando: _recontando,
        onReintentar: _cargar,
      ),
      _Fase.resumen => ResumenBorrado(
        resumen: resumen!,
        soloEsteTelefono: _soloEsteTelefono,
        irreversible: _irreversible,
        sincronizando: _sincronizando,
        recontando: _recontando,
        avisoSincronizacion: _avisoSincronizacion,
        onSoloEsteTelefono: (v) => setState(() => _soloEsteTelefono = v),
        onIrreversible: (v) => setState(() => _irreversible = v),
        onSincronizar: _sincronizar,
        onReintentarConteo: _cargar,
        onContinuar: () => setState(() => _fase = _Fase.confirmacion),
      ),
      _Fase.confirmacion => ConfirmacionFinalBorrado(
        resumen: resumen!,
        // "Cancelar": no se borra nada y se vuelve a Configuración.
        onCancelar: () => Navigator.of(context).pop(),
        onConfirmado: ({required incluirBackupDrive}) =>
            unawaited(_borrar(incluirBackupDrive: incluirBackupDrive, reintento: false)),
      ),
      _Fase.borrando => BorrandoDatos(paso: _paso),
      _Fase.fallaDrive => FallaBackupDrive(
        mensaje: _resultado == ResultadoBorradoDatosLocales.backupDriveNoBorradoSinConexion
            ? TextosBorrado.driveSinConexion
            : TextosBorrado.driveFallo,
        reintentando: false,
        onReintentar: () => unawaited(_borrar(incluirBackupDrive: true, reintento: true)),
        onIrAlLogin: _irAlLogin,
      ),
      _Fase.error => ErrorAlBorrar(
        mensaje: _mensajeError,
        // Reintentar es seguro: el borrado es idempotente.
        onReintentar: () =>
            unawaited(_borrar(incluirBackupDrive: _incluirDrive, reintento: _yaEmpezo)),
        onVolver: () => Navigator.of(context).pop(),
      ),
    };
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Revisando los datos de este teléfono…', textAlign: TextAlign.center),
      ],
    ),
  );
}

class _ErrorResumen extends StatelessWidget {
  const _ErrorResumen({
    required this.mensaje,
    required this.recontando,
    required this.onReintentar,
  });

  final String mensaje;
  final bool recontando;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('borrar_datos_error_resumen'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(child: Icon(Icons.error_outline, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('borrar_datos_reintentar_resumen'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: recontando ? null : onReintentar,
        child: const Text('Reintentar'),
      ),
    ],
  );
}
