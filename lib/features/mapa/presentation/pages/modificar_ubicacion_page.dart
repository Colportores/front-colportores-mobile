import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/resultado_modificacion_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../providers/alta_ubicacion_notifier.dart'
    show AltaConCandidatas, AltaCreada, AltaFallida, AltaIgnorada;
import '../providers/alta_ubicacion_providers.dart';
import '../providers/modificar_ubicacion_notifier.dart';
import '../widgets/aviso_mapa.dart';
import '../widgets/dialogos_modificar.dart';
import '../widgets/hoja_ciudad.dart';
import '../widgets/hoja_duplicado_alta.dart';
import '../widgets/hoja_modificar.dart';
import '../widgets/mapa_modificar.dart';
import '../widgets/piezas_alta.dart';

/// Cómo se cerró la edición de una ubicación.
sealed class SalidaModificarUbicacion {
  const SalidaModificarUbicacion();
}

/// La ubicación quedó modificada en el teléfono: el mapa vuelve con ella seleccionada.
final class UbicacionEditada extends SalidaModificarUbicacion {
  const UbicacionEditada(this.ubicacion, {this.reactivada = false});

  final Ubicacion ubicacion;

  /// Estaba en baja y se reactivó al guardar.
  final bool reactivada;
}

/// El colportor eligió «Reutilizar esta» (o «Abrir la existente») en el aviso de duplicado: la
/// edición no se guardó y se abre esa otra ubicación.
final class UbicacionExistenteElegida extends SalidaModificarUbicacion {
  const UbicacionExistenteElegida(this.ubicacionId);

  final String ubicacionId;
}

/// Vista 07 (HU-UBI-004, #202): modificar una ubicación que ya está en el teléfono.
///
/// Pantalla completa, como el alta: el mapa arriba (quieto hasta tocar «Mover el punto») y abajo la
/// hoja con el tipo, la ciudad, la calle y el número. Lo que se cambia es un borrador: recién
/// «Guardar cambios» escribe en el teléfono y, si hay algo para confirmar (reactivar, cambiar la
/// ciudad, mover el punto más de 100 m) o la ubicación quedaría como otra, lo pregunta antes. Sale con
/// un [SalidaModificarUbicacion], o con `null` si el colportor cierra sin guardar.
class ModificarUbicacionPage extends ConsumerStatefulWidget {
  const ModificarUbicacionPage({super.key, required this.parametros, this.alDarDeBaja});

  final ParametrosModificar parametros;

  /// «Dar de baja». Sin esto el botón no se dibuja: ese flujo es el de HU-UBI-005.
  final VoidCallback? alDarDeBaja;

  static var _aperturas = 0;

  /// Abre la edición de [ubicacionId] encima de la pantalla actual.
  static Future<SalidaModificarUbicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    required String ubicacionId,
    VoidCallback? alDarDeBaja,
  }) => Navigator.of(context).push<SalidaModificarUbicacion>(
    MaterialPageRoute(
      builder: (_) => ModificarUbicacionPage(
        parametros: ParametrosModificar(
          colportorId: colportorId,
          ubicacionId: ubicacionId,
          apertura: ++_aperturas,
        ),
        alDarDeBaja: alDarDeBaja,
      ),
    ),
  );

  /// Cuántas veces seguidas se vuelve a pedir el guardado con confirmaciones nuevas: hay tres
  /// posibles y cada una se pide una sola vez.
  static const _maximoRondas = 4;

  @override
  ConsumerState<ModificarUbicacionPage> createState() => _ModificarUbicacionPageState();
}

class _ModificarUbicacionPageState extends ConsumerState<ModificarUbicacionPage> {
  /// Un solo guardado a la vez, de «Guardar cambios» hasta que se cierra la pantalla o falla: un
  /// segundo toque no abre otra pregunta ni otra hoja encima.
  var _guardandoPagina = false;
  var _eligiendoCiudad = false;
  var _confirmandoSalida = false;

  ModificarUbicacionNotifier get _notificador =>
      ref.read(modificarUbicacionProvider(widget.parametros).notifier);

  ModificarUbicacionState get _estado => ref.read(modificarUbicacionProvider(widget.parametros));

  // ---------------------------------------------------------------- salir

  /// ✕ o atrás: en «Mover el punto» cancela el ajuste; con cambios sin guardar pregunta antes de
  /// descartarlos (07·04); sin ellos, cierra.
  Future<void> _intentarSalir() async {
    final estado = _estado;
    if (estado.guardando || _guardandoPagina) return;
    if (estado.modo == ModoEdicion.moverPunto) {
      _notificador.cancelarMoverPunto();
      return;
    }
    if (!estado.hayCambios) {
      Navigator.of(context).pop();
      return;
    }
    if (_confirmandoSalida) return;
    _confirmandoSalida = true;
    try {
      final descartar = await confirmarDescartarCambios(context, estado.cambios);
      if (!mounted || !descartar) return;
      Navigator.of(context).pop();
    } finally {
      _confirmandoSalida = false;
    }
  }

