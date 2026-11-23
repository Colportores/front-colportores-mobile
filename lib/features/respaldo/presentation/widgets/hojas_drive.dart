import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/presentation/hoja_inferior.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/estado_respaldo_drive.dart';
import '../providers/respaldo_drive_providers.dart';
import '../textos_respaldo_drive.dart';
import 'aviso_drive.dart';

/// Abre la hoja «Respaldo en tu Google Drive» (16D·02, 03, 08 y 09). Devuelve cómo terminó el
/// intento ([DriveQuedoConectado]; [DriveQuedoEnOtraCuenta] si Google devolvió otra cuenta que la del
/// respaldo anterior, 16E·01; o [DriveNoQuedoConectado] con [FailureDriveCancelado] si la persona
/// cerró la pantalla de Google), o `null` si tocó «Ahora no».
///
/// Con [conPrimerRespaldo] en `false` la conexión no hace el primer respaldo («Recuperar mi
/// respaldo», 16G·03, #707).
Future<ResultadoConexionDrive?> mostrarHojaConectarDrive(
  BuildContext context, {
  bool conPrimerRespaldo = true,
}) => mostrarHojaInferior<ResultadoConexionDrive>(
  context: context,
  isScrollControlled: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaConectarDrive(conPrimerRespaldo: conPrimerRespaldo),
);

/// Abre la hoja «¿Desconectar Google Drive?» (16D·05). Devuelve `true` si quedó desconectado.
Future<bool?> mostrarHojaDesconectarDrive(BuildContext context) => mostrarHojaInferior<bool>(
  context: context,
  isScrollControlled: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => const HojaDesconectarDrive(),
);

/// Cómo terminó la hoja de otra cuenta de Google (16E·01 a 16E·04).
sealed class ResultadoOtraCuentaDrive {
  const ResultadoOtraCuentaDrive();
}

/// Volvió a la cuenta del respaldo anterior (16E·03): [correo] es esa cuenta.
final class VolvioALaCuentaAnterior extends ResultadoOtraCuentaDrive {
  const VolvioALaCuentaAnterior(this.correo);

  final String correo;
}

/// Siguió con la cuenta nueva (16E·02). [primerRespaldoHecho] dice qué se le avisa.
final class SiguioConLaCuentaNueva extends ResultadoOtraCuentaDrive {
  const SiguioConLaCuentaNueva({required this.primerRespaldoHecho});

  final bool primerRespaldoHecho;
}

/// Abre la hoja «Esta no es la cuenta de tu respaldo» (16E·01 a 16E·04). Devuelve con qué cuenta
/// quedó la persona, o `null` si la cerró sin elegir: el respaldo sigue frenado y la fila lo dice.
Future<ResultadoOtraCuentaDrive?> mostrarHojaOtraCuentaDrive(
  BuildContext context, {
  required DriveCuentaPorConfirmar cuenta,
}) => mostrarHojaInferior<ResultadoOtraCuentaDrive>(
  context: context,
  isScrollControlled: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaOtraCuentaDrive(cuenta: cuenta),
);

enum _FaseConectar { previa, conectando, error, sinConexion }

/// La explicación de que los archivos van cifrados y, abajo, «Conectar con Google». Mientras la
/// persona está en la pantalla de Google la hoja no se puede cerrar ni se puede tocar dos veces.
/// Si falla, queda abierta con el aviso y «Reintentar»; sin conexión, el botón espera a que vuelva.
class HojaConectarDrive extends ConsumerStatefulWidget {
  const HojaConectarDrive({this.conPrimerRespaldo = true, super.key});

  /// Si la conexión hace el primer respaldo; `false` en «Recuperar mi respaldo» (16G·03, #707).
  final bool conPrimerRespaldo;

  @override
  ConsumerState<HojaConectarDrive> createState() => _HojaConectarDriveState();
}

class _HojaConectarDriveState extends ConsumerState<HojaConectarDrive> {
  _FaseConectar _fase = _FaseConectar.previa;
  String _mensajeDeError = TextosRespaldoDrive.sinConexion;

