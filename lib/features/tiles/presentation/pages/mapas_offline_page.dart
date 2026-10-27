import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/estado_descarga.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../../domain/services/puertos_descarga.dart';
import '../providers/mapas_offline_providers.dart';
import '../textos_mapas_offline.dart';
import '../widgets/hoja_achicar_cobertura.dart';
import '../widgets/hoja_borrar_mapa.dart';

/// «Mapas offline» (vista 35, pantallas 01 y 02, HU-SYNC-010): elegir cuánto mapa bajar (zona,
/// ciudad, departamento o Uruguay), ver cómo avanza la descarga, pausarla, borrar un mapa, bajar la
/// versión nueva y achicar la cobertura. Se entra desde la fila «Mapas offline» de Configuración.
///
/// Con mapas descargados o bajando se ve la lista (pantalla 02); sin ninguno, o con «Cambiar
/// cobertura», la elección (pantalla 01).
class MapasOfflinePage extends ConsumerStatefulWidget {
  const MapasOfflinePage({super.key});

  /// La ruta de la pantalla (todavía no hay router: go_router llega con el mapa).
  static Route<void> ruta() => MaterialPageRoute<void>(builder: (_) => const MapasOfflinePage());

  @override
  ConsumerState<MapasOfflinePage> createState() => _MapasOfflinePageState();
}

class _MapasOfflinePageState extends ConsumerState<MapasOfflinePage> {
  /// La hoja de «Achicar» está abierta: corta el segundo toque mientras se decide.
  bool _preguntando = false;

  Future<void> _descargar(EstadoMapasOffline estado) async {
    if (_preguntando) return;
    final notificador = ref.read(mapasOfflineProvider.notifier);
    final plan = notificador.planDeAchicar();
    if (plan == null) {
      await notificador.descargar();
      return;
    }
    _preguntando = true;
    bool? confirmo;
    try {
      confirmo = await mostrarHojaAchicarCobertura(
        context,
        nivel: plan.elegido.nivel,
        mayor: [
          for (final d in plan.sobran)
            TextosMapasOffline.nombreDe(d.paquete, nombreZona: estado.lugar?.zonaNombre),
        ].join(' y '),
        elegido: TextosMapasOffline.nombreDe(
          plan.elegido.paquete ?? plan.sobran.first.paquete,
          nombreZona: estado.lugar?.zonaNombre,
        ),
        liberanMegabytes: megabytesDe(plan.liberanBytes),
      );
    } finally {
      _preguntando = false;
    }
    if (confirmo ?? false) await notificador.descargar(achicar: plan);
  }