  // ---------------------------------------------------------------- guardar

  Future<void> _guardar() async {
    if (_guardandoPagina) return;
    _guardandoPagina = true;
    try {
      var confirmadas = <ConfirmacionModificacion>{};
      for (var ronda = 0; ronda < ModificarUbicacionPage._maximoRondas; ronda++) {
        final resultado = await _notificador.guardar(confirmadas: confirmadas);
        if (!mounted) return;
        switch (resultado) {
          case EdicionGuardada(:final ubicacion, :final reactivada):
            _terminar(UbicacionEditada(ubicacion, reactivada: reactivada));
            return;
          case EdicionSinCambios(:final ubicacion):
            _terminar(UbicacionEditada(ubicacion));
            return;
          case EdicionRequiereConfirmacion(:final pendientes, :final metros):
            final dadas = await _pedirConfirmaciones(pendientes, metros);
            if (!mounted) return;
            // «Cancelar» en cualquiera de las preguntas: no se guarda y el borrador sigue acá.
            if (dadas == null) return;
            confirmadas = {...confirmadas, ...dadas};
          case EdicionConDuplicados(:final candidatas):
            await _mostrarDuplicados(candidatas, confirmadas);
            return;
          case EdicionFallida() || EdicionIgnorada():
            return;
        }
      }
    } finally {
      _guardandoPagina = false;
    }
  }

  /// Hace una pregunta por cada confirmación pendiente, con el aviso de la HU. `null` si el
  /// colportor canceló alguna.
  Future<Set<ConfirmacionModificacion>?> _pedirConfirmaciones(
    List<ConfirmacionModificacion> pendientes,
    double? metros,
  ) async {
    final dadas = <ConfirmacionModificacion>{};
    for (final pendiente in pendientes) {
      final texto = switch (pendiente) {
        ConfirmacionModificacion.reactivar => ModificacionRequiereConfirmacion.avisoReactivar,
        ConfirmacionModificacion.cambioCiudad => ModificacionRequiereConfirmacion.avisoCambioCiudad,
        ConfirmacionModificacion.desplazamiento =>
          ModificacionRequiereConfirmacion.avisoDesplazamiento(
            metros ?? _estado.metrosMovidos ?? 0,
          ),
      };
      final confirmo = await confirmarModificacion(context, texto: texto);
      if (!mounted || !confirmo) return null;
      dadas.add(pendiente);
    }
    return dadas;
  }

  Future<Map<String, String>> _nombresCiudad() async {
    try {
      final r = await ref
          .read(ciudadesParaAltaProvider)
          .deMiCampania(widget.parametros.colportorId);
      return r.fold<Map<String, String>>(
        (_) => const {},
        (ciudades) => {for (final c in ciudades) c.id: c.nombre},
      );
    } on Object {
      return const {};
    }
  }

  /// El aviso de la vista 04 sobre la edición. «Crear igual» repite el guardado con la justificación
  /// y las confirmaciones que ya se dieron; «Reutilizar esta» deja la edición sin guardar y abre la
  /// otra ubicación.
  Future<void> _mostrarDuplicados(
    List<CandidataDuplicado> candidatas,
    Set<ConfirmacionModificacion> confirmadas,
  ) async {
    final estado = _estado;
    final punto = estado.punto;
    if (punto == null) return;
    var reactivada = false;
    final nombres = await _nombresCiudad();
    if (!mounted) return;
    final decision = await mostrarHojaDuplicado(
      context,
      candidatas: candidatas,
      puntoNuevo: punto,
      nombresCiudad: nombres,
      ambito: estado.ambitoMapa,
      crearIgual: (justificacion) async {
        final r = await _notificador.guardar(
          confirmadas: confirmadas,
          justificacion: justificacion,
        );
        if (r is EdicionGuardada) reactivada = r.reactivada;
        return switch (r) {
          EdicionGuardada(:final ubicacion) ||
          EdicionSinCambios(:final ubicacion) => AltaCreada(ubicacion),
          EdicionConDuplicados(:final candidatas) => AltaConCandidatas(candidatas),
          EdicionFallida(:final falla) => AltaFallida(falla),
          EdicionRequiereConfirmacion() || EdicionIgnorada() => const AltaIgnorada(),
        };
      },
      ahora: ref.read(relojAltaUbicacionProvider),
    );
    if (!mounted) return;
    switch (decision) {
      case DecisionReutilizar(:final ubicacionId):
        Navigator.of(context).pop(UbicacionExistenteElegida(ubicacionId));
      case DecisionCreada(:final ubicacion):
        _terminar(UbicacionEditada(ubicacion, reactivada: reactivada));
      case null:
        break;
    }
  }

