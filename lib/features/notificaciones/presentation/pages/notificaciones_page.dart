import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/notificaciones/permiso_alarmas_exactas.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_notificaciones.dart';
import '../../domain/repositories/avisos_del_servidor_repository.dart';
import '../providers/alarmas_exactas_providers.dart';
import '../providers/avisos_del_servidor_providers.dart';
import '../providers/notificaciones_providers.dart';
import '../providers/preferencias_recordatorios_providers.dart';
import '../widgets/aviso_notificaciones.dart';
import '../widgets/avisos_del_servidor_widgets.dart';
import '../widgets/preferencias_recordatorios_widgets.dart';

/// Configuración › Notificaciones (vista 24): el estado del permiso del teléfono (grupo A) y las
/// preferencias de los recordatorios de agenda (grupo B, HU-NOT-004: «Recordatorios de agenda» y
/// «Anticipación»). El centro de avisos llega con HU-NOT-005, en esta misma pantalla.
///
/// - Activadas: no hay nada que decir del permiso; se ven las preferencias (24B·01).
/// - Sin pedir (dijo «Ahora no», o el teléfono no deja preguntar de nuevo sin saberlo): «Activar»
///   muestra el diálogo del sistema (24A·02).
/// - Bloqueadas (24A·06): desde la app ya no se pueden activar; «Abrir ajustes del teléfono» lleva a
///   donde sí se puede. Al volver a la app, el estado se vuelve a leer solo.
/// - Alarmas exactas apagadas («Aviso exacto», #510): un aviso dice que los recordatorios pueden llegar
///   tarde y «Abrir ajustes» lleva a «Alarmas y recordatorios». Al volver, el aviso se va solo y los
///   recordatorios ya programados se reprograman exactos (`alarmasExactasProvider`). Se ve aunque el
///   permiso de notificaciones esté apagado (son dos permisos distintos), pero no con «Recordatorios de
///   agenda» apagados.
/// - Con el permiso apagado las preferencias se ven y se pueden cambiar: valen cuando se activen
///   (24B·04).
/// - Apagar «Recordatorios de agenda» deja la anticipación sin tocar (24B·02); cambiar la anticipación
///   avisa cuántos recordatorios se reprogramaron (24B·03); si no se puede guardar, el control vuelve
///   a como estaba y lo dice (24B·06).
/// - La sección AVISOS (#516) tiene un interruptor por aviso del servidor: Pedidos, Tickets, Cuotas y
///   Asignaciones (sin «Promociones», decisión del 04/11). Cuotas y «Aviso de las visitas de mañana»
///   suman la hora que elige la colportora (09:00 y 20:00 por defecto). Se guardan en el servidor
///   (`avisosDelServidorProvider`): cargando, error al leer con «Reintentar», y, si no se puede guardar
///   (también sin conexión), el control vuelve a como estaba y lo dice con «Reintentar» (24B·05 y 24B·06).
///   Los recordatorios de agenda siguen funcionando sin conexión.
class NotificacionesPage extends ConsumerStatefulWidget {
  const NotificacionesPage({super.key});

  static Route<void> ruta() => MaterialPageRoute<void>(builder: (_) => const NotificacionesPage());