  /// «Borrar mapa»: pregunta antes (se pierde el mapa y para volver a tenerlo hace falta Wi-Fi). El
  /// segundo toque mientras la hoja está abierta no hace nada.
  Future<void> _borrar(TarjetaMapa tarjeta, EstadoMapasOffline estado) async {
    if (_preguntando) return;
    _preguntando = true;
    bool? confirmo;
    try {
      confirmo = await mostrarHojaBorrarMapa(
        context,
        nombre: TextosMapasOffline.nombreDe(tarjeta.paquete, nombreZona: estado.lugar?.zonaNombre),
      );
    } finally {
      _preguntando = false;
    }
    if (confirmo ?? false) await ref.read(mapasOfflineProvider.notifier).borrar(tarjeta);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(mapasOfflineProvider);
    ref.listen(mapasOfflineProvider.select((e) => e.aviso), (_, aviso) {
      if (aviso == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(key: const Key('mapas_offline_aviso'), content: Text(aviso)));
      ref.read(mapasOfflineProvider.notifier).consumirAviso();
    });
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final lista = !estado.cargando && estado.verDescargas;
    return Scaffold(
      key: const Key('mapas_offline_pagina'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: IconButton(
                  key: const Key('mapas_offline_atras'),
                  tooltip: TextosMapasOffline.volver,
                  onPressed: () {
                    final notificador = ref.read(mapasOfflineProvider.notifier);
                    // Desde «Cambiar cobertura» el paso atrás vuelve a la lista, no sale (de a un
                    // paso, sin perder lo elegido).
                    if (estado.cambiando && estado.tarjetas.isNotEmpty) {
                      notificador.verDescargas();
                    } else {
                      unawaited(Navigator.of(context).maybePop());
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lista ? TextosMapasOffline.etiqueta02 : TextosMapasOffline.etiqueta01,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    header: true,
                    child: Text(TextosMapasOffline.titulo, style: theme.textTheme.headlineMedium),
                  ),
                  if (!lista) ...[
                    const SizedBox(height: 4),
                    Text(
                      TextosMapasOffline.subtitulo,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: estado.cargando
                  ? const _Revisando()
                  : lista
                  ? _ListaDeMapas(estado: estado, alBorrar: (t) => _borrar(t, estado))
                  : _EleccionDeCobertura(estado: estado, alDescargar: () => _descargar(estado)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Revisando extends StatelessWidget {
  const _Revisando();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('mapas_offline_revisando'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const CircularProgressIndicator(semanticsLabel: TextosMapasOffline.revisando),
            Text(TextosMapasOffline.revisando, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Pantalla 01: elegir cuánto mapa.
// ---------------------------------------------------------------------------------------------

class _EleccionDeCobertura extends ConsumerWidget {
  const _EleccionDeCobertura({required this.estado, required this.alDescargar});

  final EstadoMapasOffline estado;
  final VoidCallback alDescargar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final notificador = ref.read(mapasOfflineProvider.notifier);
    final vigente = estado.nivelVigente;
    final opcion = vigente == null ? null : estado.opcion(vigente);
    final paquete = opcion?.paquete;
    final libres = estado.bytesLibres;
    final nombreZona = estado.lugar?.zonaNombre;

    final yaBajado = opcion != null && opcion.descargado != null && !opcion.hayActualizacion;
    final plan = notificador.planDeAchicar();
    final ocupa = paquete?.tamanoBytes ?? 0;
    final sinLugar = paquete != null && libres != null && !yaBajado && ocupa > libres;
    final hayMasChico = [
      for (final n in NivelCobertura.values)
        if (estado.seOfrece(n) && n.index < (vigente?.index ?? 0)) n,
    ].isNotEmpty;

    final avisos = <Widget>[
      if (estado.falloLugar case final falla?)
        _Banner(
          clave: const Key('mapas_offline_sin_lugar'),
          tipo: _TipoBanner.error,
          texto: falla.mensaje,
          accion: TextosMapasOffline.reintentar,
          alAccionar: () => unawaited(notificador.cargar()),
        ),
      if (estado.sinCatalogo)
        _Banner(
          clave: const Key('mapas_offline_sin_catalogo'),
          tipo: _TipoBanner.info,
          texto: TextosMapasOffline.sinCatalogo,
          accion: TextosMapasOffline.reintentar,
          alAccionar: () => unawaited(notificador.cargar()),
        )
      else if (estado.conexion == TipoConexion.datosMoviles)
        const _Banner(
          clave: Key('mapas_offline_datos_moviles'),
          tipo: _TipoBanner.info,
          texto: TextosMapasOffline.datosMoviles,
        )
      else if (estado.conexion == TipoConexion.sinConexion)
        const _Banner(
          clave: Key('mapas_offline_sin_conexion'),
          tipo: _TipoBanner.info,
          texto: TextosMapasOffline.sinConexion,
        ),
      if (sinLugar)
        _Banner(
          clave: const Key('mapas_offline_sin_espacio'),
          tipo: _TipoBanner.error,
          texto: TextosMapasOffline.sinLugar(
            TextosMapasOffline.nombreDe(paquete, nombreZona: nombreZona),
            TextosMapasOffline.peso(ocupa),
            TextosMapasOffline.pesoLibre(libres),
            haySalida: hayMasChico,
          ),
        ),
      if (estado.falla case final falla? when !sinLugar) _FallaDeAccion(falla: falla),
    ];

    final etiquetaCta = plan != null && yaBajado
        ? TextosMapasOffline.achicarAccion(vigente!)
        : estado.conexion == TipoConexion.wifi
        ? TextosMapasOffline.descargar
        : TextosMapasOffline.descargarConWifi;
    final puedeDescargar =
        paquete != null &&
        !sinLugar &&
        !estado.pidiendo &&
        (!yaBajado || plan != null) &&
        !estado.cargando;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              for (final aviso in avisos) ...[aviso, const SizedBox(height: 10)],
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    TextosMapasOffline.cuantoMapa,
                    style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                  ),
                ),
              ),
              Semantics(
                container: true,
                child: Column(
                  spacing: 8,
                  children: [
                    for (final nivel in NivelCobertura.values)
                      _OpcionDeCobertura(
                        clave: Key('mapas_offline_nivel_${nivel.name}'),
                        titulo: TextosMapasOffline.nivel(nivel),
                        detalle: _detalle(nivel),
                        seleccionada: nivel == vigente,
                        habilitada: estado.seOfrece(nivel),
                        alTocar: () => notificador.elegir(nivel),
                      ),
                  ],
                ),
              ),
              if (vigente == NivelCobertura.ciudad) ...[
                const SizedBox(height: 12),
                Text(
                  TextosMapasOffline.ayudaCiudad,
                  key: const Key('mapas_offline_ayuda_ciudad'),
                  style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                ),
              ],
              if (yaBajado && plan == null) ...[
                const SizedBox(height: 12),
                Text(
                  TextosMapasOffline.yaLoTenes,
                  key: const Key('mapas_offline_ya_lo_tenes'),
                  style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                ),
              ],
              if (libres != null && !sinLugar) ...[
                const SizedBox(height: 12),
                Text(
                  TextosMapasOffline.espacioLibre(libres),
                  key: const Key('mapas_offline_espacio_libre'),
                  style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            key: const Key('mapas_offline_descargar'),
            onPressed: puedeDescargar ? alDescargar : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: estado.pidiendo
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: 'Pidiendo'),
                  )
                : Text(etiquetaCta),
          ),
        ),
      ],
    );
  }

  String _detalle(NivelCobertura nivel) {
    final opcion = estado.opcion(nivel);
    final paquete = opcion?.paquete;
    final descargado = opcion?.descargado;
    if (nivel == NivelCobertura.zona &&
        estado.lugar != null &&
        estado.lugar!.ambito.zonaId == null) {
      return TextosMapasOffline.sinZona;
    }
    if (paquete == null) {
      // Sin catálogo no se sabe qué hay: no se afirma que «llega con Pro».
      if (estado.sinCatalogo) {
        return descargado == null
            ? TextosMapasOffline.sinPaquete
            : '${TextosMapasOffline.peso(descargado.paquete.tamanoBytes)} · '
                  '${TextosMapasOffline.yaDescargado}';
      }
      return switch (nivel) {
        NivelCobertura.zona => TextosMapasOffline.zonaSinPaquete,
        NivelCobertura.ciudad => TextosMapasOffline.sinPaquete,
        NivelCobertura.departamento || NivelCobertura.uruguay => TextosMapasOffline.llegaConPro,
      };
    }
    final nombre = TextosMapasOffline.nombreDe(paquete, nombreZona: estado.lugar?.zonaNombre);
    final peso = TextosMapasOffline.peso(paquete.tamanoBytes);
    final bajado = descargado != null && !(opcion?.hayActualizacion ?? false);
    final base = nivel == NivelCobertura.uruguay ? peso : '$nombre · $peso';
    return bajado ? '$base · ${TextosMapasOffline.yaDescargado}' : base;
  }
}

class _OpcionDeCobertura extends StatelessWidget {
  const _OpcionDeCobertura({
    required this.clave,
    required this.titulo,
    required this.detalle,
    required this.seleccionada,
    required this.habilitada,
    required this.alTocar,
  });

  final Key clave;
  final String titulo;
  final String detalle;
  final bool seleccionada;
  final bool habilitada;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    return Semantics(
      key: clave,
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: seleccionada,
      enabled: habilitada,
      button: true,
      label: '$titulo. $detalle',
      excludeSemantics: true,
      onTap: habilitada ? alTocar : null,
      child: Material(
        color: seleccionada ? _fondoInfo : esquema.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: seleccionada ? esquema.primary : colores.borde,
            width: seleccionada ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: habilitada ? alTocar : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    seleccionada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: habilitada ? esquema.primary : colores.gris,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: habilitada ? esquema.onSurface : colores.gris,
                          ),
                        ),
                        Text(
                          detalle,
                          style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
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
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Pantalla 02: lo descargado y lo que se está bajando.
// ---------------------------------------------------------------------------------------------

class _ListaDeMapas extends ConsumerWidget {
  const _ListaDeMapas({required this.estado, required this.alBorrar});

  final EstadoMapasOffline estado;
  final Future<void> Function(TarjetaMapa tarjeta) alBorrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificador = ref.read(mapasOfflineProvider.notifier);
    final tarjetas = estado.tarjetas;
    final hayFallaEnTarjeta = tarjetas.any((t) => t.estado is DescargaFallida);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (estado.falla case final falla? when !hayFallaEnTarjeta) ...[
          _FallaDeAccion(falla: falla),
          const SizedBox(height: 10),
        ],
        for (final tarjeta in tarjetas) ...[
          _TarjetaDeMapa(
            tarjeta: tarjeta,
            nombreZona: estado.lugar?.zonaNombre,
            restante: estado.restante[tarjeta.paquete.id],
            ocupado: estado.pidiendo,
            alPausar: () => unawaited(notificador.pausar(tarjeta.paquete.id)),
            alSeguir: () => unawaited(notificador.seguir(tarjeta)),
            alBorrar: () => unawaited(alBorrar(tarjeta)),
            alActualizar: () => unawaited(notificador.actualizar(tarjeta)),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          key: const Key('mapas_offline_cambiar_cobertura'),
          onPressed: notificador.verCobertura,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text(TextosMapasOffline.cambiarCobertura),
        ),
      ],
    );
  }
}

class _TarjetaDeMapa extends StatelessWidget {
  const _TarjetaDeMapa({
    required this.tarjeta,
    required this.nombreZona,
    required this.restante,
    required this.ocupado,
    required this.alPausar,
    required this.alSeguir,
    required this.alBorrar,
    required this.alActualizar,
  });

  final TarjetaMapa tarjeta;
  final String? nombreZona;
  final Duration? restante;
  final bool ocupado;
  final VoidCallback alPausar;
  final VoidCallback alSeguir;
  final VoidCallback alBorrar;
  final VoidCallback alActualizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    final paquete = tarjeta.paquete;
    final id = paquete.id;
    final estado = tarjeta.estado;
    final nombre = TextosMapasOffline.nombreDe(paquete, nombreZona: nombreZona);
    final secundario = theme.textTheme.bodySmall?.copyWith(color: colores.gris);

    final (etiqueta, fondo, texto) = switch (estado) {
      DescargaPausada() => (
        TextosMapasOffline.enPausa,
        const Color(0xFFFBF1DA),
        const Color(0xFF6E5212),
      ),
      DescargaFallida() => (
        TextosMapasOffline.noSePudo,
        esquema.errorContainer,
        esquema.onErrorContainer,
      ),
      DescargaEnCurso() || DescargaVerificando() => (
        TextosMapasOffline.descargando,
        esquema.primaryContainer,
        esquema.onPrimaryContainer,
      ),
      _ => (TextosMapasOffline.descargado, const Color(0xFFDDE8D3), const Color(0xFF1F6E3A)),
    };

    final cuerpo = <Widget>[
      switch (estado) {
        DescargaEnCurso(:final recibidos, :final total) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TextosMapasOffline.avanceDe(recibidos, total), style: secundario),
            if (restante != null)
              Text(
                TextosMapasOffline.restante(restante),
                key: Key('mapas_offline_restante_$id'),
                style: secundario,
              ),
          ],
        ),
        DescargaPausada(:final recibidos, :final total) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TextosMapasOffline.avanceDe(recibidos, total), style: secundario),
            Text(
              TextosMapasOffline.motivoDePausa(estado),
              key: Key('mapas_offline_pausa_$id'),
              style: secundario?.copyWith(color: const Color(0xFF6E5212)),
            ),
          ],
        ),
        DescargaVerificando() => Text(TextosMapasOffline.verificando, style: secundario),
        DescargaFallida(:final failure) => Text(
          failure.mensaje,
          key: Key('mapas_offline_falla_$id'),
          style: secundario?.copyWith(color: esquema.error),
        ),
        _ => Text(
          TextosMapasOffline.descargadoListo(TextosMapasOffline.peso(paquete.tamanoBytes)),
          key: Key('mapas_offline_listo_$id'),
          style: secundario,
        ),
      },
    ];

    final progreso = switch (estado) {
      DescargaEnCurso(:final progreso) => progreso,
      DescargaPausada(:final recibidos, :final total) =>
        total <= 0 ? 0.0 : (recibidos / total).clamp(0, 1).toDouble(),
      _ => null,
    };

    return DecoratedBox(
      key: Key('mapas_offline_tarjeta_$id'),
      decoration: BoxDecoration(
        color: esquema.surface,
        border: Border.all(color: colores.borde),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(nombre, style: theme.textTheme.titleMedium),
                DecoratedBox(
                  decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Text(
                      etiqueta,
                      key: Key('mapas_offline_etiqueta_$id'),
                      style: theme.textTheme.labelSmall?.copyWith(color: texto),
                    ),
                  ),
                ),
              ],
            ),
            ...cuerpo,
            if (progreso != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        estado is DescargaPausada
                            ? TextosMapasOffline.descargado
                            : TextosMapasOffline.descargando,
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        '${(progreso * 100).floor()} %',
                        key: Key('mapas_offline_porcentaje_$id'),
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  LinearProgressIndicator(
                    value: progreso,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    semanticsLabel: '$nombre ${(progreso * 100).floor()} %',
                  ),
                ],
              ),
            if (estado is DescargaVerificando)
              const LinearProgressIndicator(
                minHeight: 8,
                semanticsLabel: TextosMapasOffline.verificando,
              ),
            if (estado is DescargaEnCurso)
              Text(TextosMapasOffline.puedeSeguirUsandoLaApp, style: secundario),
            if (estado == null && tarjeta.nuevo != null)
              _Banner(
                clave: Key('mapas_offline_version_nueva_$id'),
                tipo: _TipoBanner.info,
                texto: TextosMapasOffline.versionNueva(
                  nombre,
                  TextosMapasOffline.peso(tarjeta.nuevo!.tamanoBytes),
                ),
                accion: TextosMapasOffline.actualizar,
                alAccionar: ocupado ? null : alActualizar,
              ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (estado is DescargaEnCurso)
                  OutlinedButton(
                    key: Key('mapas_offline_pausar_$id'),
                    onPressed: alPausar,
                    child: const Text(TextosMapasOffline.pausar),
                  ),
                if (estado is DescargaPausada)
                  FilledButton(
                    key: Key('mapas_offline_seguir_$id'),
                    onPressed: ocupado ? null : alSeguir,
                    child: const Text(TextosMapasOffline.seguir),
                  ),
                if (estado is DescargaFallida)
                  FilledButton(
                    key: Key('mapas_offline_reintentar_$id'),
                    onPressed: ocupado ? null : alSeguir,
                    child: const Text(TextosMapasOffline.reintentar),
                  ),
                if (tarjeta.descargado != null && estado is! DescargaEnCurso)
                  TextButton(
                    key: Key('mapas_offline_borrar_$id'),
                    onPressed: ocupado ? null : alBorrar,
                    style: TextButton.styleFrom(foregroundColor: esquema.error),
                    child: const Text(TextosMapasOffline.borrarMapa),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Avisos.
// ---------------------------------------------------------------------------------------------

enum _TipoBanner { info, error }

// Fondos tenues de las etiquetas del canvas (35-07, 35-08), como los avisos de las vistas 06 y 37.
// El tema no define primaryContainer ni errorContainer (Flutter los iguala a primary y error, navy y
// rojo llenos): con texto oscuro encima no se leían (QA #132). Tinta sobre cada fondo >= 4,5:1.
const _fondoInfo = Color(0xFFE6EEF8);
const _fondoError = Color(0xFFFBE9E6);
const _tintaError = Color(0xFF8A1C12);

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tipo,
    required this.texto,
    this.clave,
    this.accion,
    this.alAccionar,
  });

  final _TipoBanner tipo;
  final String texto;
  final Key? clave;
  final String? accion;
  final VoidCallback? alAccionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final error = tipo == _TipoBanner.error;
    final fondo = error ? _fondoError : _fondoInfo;
    final color = error ? _tintaError : esquema.onSurface;
    return Semantics(
      key: clave,
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  ExcludeSemantics(
                    child: Icon(error ? Icons.error_outline : Icons.info_outline, color: color),
                  ),
                  Expanded(
                    child: Text(texto, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
                  ),
                ],
              ),
              if (accion != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: alAccionar,
                    style: TextButton.styleFrom(
                      foregroundColor: error ? _tintaError : esquema.primary,
                    ),
                    child: Text(accion!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La falla de lo último que se tocó (empezar la descarga, borrar un mapa): qué pasó y que se puede
/// volver a tocar.
class _FallaDeAccion extends StatelessWidget {
  const _FallaDeAccion({required this.falla});

  final Failure falla;

  @override
  Widget build(BuildContext context) => _Banner(
    clave: const Key('mapas_offline_falla'),
    tipo: _TipoBanner.error,
    texto: falla.mensaje,
  );
}
