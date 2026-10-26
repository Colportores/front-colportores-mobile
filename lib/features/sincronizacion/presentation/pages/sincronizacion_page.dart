import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/sync/modo_ahorro_providers.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_sincronizacion.dart';
import '../formato_sincronizacion.dart';
import '../providers/sincronizacion_providers.dart';
import '../textos_sincronizacion.dart';
import '../widgets/componentes_sincronizacion.dart';
import '../widgets/hojas_sincronizacion.dart';

/// Sincronización y respaldo (vista 25, HU-SYNC-007 y HU-SYNC-008): cuándo se envió el avance,
/// cuántas operaciones esperan, cuándo llegó lo último del coordinador y cuándo fue el último
/// respaldo; «Actualizar ahora» (sube y baja todo en el momento), la lista de lo que el servidor
/// rechazó con su detalle y el modo ahorro de datos. Se entra desde Configuración.
class SincronizacionPage extends ConsumerStatefulWidget {
  const SincronizacionPage({super.key});

  static Route<void> ruta() => MaterialPageRoute<void>(builder: (_) => const SincronizacionPage());

  @override
  ConsumerState<SincronizacionPage> createState() => _SincronizacionPageState();
}

class _SincronizacionPageState extends ConsumerState<SincronizacionPage> {
  /// Mientras se guarda el cambio del modo ahorro: el interruptor no admite otro toque.
  bool _guardandoAhorro = false;

  /// El último cambio del modo ahorro no se pudo guardar.
  bool _ahorroNoGuardo = false;

  /// Mientras hay una hoja abierta: un segundo toque no abre otra encima.
  bool _hojaAbierta = false;

