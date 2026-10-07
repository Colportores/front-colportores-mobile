import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dispositivo/abridor_ajustes_sistema.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart';
import '../../domain/entities/situacion_mapa.dart';
import '../providers/situacion_mapa_providers.dart';
import 'piezas_alta.dart';

/// Los textos del aviso del mapa (HU-UBI-003, vista 06: artboards 06C·05, 06C·06 y 06C·07). Los de
/// 06C·05, 06C·06 y 06C·07 son los del canvas, letra por letra; el de «No pudimos cargar…» lo pidió
/// Cristian en el issue #190 y su forma no está dibujada (ver `pendientes`).
abstract final class TextosAvisoMapa {
  // 06C·05 — sin conexión.
  static const sinConexionTitulo = 'Sin conexión a internet';
  static const sinConexionCuerpo =
      'Tus ubicaciones se siguen viendo. Para ver las calles, activá tus datos móviles o '
      'descargá el mapa.';
  static const descargarMapa = 'Descargar mapa';
  static const activarDatos = 'Activar datos';
  static const minimizarAviso = 'Minimizar aviso';

  // 06C·06 — aviso minimizado.
  static const pildoraSinConexion = 'Sin conexión · Descargar mapa';

  // 06C·07 — con datos móviles.
  static const datosMovilesTitulo = 'Estás viendo el mapa con datos móviles';
  static const datosMovilesCuerpo =
      'Descargalo para usarlo aunque no tengas señal. Conviene hacerlo con Wi-Fi.';
  static const ahoraNo = 'Ahora no';
  static String descargarMapaConPeso(int megabytes) => 'Descargar mapa · $megabytes MB';

  // Con conexión y el mapa no carga (issue #190, comentario del 06/10).
  static const noCargaTitulo = 'No pudimos cargar el mapa de esta ciudad';
  static const noCargaCuerpo =
      'Tus ubicaciones se siguen viendo. Para ver las calles, probá de nuevo.';
  static const reintentar = 'Reintentar';

  // Entre tocar «Descargar mapa» y tener el mapa (decisión del 06/10 sobre el pendiente P1).
  static const seDescargaSola = 'Se descarga sola cuando vuelva la señal.';
  static const descargandoMapa = 'Descargando el mapa…';

  /// «Activar datos» no pudo abrir los ajustes de red del teléfono. Propuesta: el mismo texto de la
  /// pantalla de preparación (`TextosPreparacionDbLocal.noPudimosAbrirAjustes`).
  static const noPudimosAbrirAjustes =
      'No pudimos abrir los ajustes. Abrilos a mano desde el menú del teléfono.';
}

/// Las claves de cada aviso (para los tests y la QA).
abstract final class ClavesAvisoMapa {
  static const sinConexion = Key('aviso_mapa_sin_conexion');
  static const pildora = Key('aviso_mapa_pildora');
  static const datosMoviles = Key('aviso_mapa_datos_moviles');
  static const noCarga = Key('aviso_mapa_no_carga');
}

/// Dónde va el aviso.
enum AvisoMapaModo {
  /// Dentro de la hoja de la vista 03 (alta), arriba del formulario: sin ✕ ni píldora.
  enHoja,

  /// Flotando sobre el mapa de la vista 06, abajo de la barra de estado: con ✕, píldora y los
  /// descartes de la sesión.
  flotante,
}

const _tintaAviso = Color(0xFF0E1A2B);
const _azulBoton = Color(0xFF002856);

/// El aviso del mapa de [ambito] según la conexión, lo descargado y el catálogo: «Sin conexión»
/// (06C·05 y, minimizado, 06C·06), «Estás viendo el mapa con datos móviles» (06C·07) o «No pudimos
/// cargar el mapa de esta ciudad». Sin nada que avisar no ocupa lugar.
///
/// Con [AvisoMapaModo.flotante] hay que ponerlo en un `Stack` que cubra el mapa: se acomoda arriba
/// (top 8, a 14 de los costados) y no tapa los toques fuera de sí mismo.
class AvisoMapaConectado extends ConsumerStatefulWidget {
  const AvisoMapaConectado({super.key, required this.ambito, this.modo = AvisoMapaModo.enHoja});

  final AmbitoTrabajo ambito;
  final AvisoMapaModo modo;

  @override
  ConsumerState<AvisoMapaConectado> createState() => _AvisoMapaConectadoState();
}

class _AvisoMapaConectadoState extends ConsumerState<AvisoMapaConectado> {
  bool _abriendoAjustes = false;
  bool _reintentando = false;

  bool get _flotante => widget.modo == AvisoMapaModo.flotante;

  Future<void> _descargar() => ref.read(solicitudMapaProvider(widget.ambito).notifier).pedir();