  /// Los cambios quedaron en el teléfono: sin conexión se avisa que el estado se sincroniza después y
  /// la pantalla vuelve al mapa.
  void _terminar(UbicacionEditada salida) {
    final conexion = ref.read(conexionProvider).value;
    if (conexion == TipoConexion.sinConexion) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(TextosModificar.guardadoSinConexion)));
    }
    Navigator.of(context).pop(salida);
  }

  // ---------------------------------------------------------------- ciudad y GPS

  Future<void> _elegirCiudad() async {
    if (_eligiendoCiudad) return;
    _eligiendoCiudad = true;
    try {
      await mostrarHojaCiudad(
        context,
        colportorId: widget.parametros.colportorId,
        elegidaId: _estado.ciudadId,
        alElegir: _notificador.elegirCiudad,
      );
    } finally {
      _eligiendoCiudad = false;
    }
  }

  Future<void> _volverAMiUbicacion() async {
    final falla = await _notificador.volverAMiUbicacion();
    if (!mounted || falla == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(TextosModificar.sinGps)));
  }

  // ---------------------------------------------------------------- dibujo

  @override
  Widget build(BuildContext context) {
    final proveedor = modificarUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    final lista = estado.carga == CargaEdicion.lista && estado.original != null;
    final tecladoAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;
    // La conexión se escucha desde que se abre la pantalla: al guardar, `_terminar` la lee ya
    // resuelta para saber si avisa que el estado se sincroniza después.
    ref.listen(conexionProvider, (_, _) {});

    return PopScope(
      // Mientras se guarda no se sale (el resultado se perdería); con un ajuste del punto abierto o
      // cambios sin guardar, primero se pregunta.
      canPop: !estado.guardando && estado.modo == ModoEdicion.datos && !estado.hayCambios,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_intentarSalir());
      },
      child: Scaffold(
        body: lista
            ? LayoutBuilder(
                builder: (context, caja) => Column(
                  children: [
                    Expanded(
                      child: _ZonaMapa(
                        parametros: widget.parametros,
                        estado: estado,
                        tecladoAbierto: tecladoAbierto,
                        alCerrar: () => unawaited(_intentarSalir()),
                        alMoverCentro: _notificador.moverPunto,
                        alTocar: _notificador.marcarPunto,
                        alMoverElPunto: _notificador.entrarAMoverPunto,
                        alVolverAMiUbicacion: () => unawaited(_volverAMiUbicacion()),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: caja.maxHeight * .62),
                      child: _Hoja(
                        parametros: widget.parametros,
                        estado: estado,
                        alGuardar: () => unawaited(_guardar()),
                        alElegirCiudad: () => unawaited(_elegirCiudad()),
                        alDarDeBaja: widget.alDarDeBaja,
                      ),
                    ),
                  ],
                ),
              )
            : _SinUbicacion(
                estado: estado,
                alCerrar: () => Navigator.of(context).maybePop(),
                alReintentar: () => unawaited(_notificador.reintentarCarga()),
              ),
      ),
    );
  }
}

/// La hoja de abajo: el formulario o el ajuste del punto.
class _Hoja extends StatelessWidget {
  const _Hoja({
    required this.parametros,
    required this.estado,
    required this.alGuardar,
    required this.alElegirCiudad,
    required this.alDarDeBaja,
  });

  final ParametrosModificar parametros;
  final ModificarUbicacionState estado;
  final VoidCallback alGuardar;
  final VoidCallback alElegirCiudad;
  final VoidCallback? alDarDeBaja;

