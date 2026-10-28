import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../providers/respaldo_drive_providers.dart';
import '../textos_respaldo_drive.dart';
import 'aviso_drive.dart';

/// Abre la hoja «Respaldo en tu Google Drive» (16D·02, 03, 08 y 09). Devuelve cómo terminó el
/// intento ([DriveQuedoConectado], o [DriveNoQuedoConectado] con [FailureDriveCancelado] si la
/// persona cerró la pantalla de Google), o `null` si tocó «Ahora no».
Future<ResultadoConexionDrive?> mostrarHojaConectarDrive(BuildContext context) =>
    showModalBottomSheet<ResultadoConexionDrive>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      showDragHandle: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const HojaConectarDrive(),
    );

/// Abre la hoja «¿Desconectar Google Drive?» (16D·05). Devuelve `true` si quedó desconectado.
Future<bool?> mostrarHojaDesconectarDrive(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => const HojaDesconectarDrive(),
);

enum _FaseConectar { previa, conectando, error, sinConexion }

/// La explicación de que los archivos van cifrados y, abajo, «Conectar con Google». Mientras la
/// persona está en la pantalla de Google la hoja no se puede cerrar ni se puede tocar dos veces.
/// Si falla, queda abierta con el aviso y «Reintentar»; sin conexión, el botón espera a que vuelva.
class HojaConectarDrive extends ConsumerStatefulWidget {
  const HojaConectarDrive({super.key});

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
      resultado = await ref.read(estadoRespaldoDriveProvider.notifier).conectar();
    } on Object {
      resultado = const DriveNoQuedoConectado(FailureDriveNoConectado());
    }
    if (!mounted) return;
    switch (resultado) {
      case DriveQuedoConectado():
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
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