  Future<void> _activarDatos() async {
    if (_abriendoAjustes) return;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    setState(() => _abriendoAjustes = true);
    var abierta = false;
    try {
      abierta = await ref.read(abridorAjustesSistemaProvider).abrirRed();
    } on Object {
      abierta = false;
    } finally {
      if (mounted) setState(() => _abriendoAjustes = false);
    }
    if (!abierta) {
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosAvisoMapa.noPudimosAbrirAjustes)));
    }
  }

  Future<void> _reintentar() async {
    if (_reintentando) return;
    setState(() => _reintentando = true);
    try {
      final consulta = paqueteDelAmbitoProvider(widget.ambito);
      ref.invalidate(consulta);
      await ref.read(consulta.future);
    } on Object {
      // El proveedor ya convierte sus fallos en un valor; si igual llega un error, el aviso sigue.
    } finally {
      if (mounted) setState(() => _reintentando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = ref.watch(situacionMapaProvider(widget.ambito).select((s) => s.aviso));
    final descartes = ref.watch(descartesAvisoMapaProvider);
    final descartador = ref.read(descartesAvisoMapaProvider.notifier);
    return switch (aviso) {
      null => const SizedBox.shrink(),
      AvisoSinConexion() =>
        _flotante && descartes.sinConexionMinimizado
            ? _ubicar(
                _PildoraSinConexion(ambito: widget.ambito, alPresionar: _descargar),
                ancho: false,
              )
            : _ubicar(
                _TarjetaSinConexion(
                  ambito: widget.ambito,
                  alDescargar: _descargar,
                  alActivarDatos: _activarDatos,
                  alMinimizar: _flotante ? descartador.minimizarSinConexion : null,
                  abriendoAjustes: _abriendoAjustes,
                ),
              ),
      AvisoDatosMoviles(:final megabytes) =>
        descartes.datosMovilesOculto
            ? const SizedBox.shrink()
            : _ubicar(
                _TarjetaDatosMoviles(
                  ambito: widget.ambito,
                  megabytes: megabytes,
                  alDescargar: _descargar,
                  alDescartar: descartador.ocultarDatosMoviles,
                ),
              ),
      AvisoMapaNoCarga() => _ubicar(
        _TarjetaNoCarga(alReintentar: _reintentar, reintentando: _reintentando),
      ),
    };
  }

  /// En la hoja, un renglón más con aire abajo; sobre el mapa, anclado arriba a la izquierda (la
  /// píldora) o a todo el ancho menos 14 (las tarjetas).
  Widget _ubicar(Widget aviso, {bool ancho = true}) {
    if (!_flotante) return Padding(padding: const EdgeInsets.only(bottom: 12), child: aviso);
    final altoMaximo = MediaQuery.sizeOf(context).height * .8;
    return Align(
      alignment: ancho ? Alignment.topCenter : Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, ancho ? 8 : 6, ancho ? 14 : 0, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: altoMaximo),
          child: ancho
              ? SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(child: aviso),
                )
              : aviso,
        ),
      ),
    );
  }
}

/// Qué dice el aviso mientras el mapa está pedido y todavía no está: en cola o bajando. `null` si no
/// hay nada que decir.
String? _textoDelPedido(EstadoSolicitudMapa solicitud) {
  if (solicitud.esperaSenal) return TextosAvisoMapa.seDescargaSola;
  if (solicitud.bajando) return TextosAvisoMapa.descargandoMapa;
  return null;
}

/// Lo que cambia entre las tarjetas: colores, insignia, textos y botones.
class _TarjetaAvisoMapa extends StatelessWidget {
  const _TarjetaAvisoMapa({
    super.key,
    required this.fondo,
    required this.insignia,
    required this.titulo,
    required this.cuerpo,
    required this.colorTitulo,
    required this.colorCuerpo,
    required this.pesoTitulo,
    required this.tamanoTitulo,
    required this.botones,
    this.borde,
    this.avance,
    this.falla,
    this.colorFalla,
    this.alMinimizar,
  });

  final Color fondo;
  final Color? borde;
  final Widget insignia;
  final String titulo;
  final String cuerpo;
  final Color colorTitulo;
  final Color colorCuerpo;
  final FontWeight pesoTitulo;
  final double tamanoTitulo;
  final List<Widget> botones;

  /// En qué está el pedido de «Descargar mapa»: «Se descarga sola…» o «Descargando el mapa…».
  final String? avance;

  /// El motivo de que el último pedido no saliera: «Espacio insuficiente…», etc.
  final String? falla;
  final Color? colorFalla;