  /// Hace que «hace 3 min» siga siendo cierto con la pantalla abierta.
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Un fallo o un éxito de una vez anterior no se muestran como si fueran de ahora.
    scheduleMicrotask(() {
      if (mounted) ref.read(actualizacionProvider.notifier).olvidarResultado();
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  /// «Actualizar ahora». Con el modo ahorro y datos móviles pregunta antes (25-09); cerrar la hoja
  /// sin elegir es esperar al Wi-Fi.
  Future<void> _actualizar({bool todasLasFallidas = false, String? idFallida}) async {
    if (ref.read(actualizacionProvider) is Actualizando || _hojaAbierta) return;
    final conDatos =
        ref.read(modoAhorroProvider) &&
        ref.read(conexionProvider).value == TipoConexion.datosMoviles;
    if (conDatos) {
      _hojaAbierta = true;
      final ok = await mostrarHojaActualizarConDatos(context);
      _hojaAbierta = false;
      if (ok != true || !mounted) return;
    }
    await ref
        .read(actualizacionProvider.notifier)
        .actualizar(reintentarFallidas: todasLasFallidas, idFallida: idFallida);
  }

  Future<void> _verDetalle(OperacionFallida operacion) async {
    if (_hojaAbierta) return;
    _hojaAbierta = true;
    final reintentar = await mostrarHojaDetalleOperacion(context, operacion);
    _hojaAbierta = false;
    if (reintentar == true && mounted) await _actualizar(idFallida: operacion.id);
  }

  Future<void> _cambiarModoAhorro({required bool activo}) async {
    if (_guardandoAhorro) return;
    setState(() {
      _guardandoAhorro = true;
      _ahorroNoGuardo = false;
    });
    final guardado = await ref.read(modoAhorroProvider.notifier).cambiar(activo: activo);
    if (!mounted) return;
    setState(() {
      _guardandoAhorro = false;
      _ahorroNoGuardo = !guardado;
    });
  }

  void _avisarListo(ActualizacionCompleta resultado) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const Key('sincronizacion_listo'),
          content: Row(
            spacing: 12,
            children: [
              const ExcludeSemantics(child: Icon(Icons.check, color: Color(0xFF9FD3AE))),
              Expanded(child: Text(TextosSincronizacion.listo(resultado))),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final estadoAsync = ref.watch(estadoSincronizacionProvider);
    final fase = ref.watch(actualizacionProvider);
    final ahorro = ref.watch(modoAhorroProvider);
    final conexion = ref.watch(conexionProvider).value;
    final respaldoConfigurado = ref.watch(respaldoConfiguradoProvider);
    final conectarDrive = ref.watch(conectarDriveProvider);
    final ahora = ref.watch(ahoraSincronizacionProvider)();
    ref.listen(actualizacionProvider, (anterior, actual) {
      if (actual is Actualizado && actual != anterior) _avisarListo(actual.resultado);
    });

    final estado = estadoAsync.value;
    final sinRed = conexion == TipoConexion.sinConexion;
    final conDatos = conexion == TipoConexion.datosMoviles;
    final invalidas = estado?.invalidas ?? 0;

    final avisos = <Widget>[
      if (sinRed)
        const AvisoSincronizacion(
          tono: TonoAvisoSincronizacion.sinConexion,
          texto: TextosSincronizacion.sinConexion,
          textoKey: Key('sincronizacion_aviso_sin_conexion'),
        )
      else if (fase is NoSePudoActualizar)
        AvisoSincronizacion(
          tono: TonoAvisoSincronizacion.error,
          texto: fase.motivo == MotivoFallaActualizacion.sesion
              ? TextosSincronizacion.sesionSinRenovar
              : TextosSincronizacion.errorAlActualizar,
          textoKey: const Key('sincronizacion_aviso_error'),
        )
      else if (estado?.sesionSinRenovar ?? false)
        const AvisoSincronizacion(
          tono: TonoAvisoSincronizacion.error,
          texto: TextosSincronizacion.sesionSinRenovar,
          textoKey: Key('sincronizacion_aviso_sesion'),
        ),
      if (ahorro && conDatos)
        const AvisoSincronizacion(
          tono: TonoAvisoSincronizacion.info,
          texto: TextosSincronizacion.modoAhorroConDatos,
          textoKey: Key('sincronizacion_aviso_ahorro'),
        ),
    ];

    final Widget cuerpo;
    if (estadoAsync.hasError && estado == null) {
      cuerpo = AvisoSincronizacion(
        tono: TonoAvisoSincronizacion.error,
        texto: TextosSincronizacion.errorAlLeer,
        textoKey: const Key('sincronizacion_error_lectura'),
        textoAccion: TextosSincronizacion.reintentarLectura,
        accionKey: const Key('sincronizacion_reintentar_lectura'),
        alAccionar: () => ref.invalidate(estadoSincronizacionProvider),
      );
    } else if (estado == null) {
      cuerpo = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            key: const Key('sincronizacion_cargando'),
            color: colores.gris,
            semanticsLabel: 'Cargando',
          ),
        ),
      );
    } else {
      cuerpo = _Estado(
        estado: estado,
        fase: fase,
        ahora: ahora,
        ahorro: ahorro,
        conDatos: conDatos,
        respaldoConfigurado: respaldoConfigurado,
        alConectarDrive: conectarDrive,
        alVerDetalle: (operacion) => unawaited(_verDetalle(operacion)),
      );
    }

    final botonDelPie = _BotonDelPie.para(
      fase: fase,
      invalidas: invalidas,
      sinRed: sinRed,
      alActualizar: () => unawaited(_actualizar()),
      alReintentarTodas: () => unawaited(_actualizar(todasLasFallidas: true)),
    );

    return Scaffold(
      key: const Key('sincronizacion_pagina'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('sincronizacion_atras'),
                  tooltip: 'Volver',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      TextosSincronizacion.eyebrow,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          TextosSincronizacion.titulo,
                          maxLines: 1,
                          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              ...avisos,
              cuerpo,
              InterruptorModoAhorro(
                titulo: TextosSincronizacion.modoAhorro,
                detalle: TextosSincronizacion.modoAhorroDetalle,
                activo: ahorro,
                alCambiar: _guardandoAhorro
                    ? null
                    : (activo) => unawaited(_cambiarModoAhorro(activo: activo)),
              ),
              if (_ahorroNoGuardo)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      TextosSincronizacion.modoAhorroNoGuardo,
                      key: const Key('sincronizacion_ahorro_no_guardo'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 18), child: botonDelPie),
      ),
    );
  }
}