  Future<void> _conectar() async {
    if (_fase == _FaseConectar.conectando) return; // Doble toque: una sola conexión.
    setState(() => _fase = _FaseConectar.conectando);
    ResultadoConexionDrive resultado;
    try {
      resultado = await ref
          .read(estadoRespaldoDriveProvider.notifier)
          .conectar(conPrimerRespaldo: widget.conPrimerRespaldo);
    } on Object {
      resultado = const DriveNoQuedoConectado(FailureDriveNoConectado());
    }
    if (!mounted) return;
    switch (resultado) {
      case DriveQuedoConectado() || DriveQuedoEnOtraCuenta():
        Navigator.of(context).pop(resultado);
      case DriveNoQuedoConectado(falla: FailureDriveCancelado()):
        Navigator.of(context).pop(resultado);
      case DriveNoQuedoConectado(:final falla):
        setState(() {
          _fase = falla is FailureSinConexion ? _FaseConectar.sinConexion : _FaseConectar.error;
          _mensajeDeError = falla.mensaje;
        });
      case DriveOcupado():
        setState(() => _fase = _FaseConectar.previa);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final conectando = _fase == _FaseConectar.conectando;
    final sinRedDelTelefono = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final sinRed = sinRedDelTelefono || _fase == _FaseConectar.sinConexion;
    final conError = _fase == _FaseConectar.error && !sinRed;

    return PopScope(
      canPop: !conectando,
      child: _MarcoHoja(
        clave: const Key('drive_hoja_conectar'),
        titulo: TextosRespaldoDrive.tituloConectar,
        hijos: [
          Text(
            TextosRespaldoDrive.explicacionCifrado,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          // El canvas (16D·08 y 16D·09) cambia esta línea por el aviso.
          if (!sinRed && !conError)
            Text(
              TextosRespaldoDrive.cadaNoche,
              style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
            ),
          if (sinRed)
            const AvisoDrive(
              key: Key('drive_hoja_sin_conexion'),
              clase: ClaseAvisoDrive.sinConexion,
              texto: TextosRespaldoDrive.sinConexion,
            )
          else if (conError)
            AvisoDrive(
              key: const Key('drive_hoja_error'),
              clase: ClaseAvisoDrive.error,
              texto: _mensajeDeError,
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _BotonHoja(
                clave: const Key('drive_conectar'),
                texto: conectando
                    ? TextosRespaldoDrive.conectando
                    : conError
                    ? TextosRespaldoDrive.reintentar
                    : TextosRespaldoDrive.conectarConGoogle,
                principal: true,
                cargando: conectando,
                // Sin red el botón espera a que vuelva: no hay a dónde ir (16D·08). Si la red falló en
                // pleno intento pero el teléfono dice que hay, se puede reintentar.
                onPressed: conectando || sinRedDelTelefono ? null : _conectar,
                apagadoSinCarga: sinRedDelTelefono && !conectando,
              ),
              if (!conectando)
                _BotonHoja(
                  clave: const Key('drive_ahora_no'),
                  texto: TextosRespaldoDrive.ahoraNo,
                  principal: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _FaseDesconectar { confirmar, desconectando, error }

/// «¿Desconectar Google Drive?»: dice que los respaldos paran y que las copias que ya están en el
/// Drive no se borran. Mientras desconecta no se puede cerrar ni tocar dos veces; si falla, queda
/// abierta con el aviso y «Reintentar».
class HojaDesconectarDrive extends ConsumerStatefulWidget {
  const HojaDesconectarDrive({super.key});

  @override
  ConsumerState<HojaDesconectarDrive> createState() => _HojaDesconectarDriveState();
}

class _HojaDesconectarDriveState extends ConsumerState<HojaDesconectarDrive> {
  _FaseDesconectar _fase = _FaseDesconectar.confirmar;

  Future<void> _desconectar() async {
    if (_fase == _FaseDesconectar.desconectando) return; // Doble toque: una sola vez.
    setState(() => _fase = _FaseDesconectar.desconectando);
    ResultadoDesconexionDrive resultado;
    try {
      resultado = await ref.read(estadoRespaldoDriveProvider.notifier).desconectar();
    } on Object {
      resultado = const DriveNoQuedoDesconectado(FailureInesperado());
    }
    if (!mounted) return;
    switch (resultado) {
      case DriveQuedoDesconectado():
        Navigator.of(context).pop(true);
      case DriveNoQuedoDesconectado():
        setState(() => _fase = _FaseDesconectar.error);
      case DriveOcupado():
        setState(() => _fase = _FaseDesconectar.confirmar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desconectando = _fase == _FaseDesconectar.desconectando;
    return PopScope(
      canPop: !desconectando,
      child: _MarcoHoja(
        clave: const Key('drive_hoja_desconectar'),
        titulo: TextosRespaldoDrive.tituloDesconectar,
        hijos: [
          Text(
            TextosRespaldoDrive.textoDesconectar,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          if (_fase == _FaseDesconectar.error)
            const AvisoDrive(
              key: Key('drive_hoja_error_desconectar'),
              clase: ClaseAvisoDrive.error,
              texto: TextosRespaldoDrive.noPudimosDesconectar,
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _BotonHoja(
                clave: const Key('drive_desconectar'),
                texto: switch (_fase) {
                  _FaseDesconectar.desconectando => TextosRespaldoDrive.desconectando,
                  _FaseDesconectar.error => TextosRespaldoDrive.reintentar,
                  _FaseDesconectar.confirmar => TextosRespaldoDrive.desconectar,
                },
                principal: true,
                peligro: true,
                cargando: desconectando,
                onPressed: desconectando ? null : _desconectar,
              ),
              _BotonHoja(
                clave: const Key('drive_desconectar_cancelar'),
                texto: TextosRespaldoDrive.cancelar,
                principal: false,
                onPressed: desconectando ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PasoOtraCuenta { avisar, confirmarSeguir }

enum _AccionOtraCuenta { volver, seguir }

/// «Esta no es la cuenta de tu respaldo» (16E·01): sale apenas vuelve del consentimiento de Google, con
/// la cuenta del respaldo anterior, su último respaldo y la de ahora. Dos salidas: «Volver a la cuenta
/// anterior» (abre de nuevo el selector de cuentas de Google; 16E·03) o «Seguir con la cuenta nueva»,
/// que antes pide confirmar qué pasa (16E·02). Nada se borra.
///
/// Mientras trabaja la hoja no se puede cerrar ni tocar dos veces. Sin conexión, «Volver» espera a que
/// vuelva (16E·04). Si falla, queda abierta con el aviso. Cerrarla sin elegir deja la fila «Cuenta
/// Drive» pendiente: tocarla vuelve a abrir esta hoja.
class HojaOtraCuentaDrive extends ConsumerStatefulWidget {
  const HojaOtraCuentaDrive({required this.cuenta, super.key});

  final DriveCuentaPorConfirmar cuenta;

  @override
  ConsumerState<HojaOtraCuentaDrive> createState() => _HojaOtraCuentaDriveState();
}

class _HojaOtraCuentaDriveState extends ConsumerState<HojaOtraCuentaDrive> {
  _PasoOtraCuenta _paso = _PasoOtraCuenta.avisar;

  /// Lo que está haciendo ahora, o `null`. Es un campo y no solo el estado: la guarda corta el
  /// segundo toque aunque llegue antes de que se vuelva a dibujar.
  _AccionOtraCuenta? _trabajando;

  /// La cuenta de ahora: cambia si, al volver, la persona elige otra distinta de la anterior.
  late DriveCuentaPorConfirmar _cuenta = widget.cuenta;

  /// El aviso de que algo falló, con su mensaje; `null` si no hay falla. El de sin conexión del
  /// teléfono no pasa por acá (sale de [conexionProvider]).
  String? _error;
  bool _errorDeRed = false;

  Future<void> _volver() async {
    if (_trabajando != null) return; // Doble toque: una sola conexión.
    setState(() {
      _trabajando = _AccionOtraCuenta.volver;
      _error = null;
      _errorDeRed = false;
    });
    ResultadoConexionDrive resultado;
    try {
      resultado = await ref.read(estadoRespaldoDriveProvider.notifier).conectar();
    } on Object {
      resultado = const DriveNoQuedoConectado(FailureDriveNoConectado());
    }
    if (!mounted) return;
    switch (resultado) {
      case DriveQuedoConectado():
        Navigator.of(context).pop(VolvioALaCuentaAnterior(_cuenta.anteriorEmail));
        return;
      case DriveQuedoEnOtraCuenta(:final estado):
        // Eligió otra cuenta que tampoco es la anterior: la hoja sigue con la que eligió ahora.
        setState(() => _cuenta = estado);
      case DriveNoQuedoConectado(falla: FailureDriveCancelado()):
        break; // Cerró la pantalla de Google: la hoja sigue como estaba.
      case DriveNoQuedoConectado(:final falla):
        setState(() {
          _error = falla is FailureSinConexion
              ? TextosRespaldoDrive.sinConexionParaCambiarDeCuenta
              : falla.mensaje;
          _errorDeRed = falla is FailureSinConexion;
        });
      case DriveOcupado():
        break;
    }
    setState(() => _trabajando = null);
  }

  Future<void> _seguir() async {
    if (_trabajando != null) return; // Doble toque: una sola vez.
    setState(() {
      _trabajando = _AccionOtraCuenta.seguir;
      _error = null;
      _errorDeRed = false;
    });
    ResultadoConexionDrive resultado;
    try {
      resultado = await ref.read(estadoRespaldoDriveProvider.notifier).confirmarCuentaNueva();
    } on Object {
      resultado = const DriveNoQuedoConectado(FailureDriveNoConectado());
    }
    if (!mounted) return;
    switch (resultado) {
      case DriveQuedoConectado(:final primerRespaldoHecho):
        Navigator.of(context).pop(SiguioConLaCuentaNueva(primerRespaldoHecho: primerRespaldoHecho));
        return;
      case DriveNoQuedoConectado(:final falla):
        setState(() => _error = falla.mensaje);
      case DriveQuedoEnOtraCuenta() || DriveOcupado():
        break;
    }
    setState(() => _trabajando = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final trabajando = _trabajando != null;
    final confirmando = _paso == _PasoOtraCuenta.confirmarSeguir;
    final sinRedDelTelefono = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final sinRed = sinRedDelTelefono || _errorDeRed;
    final conError = _error != null && !_errorDeRed;
    final ultimo = ref.watch(ultimoRespaldoDriveProvider).value;
    final anterior = _cuenta.anteriorEmail;
    final nueva = _cuenta.email;

    return PopScope(
      // Sin elegir se puede cerrar; en la confirmación, el atrás vuelve a la hoja anterior.
      canPop: !trabajando && !confirmando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !trabajando && confirmando) {
          setState(() {
            _paso = _PasoOtraCuenta.avisar;
            _error = null;
            _errorDeRed = false;
          });
        }
      },
      child: _MarcoHoja(
        clave: Key(confirmando ? 'drive_hoja_seguir_con_la_nueva' : 'drive_hoja_otra_cuenta'),
        titulo: confirmando
            ? TextosRespaldoDrive.tituloSeguirConLaNueva
            : TextosRespaldoDrive.tituloOtraCuenta,
        hijos: [
          Text(
            confirmando
                ? TextosRespaldoDrive.textoSeguirConLaNueva(anterior: anterior, nueva: nueva)
                : TextosRespaldoDrive.textoOtraCuenta(anterior: anterior, nueva: nueva),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          if (!confirmando) ...[
            _FilasDeCuentas(
              filas: [
                (TextosRespaldoDrive.rotuloRespaldoAnterior, anterior),
                (
                  TextosRespaldoDrive.rotuloUltimoRespaldo,
                  ultimo == null
                      ? TextosRespaldoDrive.sinRespaldoTodavia
                      : TextosRespaldoDrive.fechaDelUltimoRespaldo(ultimo.toLocal()),
                ),
                (TextosRespaldoDrive.rotuloCuentaDeAhora, nueva),
              ],
            ),
            Text(
              TextosRespaldoDrive.noSeBorraNada,
              style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
            ),
          ],
          if (sinRed)
            const AvisoDrive(
              key: Key('drive_hoja_otra_cuenta_sin_conexion'),
              clase: ClaseAvisoDrive.sinConexion,
              texto: TextosRespaldoDrive.sinConexionParaCambiarDeCuenta,
            )
          else if (conError)
            AvisoDrive(
              key: const Key('drive_hoja_otra_cuenta_error'),
              clase: ClaseAvisoDrive.error,
              texto: _error!,
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              if (!confirmando) ...[
                _BotonHoja(
                  clave: const Key('drive_otra_cuenta_volver'),
                  texto: TextosRespaldoDrive.volverALaCuentaAnterior,
                  principal: true,
                  cargando: _trabajando == _AccionOtraCuenta.volver,
                  // Sin red no hay a dónde ir (16E·04): el botón espera a que vuelva.
                  onPressed: trabajando || sinRedDelTelefono ? null : _volver,
                  apagadoSinCarga: sinRedDelTelefono && !trabajando,
                ),
                _BotonHoja(
                  clave: const Key('drive_otra_cuenta_seguir'),
                  texto: TextosRespaldoDrive.seguirConLaCuentaNueva,
                  principal: false,
                  onPressed: trabajando
                      ? null
                      : () => setState(() {
                          _paso = _PasoOtraCuenta.confirmarSeguir;
                          _error = null;
                          _errorDeRed = false;
                        }),
                ),
              ] else ...[
                _BotonHoja(
                  clave: const Key('drive_otra_cuenta_confirmar_seguir'),
                  texto: TextosRespaldoDrive.seguirConLaCuentaNueva,
                  principal: true,
                  cargando: _trabajando == _AccionOtraCuenta.seguir,
                  onPressed: trabajando ? null : _seguir,
                ),
                _BotonHoja(
                  clave: const Key('drive_otra_cuenta_confirmar_volver'),
                  texto: TextosRespaldoDrive.volverALaAnterior,
                  principal: false,
                  cargando: _trabajando == _AccionOtraCuenta.volver,
                  onPressed: trabajando || sinRedDelTelefono ? null : _volver,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Las filas «rótulo · valor» de la hoja de otra cuenta (el bloque `kv` del canvas). Con la letra
/// grande el valor baja bajo su rótulo: un correo largo se lee entero y nunca se corta con «…».
class _FilasDeCuentas extends StatelessWidget {
  const _FilasDeCuentas({required this.filas});

  final List<(String, String)> filas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final letraGrande = MediaQuery.textScalerOf(context).scale(10) >= 13;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: colores.borde),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < filas.length; i++)
              Container(
                key: Key('drive_otra_cuenta_fila_$i'),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: colores.borde)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: letraGrande
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            filas[i].$1,
                            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                          ),
                          Text(filas[i].$2, style: theme.textTheme.bodyMedium),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        spacing: 12,
                        children: [
                          Text(
                            filas[i].$1,
                            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                          ),
                          Expanded(
                            child: Text(
                              filas[i].$2,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El marco de las hojas: el asa, el título y lo que sigue, en una columna que se desplaza con
/// texto grande o con poco alto.
class _MarcoHoja extends StatelessWidget {
  const _MarcoHoja({required this.clave, required this.titulo, required this.hijos});

  final Key clave;
  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return SingleChildScrollView(
      child: Padding(
        key: clave,
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Align(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colores.bordeInput,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Semantics(header: true, child: Text(titulo, style: theme.textTheme.headlineSmall)),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

class _BotonHoja extends StatelessWidget {
  const _BotonHoja({
    required this.clave,
    required this.texto,
    required this.principal,
    required this.onPressed,
    this.cargando = false,
    this.peligro = false,
    this.apagadoSinCarga = false,
  });

  final Key clave;
  final String texto;
  final bool principal;
  final bool cargando;
  final bool peligro;

  /// Apagado porque falta algo (la conexión), no porque esté trabajando.
  final bool apagadoSinCarga;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.extension<ColoresColportaje>()!;
    final escala = MediaQuery.textScalerOf(context).scale(15);
    final forma = escala > 20
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        : const StadiumBorder();
    const minimo = Size.fromHeight(52);
    final contenido = cargando
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: principal ? Colors.white : tema.colorScheme.primary,
                ),
              ),
              Flexible(child: Text(texto, textAlign: TextAlign.center)),
            ],
          )
        : Text(texto, textAlign: TextAlign.center);
    if (!principal) {
      return OutlinedButton(
        key: clave,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: minimo,
          shape: forma,
          side: BorderSide(color: colores.bordeInput),
        ),
        child: contenido,
      );
    }
    final base = peligro ? tema.colorScheme.error : tema.colorScheme.primary;
    return FilledButton(
      key: clave,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: minimo,
        shape: forma,
        backgroundColor: base,
        // Un botón apagado de Material pinta `onSurface` al 38 %: ilegible sobre el azul.
        disabledBackgroundColor: apagadoSinCarga
            ? colores.placeholder
            : base.withValues(alpha: .85),
        disabledForegroundColor: Colors.white,
      ),
      child: contenido,
    );
  }
}