  /// La ✕ de «Minimizar aviso»; `null` en la hoja del alta y en el aviso de datos móviles.
  final VoidCallback? alMinimizar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(16),
          border: borde == null ? null : Border.all(color: borde!, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                insignia,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: tamanoTitulo,
                          fontWeight: pesoTitulo,
                          color: colorTitulo,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cuerpo,
                        style: TextStyle(fontSize: 13.5, height: 1.45, color: colorCuerpo),
                      ),
                      if (avance != null) ...[
                        const SizedBox(height: 6),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            avance!,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: colorTitulo,
                            ),
                          ),
                        ),
                      ],
                      if (falla != null) ...[
                        const SizedBox(height: 6),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            falla!,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: colorFalla ?? colorCuerpo,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (alMinimizar != null)
                  SizedBox(
                    width: 48,
                    height: 48,
                    // El lector de pantalla dice «Minimizar aviso», no «✕»; el tooltip es para
                    // quien mantiene el dedo apretado.
                    child: Semantics(
                      button: true,
                      label: TextosAvisoMapa.minimizarAviso,
                      onTap: alMinimizar,
                      excludeSemantics: true,
                      child: IconButton(
                        onPressed: alMinimizar,
                        tooltip: TextosAvisoMapa.minimizarAviso,
                        padding: EdgeInsets.zero,
                        color: colorTitulo,
                        icon: Text('✕', style: TextStyle(fontSize: 15, color: colorTitulo)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < botones.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              botones[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// El círculo de la insignia de las tarjetas: [fondo] liso con [glyph] adentro.
class _Insignia extends StatelessWidget {
  const _Insignia({
    required this.fondo,
    required this.colorGlyph,
    required this.glyph,
    this.tamano = 26,
    this.radio,
  });

  final Color fondo;
  final Color colorGlyph;
  final String glyph;
  final double tamano;

  /// Esquinas redondeadas en vez de círculo (la insignia «⇩» de 06C·07).
  final double? radio;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: tamano,
        height: tamano,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fondo,
          shape: radio == null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radio == null ? null : BorderRadius.circular(radio!),
        ),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: tamano <= 22 ? 12 : 14,
            fontWeight: FontWeight.w700,
            color: colorGlyph,
            height: 1,
          ),
        ),
      ),
    );
  }
}

ButtonStyle _estiloPildora({
  required Color fondo,
  required Color texto,
  required FontWeight peso,
  BorderSide? borde,
}) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
  shape: const WidgetStatePropertyAll(StadiumBorder()),
  side: borde == null ? null : WidgetStatePropertyAll(borde),
  backgroundColor: WidgetStateProperty.resolveWith(
    (estados) => estados.contains(WidgetState.disabled) ? fondo.withValues(alpha: .6) : fondo,
  ),
  foregroundColor: WidgetStateProperty.resolveWith(
    (estados) => estados.contains(WidgetState.disabled) ? texto.withValues(alpha: .6) : texto,
  ),
  textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: peso)),
);

/// 06C·05 — la tarjeta roja de «Sin conexión a internet».
class _TarjetaSinConexion extends ConsumerWidget {
  const _TarjetaSinConexion({
    required this.ambito,
    required this.alDescargar,
    required this.alActivarDatos,
    required this.alMinimizar,
    required this.abriendoAjustes,
  });