/// El botón del pie según dónde esté la pantalla.
abstract final class _BotonDelPie {
  static Widget para({
    required FaseActualizacion fase,
    required int invalidas,
    required bool sinRed,
    required VoidCallback alActualizar,
    required VoidCallback alReintentarTodas,
  }) {
    if (fase is Actualizando) {
      return const BotonActualizar(
        texto: TextosSincronizacion.actualizando,
        alTocar: null,
        trabajando: true,
      );
    }
    if (fase is NoSePudoActualizar) {
      return BotonActualizar(
        texto: TextosSincronizacion.reintentar,
        alTocar: sinRed ? null : alActualizar,
      );
    }
    if (invalidas > 0) {
      return BotonActualizar(
        texto: TextosSincronizacion.reintentarFallidas(invalidas),
        alTocar: sinRed ? null : alReintentarTodas,
      );
    }
    return BotonActualizar(
      texto: TextosSincronizacion.actualizarAhora,
      alTocar: sinRed ? null : alActualizar,
    );
  }
}

/// La tarjeta grande, las cifras, la lista de lo que no se pudo enviar y, si falta, el aviso de que
/// no hay respaldo.
class _Estado extends ConsumerWidget {
  const _Estado({
    required this.estado,
    required this.fase,
    required this.ahora,
    required this.ahorro,
    required this.conDatos,
    required this.respaldoConfigurado,
    required this.alConectarDrive,
    required this.alVerDetalle,
  });

  final EstadoSincronizacion estado;
  final FaseActualizacion fase;
  final DateTime ahora;
  final bool ahorro;
  final bool conDatos;
  final bool respaldoConfigurado;
  final VoidCallback? alConectarDrive;
  final ValueChanged<OperacionFallida> alVerDetalle;

  Widget _tarjeta() {
    if (fase is Actualizando) {
      final total = (fase as Actualizando).pendientesAlEmpezar;
      final restantes = estado.pendientes;
      final grande = total < restantes ? restantes : total;
      final hechas = grande - restantes;
      return TarjetaSincronizacion(
        glifo: GlifoTarjeta.actualizando,
        titulo: TextosSincronizacion.actualizando,
        detalle: restantes > 0 && grande > 0
            ? TextosSincronizacion.enviando(hechas + 1, grande)
            : TextosSincronizacion.trayendoCambios,
        tituloKey: const Key('sincronizacion_titulo'),
        detalleKey: const Key('sincronizacion_detalle'),
      );
    }
    if (estado.invalidas > 0) {
      return TarjetaSincronizacion(
        glifo: GlifoTarjeta.error,
        titulo: TextosSincronizacion.conError(estado.invalidas),
        detalle: estado.pendientes > 0
            ? TextosSincronizacion.conErrorYPendientes(
                estado.pendientes,
                conflictos: estado.conflictos,
              )
            : TextosSincronizacion.conErrorDetalle,
        tituloKey: const Key('sincronizacion_titulo'),
        detalleKey: const Key('sincronizacion_detalle'),
      );
    }
    if (estado.pendientes > 0) {
      return TarjetaSincronizacion(
        glifo: GlifoTarjeta.pendientes,
        cantidad: estado.pendientes,
        titulo: TextosSincronizacion.pendientes(estado.pendientes),
        detalle: TextosSincronizacion.pendientesDetalleDe(estado.pendientes, estado.conflictos),
        tituloKey: const Key('sincronizacion_titulo'),
        detalleKey: const Key('sincronizacion_detalle'),
      );
    }
    return TarjetaSincronizacion(
      glifo: GlifoTarjeta.alDia,
      titulo: TextosSincronizacion.alDia,
      detalle: estado.actualizacionEnEspera
          ? TextosSincronizacion.alDiaConActualizacionEnEspera
          : estado.ultimaActualizacion == null
          ? TextosSincronizacion.alDiaSinActualizacion
          : TextosSincronizacion.alDiaDetalle,
      tituloKey: const Key('sincronizacion_titulo'),
      detalleKey: const Key('sincronizacion_detalle'),
    );
  }