  @override
  Widget build(BuildContext context) {
    final mover = estado.modo == ModoEdicion.moverPunto;
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x1F0E1A2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: ColoresAlta.grisBorde,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (mover) ...[
                AvisoMapaConectado(ambito: estado.ambitoMapa),
                HojaMoverPunto(parametros: parametros),
              ] else
                HojaModificarDatos(
                  parametros: parametros,
                  alGuardar: alGuardar,
                  alElegirCiudad: alElegirCiudad,
                  alDarDeBaja: alDarDeBaja,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El mapa y lo que flota encima: «Cerrar», el título, «Mover el punto» o, ya moviendo, cuánto se
/// movió y «Volver a mi ubicación».
class _ZonaMapa extends StatelessWidget {
  const _ZonaMapa({
    required this.parametros,
    required this.estado,
    required this.tecladoAbierto,
    required this.alCerrar,
    required this.alMoverCentro,
    required this.alTocar,
    required this.alMoverElPunto,
    required this.alVolverAMiUbicacion,
  });

  final ParametrosModificar parametros;
  final ModificarUbicacionState estado;

  /// Con el teclado abierto el mapa queda muy chico: el botón «Mover el punto» se oculta para no
  /// tapar el pin. El colportor está escribiendo, no moviendo el punto.
  final bool tecladoAbierto;
  final VoidCallback alCerrar;
  final ValueChanged<Coordenadas> alMoverCentro;
  final ValueChanged<Coordenadas> alTocar;
  final VoidCallback alMoverElPunto;
  final VoidCallback alVolverAMiUbicacion;

  @override
  Widget build(BuildContext context) {
    final arriba = MediaQuery.paddingOf(context).top;
    final mover = estado.modo == ModoEdicion.moverPunto;
    final metros = estado.metrosMovidos ?? 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Mientras se guarda el punto no se toca: si el guardado falla o devuelve candidatas, el pin
        // tiene que seguir donde estaba.
        IgnorePointer(
          ignoring: estado.guardando,
          child: MapaModificar(
            colportorId: parametros.colportorId,
            estado: estado,
            alMoverCentro: alMoverCentro,
            alTocar: alTocar,
          ),
        ),
        Positioned(
          left: 14,
          top: arriba + 8,
          child: BotonRedondoMapa(
            tamano: 48,
            icono: Icons.close,
            etiqueta: TextosModificar.cerrar,
            alPresionar: estado.guardando ? null : alCerrar,
          ),
        ),
        Positioned(
          left: 72,
          right: 14,
          top: arriba + 14,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _Pildora(
              texto: mover ? TextosModificar.tituloMover : TextosModificar.tituloEditar,
              encabezado: true,
            ),
          ),
        ),
        if (mover && metros >= MapaModificar.metrosParaFantasma)
          Positioned(
            left: 14,
            right: 14,
            top: arriba + 8 + 48 + 10,
            child: Align(
              alignment: Alignment.topCenter,
              child: _Pildora(texto: TextosModificar.moviste(metros), aviso: true),
            ),
          ),
        if (mover)
          Positioned(
            right: 14,
            bottom: 36,
            child: BotonRedondoMapa(
              tamano: 52,
              icono: Icons.my_location,
              etiqueta: TextosModificar.volverAMiUbicacion,
              alPresionar: alVolverAMiUbicacion,
            ),
          )
        else if (!tecladoAbierto)
          Positioned(
            right: 14,
            bottom: 36,
            child: _BotonMoverPunto(alPresionar: estado.guardando ? null : alMoverElPunto),
          ),
      ],
    );
  }
}

/// «⤢ Mover el punto»: pasa a ajustar la posición (07·02).
class _BotonMoverPunto extends StatelessWidget {
  const _BotonMoverPunto({required this.alPresionar});

  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: alPresionar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_with, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    TextosModificar.moverElPunto,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una píldora blanca sobre el mapa: el título de la vista («EDITAR UBICACIÓN») o el aviso de cuánto
/// se movió el punto.
class _Pildora extends StatelessWidget {
  const _Pildora({required this.texto, this.encabezado = false, this.aviso = false});

  final String texto;
  final bool encabezado;
  final bool aviso;

  @override
  Widget build(BuildContext context) {
    final cuerpo = Material(
      color: Colors.white,
      elevation: 2,
      shape: const StadiumBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: encabezado ? 12.5 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: encabezado ? .6 : 0,
              color: ColoresAlta.tinta,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      header: encabezado,
      liveRegion: aviso,
      container: true,
      label: texto,
      excludeSemantics: true,
      child: cuerpo,
    );
  }
}

/// Lo que se ve mientras la ubicación se lee, o si no está o no se pudo leer: una barra con «Cerrar»
/// y el estado al centro.
class _SinUbicacion extends StatelessWidget {
  const _SinUbicacion({required this.estado, required this.alCerrar, required this.alReintentar});

  final ModificarUbicacionState estado;
  final VoidCallback alCerrar;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final arriba = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: ColoresAlta.fondoMapa,
      child: Stack(
        fit: StackFit.expand,
        children: [
          EstadoCargaModificar(estado: estado, alReintentar: alReintentar, alVolver: alCerrar),
          Positioned(
            left: 14,
            top: arriba + 8,
            child: BotonRedondoMapa(
              tamano: 48,
              icono: Icons.close,
              etiqueta: TextosModificar.cerrar,
              alPresionar: alCerrar,
            ),
          ),
          Positioned(
            left: 72,
            right: 14,
            top: arriba + 14,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: _Pildora(texto: TextosModificar.tituloEditar, encabezado: true),
            ),
          ),
        ],
      ),
    );
  }
}
