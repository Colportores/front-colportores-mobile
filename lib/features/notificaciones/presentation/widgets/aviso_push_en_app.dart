import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/entities/tipo_notificacion.dart';
import '../providers/push_remotas_providers.dart';

/// Los textos del aviso con la app abierta (24C·08). El canvas dibuja «AHORA» y «Tocá para ver el
/// detalle»; el nombre de la ✕ para el lector de pantalla es propuesta.
abstract final class TextosAvisoPushEnApp {
  static const ahora = 'AHORA';
  static const tocarParaVerElDetalle = 'Tocá para ver el detalle';
  static const cerrar = 'Cerrar aviso';
}

/// Cuánto queda a la vista el aviso si nadie lo toca. El aviso no se pierde al irse: queda en el
/// centro de notificaciones. Con lector de pantalla o con el foco en el aviso no se va solo: espera a
/// que se cierre (WCAG 2.2.1, «Deshacer AA», 21/10).
const duracionAvisoPushEnApp = Duration(seconds: 8);

const _bordeAviso = Color(0xFFCFD6E1);
const _sombraAviso = Color(0x240E1A2B);
const _fondoGlifo = Color(0xFFE6EEF8);
const _azul = Color(0xFF002856);
const _cierre = Color(0xFF5B6B82);

/// El aviso sutil de una push que llega con la app abierta (HU-NOT-003, vista 24, 24C·08): una
/// tarjeta arriba con el glifo, «AHORA», el título y, si el aviso lleva a algún lado, «Tocá para ver
/// el detalle». Tocarla abre el aviso; la ✕ la cierra y el aviso queda en el centro.
class AvisoPushEnApp extends StatelessWidget {
  const AvisoPushEnApp({
    super.key,
    required this.aviso,
    required this.onAbrir,
    required this.onCerrar,
    this.focoAbrir,
    this.focoCerrar,
  });

  final Notificacion aviso;
  final VoidCallback onAbrir;
  final VoidCallback onCerrar;

  /// Los nodos de foco de la tarjeta y de la ✕, si quien la pone necesita llevarles el foco del
  /// teclado (`AvisoPushEnAppHost`).
  final FocusNode? focoAbrir;
  final FocusNode? focoCerrar;

