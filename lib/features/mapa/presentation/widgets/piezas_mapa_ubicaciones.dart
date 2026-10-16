import 'package:flutter/material.dart';

import '../../domain/entities/estado_casa.dart';
import '../formato_mapa_ubicaciones.dart';
import '../mapa_base/modelo_mapa_base.dart' show ColoresMapa;
import 'piezas_alta.dart' show ColoresAlta;
import 'piezas_lista_ubicaciones.dart';

/// Las claves con que los tests (y el QA) encuentran lo que dibuja el mapa de ubicaciones.
abstract final class ClavesMapaUbicaciones {
  static const miUbicacion = Key('mapa_mi_ubicacion');
  static const nueva = Key('mapa_nueva');
  static const referencias = Key('mapa_referencias');
  static const hoja = Key('mapa_hoja');
  static const asa = Key('mapa_asa');
  static const pestanaCercania = Key('mapa_pestana_cercania');
  static const vistaPrevia = Key('mapa_vista_previa');
  static const cerrarVistaPrevia = Key('mapa_vista_previa_cerrar');
  static const cargando = Key('mapa_cargando');
  static const vacio = Key('mapa_vacio');
  static const error = Key('mapa_error');
  static const reintentar = Key('mapa_reintentar');
  static const activarGps = Key('mapa_activar_gps');
  static const registrarPrimera = Key('mapa_registrar_primera');
  static const hojaReferencias = Key('mapa_hoja_referencias');
  static const cerrarReferencias = Key('mapa_referencias_cerrar');

  /// La fila de la ubicación [id] en la hoja.
  static Key fila(String id) => Key('mapa_fila_$id');
}

/// «Mi ubicación» (canvas, 06C·01): el botón redondo blanco de 52 dp que centra el mapa en el GPS.
/// Sin [alPresionar] está deshabilitado (HU-UBI-003, «Edge: sin GPS»).
class BotonMiUbicacion extends StatelessWidget {
  const BotonMiUbicacion({super.key, required this.alPresionar});

  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final habilitado = alPresionar != null;
    return Semantics(
      button: true,
      enabled: habilitado,
      label: TextosMapaUbicaciones.miUbicacion,
      hint: habilitado ? null : TextosMapaUbicaciones.miUbicacionSinGps,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          elevation: 3,
          shape: const CircleBorder(),
          child: InkResponse(
            customBorder: const CircleBorder(),
            onTap: alPresionar,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                Icons.my_location,
                size: 22,
                color: habilitado ? ColoresMapa.aroSeleccion : ColoresLista.chevron,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «+ Nueva» (canvas): la píldora navy de 52 dp de alto que abre el alta.
class BotonNuevaUbicacion extends StatelessWidget {
  const BotonNuevaUbicacion({super.key, required this.alPresionar});

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.nuevaUbicacion,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: Theme.of(context).colorScheme.primary,
          elevation: 4,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 20, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('+', style: TextStyle(color: Colors.white, fontSize: 22, height: 1)),
                    SizedBox(width: 8),
                    Text(
                      TextosMapaUbicaciones.nueva,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El chip «Referencias» de arriba a la derecha (canvas): abre la leyenda de los marcadores.
class ChipReferencias extends StatelessWidget {
  const ChipReferencias({super.key, required this.alPresionar});

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.referencias,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_outlined, size: 18, color: ColoresAlta.azul),
                    SizedBox(width: 7),
                    Text(
                      TextosMapaUbicaciones.referencias,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ColoresAlta.azul,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre la leyenda «Referencias». Devuelve cuando se cierra.
Future<void> mostrarReferenciasMapa(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => const HojaReferenciasMapa(),
);

/// La leyenda de los marcadores de la vista 06. El canvas la dibuja entera y la marca «PROPUESTA»
/// (con los ocho estados de la visita y la venta); acá van solo los marcadores que el mapa dibuja
/// hoy: hasta que lleguen los colores por estado (HU-VIS-005) todas las ubicaciones se ven «Sin
/// visita».
class HojaReferenciasMapa extends StatelessWidget {
  const HojaReferenciasMapa({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: ClavesMapaUbicaciones.hojaReferencias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                TextosMapaUbicaciones.referencias,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _FilaReferencia(
              muestra: InsigniaEstadoCasa(estado: EstadoCasa.sinVisita, tamano: 24),
              texto: TextosMapaUbicaciones.leyendaSinVisita,
            ),
            const _FilaReferencia(
              muestra: _MuestraGrupo(),
              texto: TextosMapaUbicaciones.leyendaAgrupadas,
            ),
            const _FilaReferencia(
              muestra: _MuestraCerca(),
              texto: TextosMapaUbicaciones.leyendaCerca,
            ),
            const _FilaReferencia(
              muestra: _MuestraTuUbicacion(),
              texto: TextosMapaUbicaciones.leyendaTuUbicacion,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ClavesMapaUbicaciones.cerrarReferencias,
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(
                  foregroundColor: ColoresAlta.azul,
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text(TextosMapaUbicaciones.cerrar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaReferencia extends StatelessWidget {
  const _FilaReferencia({required this.muestra, required this.texto});

  final Widget muestra;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: texto,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            SizedBox(width: 44, child: Center(child: muestra)),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

/// El círculo de un grupo (canvas: «9»).
class _MuestraGrupo extends StatelessWidget {
  const _MuestraGrupo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ColoresMapa.tintaOscura,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Text(
        '9',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// La etiqueta de «cerca tuyo» (canvas: «1234»).
class _MuestraCerca extends StatelessWidget {
  const _MuestraCerca();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ColoresMapa.bordeContexto, width: 2),
      ),
      child: const Text(
        '1234',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: ColoresMapa.tinta,
          height: 1,
        ),
      ),
    );
  }
}

/// El punto azul del GPS.
class _MuestraTuUbicacion extends StatelessWidget {
  const _MuestraTuUbicacion();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: ColoresMapa.puntoGps,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x292F6FD1), spreadRadius: 6)],
      ),
    );
  }
}