  final AmbitoTrabajo ambito;
  final VoidCallback alDescargar;
  final VoidCallback alActivarDatos;
  final VoidCallback? alMinimizar;
  final bool abriendoAjustes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitud = ref.watch(solicitudMapaProvider(ambito));
    return _TarjetaAvisoMapa(
      key: ClavesAvisoMapa.sinConexion,
      fondo: ColoresAlta.rojo,
      insignia: const _Insignia(fondo: Colors.white, colorGlyph: ColoresAlta.rojo, glyph: '!'),
      titulo: TextosAvisoMapa.sinConexionTitulo,
      cuerpo: TextosAvisoMapa.sinConexionCuerpo,
      colorTitulo: Colors.white,
      colorCuerpo: Colors.white,
      pesoTitulo: FontWeight.w700,
      tamanoTitulo: 15.5,
      avance: _textoDelPedido(solicitud),
      falla: solicitud.falla?.mensaje,
      alMinimizar: alMinimizar,
      botones: [
        FilledButton(
          onPressed: solicitud.enMarcha ? null : alDescargar,
          style: _estiloPildora(
            fondo: Colors.white,
            texto: ColoresAlta.rojo,
            peso: FontWeight.w700,
          ),
          child: const Text(TextosAvisoMapa.descargarMapa, textAlign: TextAlign.center),
        ),
        OutlinedButton(
          onPressed: abriendoAjustes ? null : alActivarDatos,
          style: _estiloPildora(
            fondo: Colors.transparent,
            texto: Colors.white,
            peso: FontWeight.w600,
            borde: const BorderSide(color: Colors.white, width: 1.5),
          ),
          child: const Text(TextosAvisoMapa.activarDatos, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// 06C·06 — la píldora roja que queda cuando se minimiza el aviso, mientras no haya conexión.
class _PildoraSinConexion extends ConsumerWidget {
  const _PildoraSinConexion({required this.ambito, required this.alPresionar})
    : super(key: ClavesAvisoMapa.pildora);

  final AmbitoTrabajo ambito;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitud = ref.watch(solicitudMapaProvider(ambito));
    // La píldora no tiene lugar para el motivo de una falla ni para decir en qué está el pedido: sale
    // como aviso pasajero.
    ref.listen(solicitudMapaProvider(ambito).select((s) => s.falla), (_, falla) {
      if (falla == null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(falla.mensaje)));
    });
    ref.listen(solicitudMapaProvider(ambito).select(_textoDelPedido), (anterior, texto) {
      if (texto == null || texto == anterior) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(texto)));
    });
    // El área de toque es de 48 y la píldora dibujada de 44, como en el canvas.
    return Semantics(
      liveRegion: true,
      container: true,
      button: true,
      enabled: !solicitud.enMarcha,
      excludeSemantics: true,
      label: TextosAvisoMapa.pildoraSinConexion,
      onTap: solicitud.enMarcha ? null : alPresionar,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Material(
            color: ColoresAlta.rojo,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: solicitud.enMarcha ? null : alPresionar,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 14, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Insignia(
                        fondo: Colors.white,
                        colorGlyph: ColoresAlta.rojo,
                        glyph: '!',
                        tamano: 22,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          TextosAvisoMapa.pildoraSinConexion,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 06C·07 — la tarjeta blanca de «Estás viendo el mapa con datos móviles».
class _TarjetaDatosMoviles extends ConsumerWidget {
  const _TarjetaDatosMoviles({
    required this.ambito,
    required this.megabytes,
    required this.alDescargar,
    required this.alDescartar,
  });

  final AmbitoTrabajo ambito;
  final int megabytes;
  final VoidCallback alDescargar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitud = ref.watch(solicitudMapaProvider(ambito));
    return _TarjetaAvisoMapa(
      key: ClavesAvisoMapa.datosMoviles,
      fondo: Colors.white,
      borde: ColoresAlta.grisBorde,
      insignia: const _Insignia(fondo: _azulBoton, colorGlyph: Colors.white, glyph: '⇩', radio: 7),
      titulo: TextosAvisoMapa.datosMovilesTitulo,
      cuerpo: TextosAvisoMapa.datosMovilesCuerpo,
      colorTitulo: _tintaAviso,
      colorCuerpo: ColoresAlta.tinta,
      pesoTitulo: FontWeight.w600,
      tamanoTitulo: 15,
      avance: _textoDelPedido(solicitud),
      falla: solicitud.falla?.mensaje,
      colorFalla: ColoresAlta.rojo,
      botones: [
        FilledButton(
          onPressed: solicitud.enMarcha ? null : alDescargar,
          style: _estiloPildora(fondo: _azulBoton, texto: Colors.white, peso: FontWeight.w600),
          child: Text(TextosAvisoMapa.descargarMapaConPeso(megabytes), textAlign: TextAlign.center),
        ),
        TextButton(
          onPressed: alDescartar,
          style: _estiloPildora(
            fondo: Colors.transparent,
            texto: ColoresAlta.azul,
            peso: FontWeight.w600,
          ),
          child: const Text(TextosAvisoMapa.ahoraNo, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// Con conexión y el mapa no carga: la forma no está en el canvas, así que usa la de 06C·07 (tarjeta
/// blanca) con la insignia roja de «!» del aviso de conexión y un solo botón. Fondo liso, sin gris.
class _TarjetaNoCarga extends StatelessWidget {
  const _TarjetaNoCarga({required this.alReintentar, required this.reintentando});

  final VoidCallback alReintentar;
  final bool reintentando;

  @override
  Widget build(BuildContext context) {
    return _TarjetaAvisoMapa(
      key: ClavesAvisoMapa.noCarga,
      fondo: Colors.white,
      borde: ColoresAlta.grisBorde,
      insignia: const _Insignia(fondo: ColoresAlta.rojo, colorGlyph: Colors.white, glyph: '!'),
      titulo: TextosAvisoMapa.noCargaTitulo,
      cuerpo: TextosAvisoMapa.noCargaCuerpo,
      colorTitulo: _tintaAviso,
      colorCuerpo: ColoresAlta.tinta,
      pesoTitulo: FontWeight.w600,
      tamanoTitulo: 15,
      botones: [
        FilledButton(
          onPressed: reintentando ? null : alReintentar,
          style: _estiloPildora(fondo: _azulBoton, texto: Colors.white, peso: FontWeight.w600),
          child: const Text(TextosAvisoMapa.reintentar, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