  IconData get _icono => switch (aviso.tipo) {
    TipoNotificacion.recordatorioVisita => Icons.event_note_outlined,
    TipoNotificacion.pedidoAutorizado || TipoNotificacion.ticketValidado => Icons.check,
    TipoNotificacion.ticketRechazado => Icons.close,
    TipoNotificacion.asignacionCampania => Icons.place_outlined,
    TipoNotificacion.cuotaPendiente => Icons.payments_outlined,
    TipoNotificacion.agendaManana => Icons.event_note_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final segundaLinea = aviso.detalle?.isNotEmpty ?? false
        ? aviso.detalle
        : (aviso.destino != null ? TextosAvisoPushEnApp.tocarParaVerElDetalle : null);

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _bordeAviso, width: 1.5),
          boxShadow: const [BoxShadow(color: _sombraAviso, blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  container: true,
                  label: [TextosAvisoPushEnApp.ahora, aviso.titulo, ?segundaLinea].join('. '),
                  onTap: onAbrir,
                  excludeSemantics: true,
                  child: InkWell(
                    key: const Key('aviso_push_en_app_abrir'),
                    focusNode: focoAbrir,
                    onTap: onAbrir,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        child: Row(
                          spacing: 12,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _fondoGlifo,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_icono, size: 18, color: _azul),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 2,
                                children: [
                                  Text(
                                    TextosAvisoPushEnApp.ahora,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colores.gris,
                                      letterSpacing: .4,
                                    ),
                                  ),
                                  Text(
                                    aviso.titulo,
                                    // Un nombre largo (la campaña) no deja el aviso ocupando media
                                    // pantalla; el texto entero está en el centro y en el lector.
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  if (segundaLinea != null)
                                    Text(
                                      segundaLinea,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colores.gris,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Sin `IconButton`: su tooltip pide un `Overlay` y este aviso va arriba del navegador.
              Semantics(
                button: true,
                label: TextosAvisoPushEnApp.cerrar,
                onTap: onCerrar,
                excludeSemantics: true,
                child: InkResponse(
                  key: const Key('aviso_push_en_app_cerrar'),
                  focusNode: focoCerrar,
                  onTap: onCerrar,
                  radius: 24,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.close, size: 20, color: _cierre),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pone el aviso de las push con la app abierta arriba de toda la app (24C·08), sobre cualquier
/// pantalla. Va en el `builder` de `MaterialApp`.
///
/// Un aviso nuevo reemplaza al anterior (el anterior queda en el centro). [activo] es `false` sin
/// sesión: lo que estuviera a la vista se saca y no sale nada.
///
/// Teclado externo (WCAG 2.1.1): el aviso está fuera de la pantalla, así que el Tab de la pantalla no
/// lo recorre. Mientras está a la vista, el primer Tab lleva el foco a la tarjeta, el siguiente a la
/// ✕, y el siguiente devuelve el foco a lo que lo tenía (Mayús+Tab recorre al revés).
///
/// Se va solo a los [duracionAvisoPushEnApp], salvo con lector de pantalla encendido o con el foco
/// adentro: ahí se queda hasta que la persona lo cierre o lo abra.
class AvisoPushEnAppHost extends ConsumerStatefulWidget {
  const AvisoPushEnAppHost({super.key, required this.activo, required this.child});

  final bool activo;
  final Widget child;

  @override
  ConsumerState<AvisoPushEnAppHost> createState() => _AvisoPushEnAppHostState();
}

class _AvisoPushEnAppHostState extends ConsumerState<AvisoPushEnAppHost> {
  StreamSubscription<Notificacion>? _suscripcion;
  Timer? _temporizador;
  Notificacion? _aviso;
  bool _abriendo = false;

  /// El foco del teclado está en el aviso.
  bool _conFoco = false;

  /// Pasaron los segundos del aviso mientras tenía el foco: se va apenas lo suelte.
  bool _vencido = false;

  /// El foco del teclado: el ámbito del aviso (su propio recorrido con Tab), sus dos controles y lo
  /// que tenía el foco antes de entrar, para devolvérselo al salir.
  final _ambito = FocusScopeNode(debugLabel: 'aviso_push_en_app');
  final _focoAbrir = FocusNode(debugLabel: 'aviso_push_en_app_abrir');
  final _focoCerrar = FocusNode(debugLabel: 'aviso_push_en_app_cerrar');
  FocusNode? _focoPrevio;

  @override
  void initState() {
    super.initState();
    _suscripcion = ref.read(canalAvisosPushProvider).avisos.listen(_mostrar);
  }

  @override
  void didUpdateWidget(AvisoPushEnAppHost anterior) {
    super.didUpdateWidget(anterior);
    if (!widget.activo && _aviso != null) _sacar();
  }

  @override
  void dispose() {
    unawaited(_suscripcion?.cancel());
    _temporizador?.cancel();
    _ambito.dispose();
    _focoAbrir.dispose();
    _focoCerrar.dispose();
    super.dispose();
  }

  void _mostrar(Notificacion aviso) {
    if (!widget.activo || !mounted) return;
    _temporizador?.cancel();
    _temporizador = null;
    _vencido = false;
    // Con un lector de pantalla no hay cuenta regresiva: la persona decide cuándo lo cierra.
    final conLector = MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    if (!conLector) {
      _temporizador = Timer(duracionAvisoPushEnApp, () {
        if (!mounted || _aviso?.id != aviso.id) return;
        if (_conFoco) {
          _vencido = true;
        } else {
          _sacar();
        }
      });
    }
    setState(() => _aviso = aviso);
  }

  void _sacar() {
    _temporizador?.cancel();
    _temporizador = null;
    _vencido = false;
    _conFoco = false;
    _devolverElFoco();
    if (mounted) setState(() => _aviso = null);
  }

  /// Si el foco estaba en el aviso, vuelve a lo que lo tenía antes (el aviso se va y no puede
  /// llevárselo).
  void _devolverElFoco() {
    final previo = _focoPrevio;
    _focoPrevio = null;
    if (!_ambito.hasFocus) return;
    if (previo != null && previo.context != null && previo.canRequestFocus) {
      previo.requestFocus();
    } else {
      _ambito.unfocus();
    }
  }

  /// Tab con el aviso a la vista (WCAG 2.1.1). Va en un `Focus` por encima de la pantalla, así que
  /// ve las teclas antes que el recorrido de la ruta.
  KeyEventResult _alTeclear(FocusNode nodo, KeyEvent evento) {
    if (_aviso == null || evento is! KeyDownEvent || evento.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final conMayus = HardwareKeyboard.instance.isShiftPressed;
    if (!_ambito.hasFocus) {
      if (conMayus) return KeyEventResult.ignored;
      _focoPrevio = FocusManager.instance.primaryFocus;
      _focoAbrir.requestFocus();
      return KeyEventResult.handled;
    }
    final primario = FocusManager.instance.primaryFocus;
    if ((!conMayus && primario == _focoCerrar) || (conMayus && primario == _focoAbrir)) {
      _devolverElFoco();
      return KeyEventResult.handled;
    }
    // Entre la tarjeta y la ✕ sigue el recorrido normal, dentro del ámbito del aviso.
    return KeyEventResult.ignored;
  }

  void _alCambiarFoco(bool tieneFoco) {
    _conFoco = tieneFoco;
    if (!tieneFoco && _vencido) _sacar();
  }

  Future<void> _abrir(Notificacion aviso) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      // Se saca antes de abrir: el destino no queda tapado por el aviso que lo abrió.
      _sacar();
      await ref.read(abridorAvisoPushProvider)(aviso);
    } on Object catch (e) {
      AppLogger.instance.warn(LogModulo.push, 'PUSH_ABRIR_FAIL', 'no se pudo abrir el aviso', {
        'tipo': e.runtimeType.toString(),
      });
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = _aviso;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _alTeclear,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (aviso != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: FocusScope(
                    node: _ambito,
                    onFocusChange: _alCambiarFoco,
                    child: AvisoPushEnApp(
                      key: ValueKey(aviso.id),
                      aviso: aviso,
                      focoAbrir: _focoAbrir,
                      focoCerrar: _focoCerrar,
                      onAbrir: () => unawaited(_abrir(aviso)),
                      onCerrar: _sacar,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