  @override
  ConsumerState<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends ConsumerState<NotificacionesPage> {
  /// Mientras el diálogo del sistema está abierto: «Activar» no pide dos veces.
  bool _activando = false;

  /// El último «Activar» falló (la plataforma no mostró el diálogo).
  bool _falloAlActivar = false;

  /// Mientras se abren los ajustes del teléfono, y si no se pudieron abrir.
  bool _abriendoAjustes = false;
  bool _ajustesNoAbren = false;

  Future<void> _activar() async {
    if (_activando) return;
    setState(() {
      _activando = true;
      _falloAlActivar = false;
    });
    final mensajero = ScaffoldMessenger.of(context);
    final sinConexion = ref.read(conexionProvider).value == TipoConexion.sinConexion;
    final resultado = await ref.read(notificacionesProvider.notifier).activar();
    if (resultado == ResultadoActivacion.activadas) {
      avisarNotificacionesActivadas(mensajero, sinConexion: sinConexion);
    }
    if (!mounted) return;
    setState(() {
      _activando = false;
      _falloAlActivar = resultado == ResultadoActivacion.fallo;
    });
  }

  Future<void> _abrirAjustes() async {
    if (_abriendoAjustes) return;
    setState(() {
      _abriendoAjustes = true;
      _ajustesNoAbren = false;
    });
    final abiertos = await ref.read(notificacionesProvider.notifier).abrirAjustes();
    if (!mounted) return;
    setState(() {
      _abriendoAjustes = false;
      _ajustesNoAbren = !abiertos;
    });
  }

  /// Mientras se abre «Alarmas y recordatorios», y si no se pudo abrir.
  bool _abriendoAlarmas = false;
  bool _alarmasNoAbren = false;

  Future<void> _abrirAjustesAlarmas() async {
    if (_abriendoAlarmas) return;
    setState(() {
      _abriendoAlarmas = true;
      _alarmasNoAbren = false;
    });
    final abiertos = await ref.read(alarmasExactasProvider.notifier).abrirAjustes();
    if (!mounted) return;
    setState(() {
      _abriendoAlarmas = false;
      _alarmasNoAbren = !abiertos;
    });
  }

  Future<void> _cambiarActivados({required bool activados}) async {
    final mensajero = ScaffoldMessenger.of(context);
    // El teléfono guarda el interruptor y el servidor recibe su copia desde el notificador de los
    // avisos, que sigue vivo aunque la persona salga de la pantalla mientras tanto.
    await ref
        .read(avisosDelServidorProvider.notifier)
        .cambiarRecordatoriosDeAgenda(activados: activados);
    // Con los recordatorios apagados no se avisa nada: el aviso de la anticipación («te avisamos 35
    // min antes») que sigue a la vista contradiría al aviso fijo de 24B·02 (#155).
    // Si la persona salió de la pantalla mientras se guardaba no se puede leer el estado (`ref`): vale
    // lo que pidió. Si sigue acá, vale lo guardado (otro cambio pudo volver a prender mientras tanto).
    final apagados = mounted
        ? ref.read(preferenciasRecordatoriosProvider).value?.preferencias.activados == false
        : !activados;
    if (apagados) mensajero.clearSnackBars();
  }

  /// Guarda la anticipación y, si se guardó, avisa a cuántos recordatorios les tocó la hora nueva.
  Future<void> _cambiarAnticipacion(int minutos) =>
      _avisandoLaReprogramacion((n) => n.cambiarAnticipacion(minutos), siempre: true);

  /// «Reintentar» del error al guardar (24B·06): avisa solo si lo que se reintenta es la anticipación.
  Future<void> _reintentarGuardado() =>
      _avisandoLaReprogramacion((n) => n.reintentar(), siempre: false);

  Future<void> _avisandoLaReprogramacion(
    Future<int?> Function(PreferenciasRecordatoriosNotifier) accion, {
    required bool siempre,
  }) async {
    final mensajero = ScaffoldMessenger.of(context);
    final notificador = ref.read(preferenciasRecordatoriosProvider.notifier);
    final antes = ref
        .read(preferenciasRecordatoriosProvider)
        .value
        ?.preferencias
        .anticipacionMinutos;
    final reprogramados = await accion(notificador);
    if (reprogramados == null || !mounted) return;
    final preferencias = ref.read(preferenciasRecordatoriosProvider).value?.preferencias;
    final minutos = preferencias?.anticipacionMinutos;
    if (minutos == null || (!siempre && minutos == antes)) return;
    // Si mientras se guardaba se apagaron los recordatorios (dos cambios que comparten el
    // guardado), no se reprogramó ninguno: el aviso fijo de 24B·02 ya lo dice y este lo contradiría.
    if (!preferencias!.activados) return;
    mensajero
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const Key('pref_anticipacion_aviso'),
          content: Text(
            TextosNotificaciones.anticipacionCambiada(
              reprogramados: reprogramados,
              minutos: minutos,
            ),
          ),
        ),
      );
  }

  /// El permiso del teléfono (grupo A): con las notificaciones activadas no hay nada que decir.
  List<Widget> _permiso(AsyncValue<EstadoNotificaciones> estado) => switch (estado) {
    AsyncData(:final value) when value.permiso == EstadoPermisoNotificaciones.activadas => const [],
    AsyncData(:final value) => [
      _Contenido(
        permiso: value.permiso,
        activando: _activando,
        falloAlActivar: _falloAlActivar,
        abriendoAjustes: _abriendoAjustes,
        ajustesNoAbren: _ajustesNoAbren,
        onActivar: () => unawaited(_activar()),
        onAbrirAjustes: () => unawaited(_abrirAjustes()),
      ),
    ],
    AsyncError() => [
      AvisoNotificaciones(
        tono: TonoAviso.error,
        texto: TextosNotificaciones.errorAlLeer,
        textoKey: const Key('notificaciones_error'),
        textoAccion: TextosNotificaciones.reintentar,
        accionKey: const Key('notificaciones_reintentar'),
        onAccion: () => ref.invalidate(notificacionesProvider),
      ),
    ],
    _ => const [],
  };

  /// «Aviso exacto» (#510): sin «Alarmas y recordatorios» los recordatorios pueden llegar tarde. Con el
  /// permiso prendido, sin concepto (iOS) o sin saber, no hay nada que decir.
  List<Widget> _alarmas(
    AsyncValue<EstadoAlarmasExactas> alarmas,
    AsyncValue<EstadoPreferenciasRecordatorios> preferencias,
  ) {
    if (alarmas.value != EstadoAlarmasExactas.apagadas) return const [];
    // Con «Recordatorios de agenda» apagados no hay recordatorios que lleguen tarde (decidido el
    // 03/11, mapa §2): el aviso vuelve apenas se prenden.
    if (preferencias.value?.preferencias.activados == false) return const [];
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return [
      AvisoNotificaciones(
        tono: TonoAviso.advertencia,
        texto: TextosNotificaciones.alarmasApagadas,
        textoKey: const Key('alarmas_exactas_aviso'),
        textoAccion: TextosNotificaciones.alarmasAbrirAjustes,
        accionKey: const Key('alarmas_exactas_abrir_ajustes'),
        onAccion: _abriendoAlarmas ? null : () => unawaited(_abrirAjustesAlarmas()),
      ),
      if (_alarmasNoAbren)
        Semantics(
          liveRegion: true,
          child: Text(
            TextosNotificaciones.alarmasAjustesNoAbren,
            key: const Key('alarmas_exactas_ajustes_no_abren'),
            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
          ),
        ),
    ];
  }

  /// El cambio que no se pudo guardar tocaba solo el interruptor (y no la anticipación).
  static bool _soloElInterruptor(EstadoPreferenciasRecordatorios estado) =>
      estado.falla?.anticipacionMinutos == estado.preferencias.anticipacionMinutos;

  /// Las preferencias de los recordatorios (grupo B). Con el permiso del teléfono apagado se ven a
  /// todo contraste, con el aviso de 24B·04 arriba y sin la opacidad .45 del canvas (decidido el
  /// 27/10, mapa §2: un control tocable a 45 % no llega a AA).
  List<Widget> _preferencias(
    AsyncValue<EstadoPreferenciasRecordatorios> preferencias,
    AsyncValue<EstadoAvisosDelServidor> avisos,
  ) => switch (preferencias) {
    AsyncData(:final value) => [
      if (!value.preferencias.activados)
        const AvisoNotificaciones(
          tono: TonoAviso.info,
          texto: TextosNotificaciones.recordatoriosApagados,
          textoKey: Key('pref_apagados_aviso'),
        ),
      if (value.falla != null)
        AvisoNotificaciones(
          tono: TonoAviso.error,
          // Solo el interruptor: el texto del canvas; si no, el aviso dice que volvió todo.
          texto: _soloElInterruptor(value)
              ? TextosNotificaciones.errorAlGuardar
              : TextosNotificaciones.errorAlGuardarVarios,
          textoKey: const Key('pref_error_guardar'),
          textoAccion: TextosNotificaciones.reintentar,
          accionKey: const Key('pref_error_reintentar'),
          onAccion: () => unawaited(_reintentarGuardado()),
        ),
      Semantics(
        header: true,
        child: Text(
          TextosNotificaciones.seccionRecordatorios,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      InterruptorRecordatorios(
        activado: value.preferencias.activados,
        onCambio: (v) => unawaited(_cambiarActivados(activados: v)),
      ),
      TarjetaAnticipacion(
        minutos: value.preferencias.anticipacionMinutos,
        habilitada: value.preferencias.activados,
        onGuardar: (m) => unawaited(_cambiarAnticipacion(m)),
      ),
      if (avisos case AsyncData(value: final a))
        TarjetaHoraAgenda(
          hora: a.avisos.horaAgenda,
          habilitada: value.preferencias.activados,
          onElegirHora: (h) =>
              unawaited(ref.read(avisosDelServidorProvider.notifier).cambiarHoraAgenda(h)),
        ),
    ],
    AsyncError() => [
      AvisoNotificaciones(
        tono: TonoAviso.error,
        texto: TextosNotificaciones.errorAlLeerPreferencias,
        textoKey: const Key('pref_error_leer'),
        textoAccion: TextosNotificaciones.reintentar,
        accionKey: const Key('pref_reintentar_leer'),
        onAccion: () => ref.invalidate(preferenciasRecordatoriosProvider),
      ),
    ],
    _ => const [],
  };

  /// El texto del error al guardar un aviso del servidor (24B·06): sin conexión lo dice y guía; con
  /// conexión, lo que volvió a como estaba (un interruptor, una hora, o varios cambios).
  static String _textoErrorAvisos(EstadoAvisosDelServidor estado) {
    if (estado.fallo == FalloDeAvisos.sinConexion) {
      return TextosNotificaciones.errorAlGuardarSinConexion;
    }
    final pedido = estado.falla;
    if (pedido == null) return TextosNotificaciones.errorAlGuardar;
    final actual = estado.avisos;
    final interruptores = [
      pedido.pedidos != actual.pedidos,
      pedido.tickets != actual.tickets,
      pedido.cuotas != actual.cuotas,
      pedido.asignaciones != actual.asignaciones,
    ].where((cambio) => cambio).length;
    final horas = [
      pedido.horaCuota != actual.horaCuota,
      pedido.horaAgenda != actual.horaAgenda,
    ].where((cambio) => cambio).length;
    if (interruptores + horas > 1) return TextosNotificaciones.errorAlGuardarVarios;
    if (horas == 0) return TextosNotificaciones.errorAlGuardar;
    return TextosNotificaciones.errorAlGuardarHora(
      pedido.horaCuota != actual.horaCuota ? HoraDeAviso.cuotas : HoraDeAviso.visitasDeManana,
    );
  }

  /// La sección AVISOS (grupo B, #516): los avisos que manda el servidor. Cargando (24B·05), error al
  /// leer con «Reintentar», y con datos, un interruptor por aviso (Cuotas con su hora).
  List<Widget> _avisos(AsyncValue<EstadoAvisosDelServidor> avisos) {
    final notificador = ref.read(avisosDelServidorProvider.notifier);
    final titulo = Semantics(
      header: true,
      child: Text(
        TextosNotificaciones.seccionAvisos,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
    return switch (avisos) {
      AsyncData(:final value) => [
        titulo,
        if (value.falla != null)
          AvisoNotificaciones(
            tono: TonoAviso.error,
            texto: _textoErrorAvisos(value),
            textoKey: const Key('avisos_error_guardar'),
            textoAccion: TextosNotificaciones.reintentar,
            accionKey: const Key('avisos_error_reintentar'),
            onAccion: () => unawaited(notificador.reintentar()),
          ),
        TarjetaPreferencia(
          hijo: InterruptorPreferencia(
            interruptorKey: const Key('aviso_pedidos_interruptor'),
            titulo: TextosNotificaciones.avisoPedidos,
            activado: value.avisos.pedidos,
            onCambio: (v) => unawaited(notificador.cambiarPedidos(activado: v)),
          ),
        ),
        TarjetaPreferencia(
          hijo: InterruptorPreferencia(
            interruptorKey: const Key('aviso_tickets_interruptor'),
            titulo: TextosNotificaciones.avisoTickets,
            activado: value.avisos.tickets,
            onCambio: (v) => unawaited(notificador.cambiarTickets(activado: v)),
          ),
        ),
        TarjetaAvisoCuotas(
          activado: value.avisos.cuotas,
          hora: value.avisos.horaCuota,
          onCambio: (v) => unawaited(notificador.cambiarCuotas(activado: v)),
          onElegirHora: (h) => unawaited(notificador.cambiarHoraCuota(h)),
        ),
        TarjetaPreferencia(
          hijo: InterruptorPreferencia(
            interruptorKey: const Key('aviso_asignaciones_interruptor'),
            titulo: TextosNotificaciones.avisoAsignaciones,
            detalle: TextosNotificaciones.avisoAsignacionesDetalle,
            activado: value.avisos.asignaciones,
            onCambio: (v) => unawaited(notificador.cambiarAsignaciones(activado: v)),
          ),
        ),
      ],
      AsyncError(:final error) => [
        titulo,
        AvisoNotificaciones(
          tono: TonoAviso.error,
          texto: error is AvisosSinConexionException
              ? TextosNotificaciones.errorAlLeerAvisosSinConexion
              : TextosNotificaciones.errorAlLeerAvisos,
          textoKey: const Key('avisos_error_leer'),
          textoAccion: TextosNotificaciones.reintentar,
          accionKey: const Key('avisos_reintentar_leer'),
          onAccion: () => ref.invalidate(avisosDelServidorProvider),
        ),
      ],
      _ => [titulo, const CargandoAvisos()],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estado = ref.watch(notificacionesProvider);
    final preferencias = ref.watch(preferenciasRecordatoriosProvider);
    final alarmas = ref.watch(alarmasExactasProvider);
    final avisos = ref.watch(avisosDelServidorProvider);

    return Scaffold(
      key: const Key('notificaciones_pagina'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('notificaciones_atras'),
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
                      'CONFIGURACIÓN',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Notificaciones',
                          maxLines: 1,
                          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    if (estado is AsyncLoading || preferencias is AsyncLoading)
                      const CargandoPreferencias()
                    else ...[
                      ..._permiso(estado),
                      ..._alarmas(alarmas, preferencias),
                      ..._preferencias(preferencias, avisos),
                      ..._avisos(avisos),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.permiso,
    required this.activando,
    required this.falloAlActivar,
    required this.abriendoAjustes,
    required this.ajustesNoAbren,
    required this.onActivar,
    required this.onAbrirAjustes,
  });

  final EstadoPermisoNotificaciones permiso;
  final bool activando;
  final bool falloAlActivar;
  final bool abriendoAjustes;
  final bool ajustesNoAbren;
  final VoidCallback onActivar;
  final VoidCallback onAbrirAjustes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        switch (permiso) {
          EstadoPermisoNotificaciones.activadas => const SizedBox.shrink(),
          EstadoPermisoNotificaciones.sinPedir => AvisoNotificaciones(
            tono: TonoAviso.advertencia,
            texto: TextosNotificaciones.apagadas,
            textoKey: const Key('notificaciones_apagadas'),
            textoAccion: TextosNotificaciones.activarCorto,
            accionKey: const Key('notificaciones_activar'),
            onAccion: activando ? null : onActivar,
          ),
          EstadoPermisoNotificaciones.bloqueadas => AvisoNotificaciones(
            tono: TonoAviso.advertencia,
            texto: TextosNotificaciones.bloqueadas,
            textoKey: const Key('notificaciones_bloqueadas'),
            textoAccion: TextosNotificaciones.abrirAjustes,
            accionKey: const Key('notificaciones_abrir_ajustes'),
            onAccion: abriendoAjustes ? null : onAbrirAjustes,
          ),
        },
        if (falloAlActivar)
          Semantics(
            liveRegion: true,
            child: Text(
              TextosNotificaciones.activarFallo,
              key: const Key('notificaciones_fallo'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (ajustesNoAbren)
          Semantics(
            liveRegion: true,
            child: Text(
              TextosNotificaciones.ajustesNoAbren,
              key: const Key('notificaciones_ajustes_no_abren'),
              style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
            ),
          ),
      ],
    );
  }
}