  List<FilaDeCifras> _filas() {
    final envio = estado.ultimoEnvio;
    final actualizacion = estado.ultimaActualizacion;
    final respaldo = estado.ultimoRespaldo;
    final actualizacionBase = actualizacion == null
        ? TextosSincronizacion.todaviaNoHubo
        : FormatoSincronizacion.hace(actualizacion, ahora);
    final String valorRespaldo;
    if (respaldo != null) {
      final base =
          '${FormatoSincronizacion.reloj(respaldo, ahora)} · '
          '${TextosSincronizacion.destinoRespaldo}';
      valorRespaldo = ahorro && conDatos ? '$base · ${TextosSincronizacion.esperaWifi}' : base;
    } else {
      valorRespaldo = respaldoConfigurado
          ? TextosSincronizacion.todaviaNoHubo
          : TextosSincronizacion.respaldoNunca;
    }
    return [
      FilaDeCifras(
        rotulo: TextosSincronizacion.filaUltimoEnvio,
        valor: envio == null
            ? TextosSincronizacion.todaviaNoHubo
            : FormatoSincronizacion.hace(envio, ahora),
        clave: const Key('sincronizacion_ultimo_envio'),
      ),
      FilaDeCifras(
        rotulo: TextosSincronizacion.filaPendientes,
        valor: '${estado.pendientes}',
        clave: const Key('sincronizacion_pendientes'),
        numero: true,
        destacada: estado.pendientes > 0,
      ),
      FilaDeCifras(
        rotulo: TextosSincronizacion.filaUltimaActualizacion,
        valor: ahorro && estado.actualizacionEnEspera
            ? '$actualizacionBase · ${TextosSincronizacion.esperaWifi}'
            : actualizacionBase,
        clave: const Key('sincronizacion_ultima_actualizacion'),
      ),
      FilaDeCifras(
        rotulo: TextosSincronizacion.filaUltimoRespaldo,
        valor: valorRespaldo,
        clave: const Key('sincronizacion_ultimo_respaldo'),
        alerta: respaldo == null && !respaldoConfigurado,
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final fallidas = estado.invalidas > 0 ? ref.watch(operacionesFallidasProvider) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Semantics(liveRegion: true, container: true, child: _tarjeta()),
        FilasDeCifras(filas: _filas()),
        if (fallidas != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Semantics(
              header: true,
              child: Text(
                TextosSincronizacion.rechazadas,
                style: theme.textTheme.labelMedium?.copyWith(color: colores.gris),
              ),
            ),
          ),
          switch (fallidas) {
            AsyncData(:final value) => Column(
              spacing: 12,
              children: [
                for (final operacion in value)
                  TarjetaSincronizacion(
                    glifo: GlifoTarjeta.error,
                    titulo: TextosSincronizacion.tituloOperacion(
                      operacion,
                      FormatoSincronizacion.dia(operacion.fecha),
                    ),
                    detalle: operacion.error.isEmpty
                        ? TextosSincronizacion.detalleSinMotivo
                        : operacion.error,
                    alTocar: () => alVerDetalle(operacion),
                  ),
              ],
            ),
            AsyncError() => AvisoSincronizacion(
              tono: TonoAvisoSincronizacion.error,
              texto: TextosSincronizacion.errorAlLeerFallidas,
              textoKey: const Key('sincronizacion_error_fallidas'),
              textoAccion: TextosSincronizacion.reintentarLectura,
              accionKey: const Key('sincronizacion_reintentar_fallidas'),
              alAccionar: () => ref.invalidate(operacionesFallidasProvider),
            ),
            _ => Center(
              child: CircularProgressIndicator(
                key: const Key('sincronizacion_cargando_fallidas'),
                color: colores.gris,
                semanticsLabel: 'Cargando',
              ),
            ),
          },
        ],
        if (estado.ultimoRespaldo == null && !respaldoConfigurado)
          AvisoSincronizacion(
            tono: TonoAvisoSincronizacion.advertencia,
            texto: TextosSincronizacion.sinRespaldo,
            textoKey: const Key('sincronizacion_aviso_sin_respaldo'),
            textoAccion: alConectarDrive == null ? null : TextosSincronizacion.conectarDrive,
            accionKey: const Key('sincronizacion_conectar_drive'),
            alAccionar: alConectarDrive,
          ),
      ],
    );
  }
}
