import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/armador_candidatas_alternativa.dart';
import '../formato_ubicaciones.dart';
import '../providers/ubicacion_alternativa_providers.dart';
import '../providers/ubicacion_colportor_provider.dart';
import '../textos_ubicacion_alternativa.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_ubicacion_alternativa.dart';
import 'alta_ubicacion_page.dart';

/// «¿Dónde le cobrás?» (HU-UBI-013, vista 22A·02 a 22A·05): el selector de la ubicación alternativa de
/// cobranza de una persona. Se abre desde la sección «COBRANZA» de su ficha y devuelve la [Ubicacion]
/// elegida (o `null` si se cierra sin elegir); quien lo abre la guarda.
///
/// - Solo se elige entre las ubicaciones propias, activas y distintas de la del espacio de la persona:
///   no se acepta texto suelto.
/// - Con GPS van por cercanía, con su distancia; sin él van por dirección y el rótulo no promete una
///   cercanía que no hay.
/// - **22A·03** cargando, **22A·04** sin otras ubicaciones (con «Registrar una ubicación»), **22A·05**
///   búsqueda sin resultados y un error al leer con «Reintentar».
/// - «+ Registrar una ubicación» abre el alta y, al volver, la lista (que lee en vivo) ya trae la nueva.
/// - Un segundo toque sobre una fila no elige dos veces.
class ElegirUbicacionAlternativaPage extends ConsumerStatefulWidget {
  const ElegirUbicacionAlternativaPage({
    super.key,
    required this.colportorId,
    required this.espacioId,
    this.ubicacionActualId,
    this.alRegistrar,
  });

  /// Quién cobra: solo se eligen ubicaciones que registró él.
  final String colportorId;

  /// El espacio de la persona: su ubicación no se ofrece.
  final String espacioId;

  /// La ubicación que hoy es la alternativa (si se abre para cambiarla): su fila queda en su lugar del
  /// orden con la etiqueta «Actual». Elegirla de nuevo no cambia nada.
  final String? ubicacionActualId;

  /// Cómo se abre el alta («+ Registrar una ubicación»). Por defecto abre `AltaUbicacionPage`; un test
  /// pone el suyo.
  final Future<void> Function()? alRegistrar;

  static Future<Ubicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    required String espacioId,
    String? ubicacionActualId,
  }) => Navigator.of(context).push<Ubicacion>(
    MaterialPageRoute(
      builder: (_) => ElegirUbicacionAlternativaPage(
        colportorId: colportorId,
        espacioId: espacioId,
        ubicacionActualId: ubicacionActualId,
      ),
    ),
  );

  @override
  ConsumerState<ElegirUbicacionAlternativaPage> createState() =>
      _ElegirUbicacionAlternativaPageState();
}

class _ElegirUbicacionAlternativaPageState extends ConsumerState<ElegirUbicacionAlternativaPage> {
  final _busqueda = TextEditingController();

  /// Ya se eligió una (la pantalla se está yendo): ningún toque más elige otra ni cierra dos veces.
  var _resuelto = false;

  var _abriendoAlta = false;

  ClaveCandidatasAlternativa get _clave =>
      (colportorId: widget.colportorId, espacioId: widget.espacioId);

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _elegir(Ubicacion ubicacion) {
    if (_resuelto) return;
    _resuelto = true;
    Navigator.of(context).pop<Ubicacion>(ubicacion);
  }

  void _cerrar() {
    if (_resuelto) return;
    _resuelto = true;
    Navigator.of(context).pop<Ubicacion>();
  }

  Future<void> _registrar() async {
    if (_abriendoAlta || _resuelto) return;
    // Con la cuenta restringida no se empieza un alta nueva.
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendoAlta = true;
    try {
      final personalizado = widget.alRegistrar;
      if (personalizado != null) {
        await personalizado();
      } else {
        await AltaUbicacionPage.abrir(context, colportorId: widget.colportorId);
      }
    } on Object catch (error, pila) {
      // El alta avisa sus propios errores; si ella misma se cae, el selector tiene que seguir usable.
      AppLogger.instance.error(
        LogModulo.map,
        'ALTERNATIVA_ALTA_FAIL',
        'no se pudo abrir el alta desde el selector',
        const {},
        error,
        pila,
      );
    } finally {
      _abriendoAlta = false;
    }
  }

  void _reintentar() => ref.invalidate(candidatasAlternativaProvider(_clave));

  @override
  Widget build(BuildContext context) {
    final lectura = ref.watch(candidatasAlternativaProvider(_clave));
    final posicion = ref.watch(ubicacionColportorProvider.select((s) => s.posicion));
    final candidatas = lectura.value;
    final lista = candidatas == null
        ? null
        : ArmadorCandidatasAlternativa.armar(
            candidatas,
            busqueda: _busqueda.text,
            posicion: posicion,
          );
    final cargando = candidatas == null && !lectura.hasError;
    final conError = candidatas == null && lectura.hasError;
    final sinCandidatas = lista != null && !lista.hayCandidatas;
    final sinResultados = lista != null && lista.hayCandidatas && lista.items.isEmpty;
    final theme = Theme.of(context);

    return Scaffold(
      key: ClavesAlternativa.selector,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 6, 0),
                child: IconButton(
                  key: ClavesAlternativa.selectorCerrar,
                  tooltip: TextosUbicacionAlternativa.cerrar,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _cerrar,
                  icon: const Icon(Icons.close, size: 26),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  const Text(
                    TextosUbicacionAlternativa.selectorRotulo,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w500,
                      color: ColoresAlta.azul,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    header: true,
                    child: Text(
                      TextosUbicacionAlternativa.selectorTitulo,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  if (!cargando && !sinCandidatas) ...[
                    const SizedBox(height: 6),
                    Text(
                      TextosUbicacionAlternativa.selectorSubtitulo,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (!sinCandidatas && !conError)
                    _CampoDeBusqueda(
                      controlador: _busqueda,
                      habilitado: !cargando,
                      alCambiar: () => setState(() {}),
                    ),
                  const SizedBox(height: 14),
                  if (cargando)
                    const _Cargando()
                  else if (conError)
                    KeyedSubtree(
                      key: ClavesAlternativa.selectorError,
                      child: AvisoAlta(
                        color: ColoresAlta.rojo,
                        glyph: '!',
                        texto: TextosUbicacionAlternativa.noPudimosLeerUbicaciones,
                        acciones: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: ClavesAlternativa.selectorReintentar,
                            onPressed: _reintentar,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: ColoresAlta.azul,
                              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            child: const Text(TextosUbicacionAlternativa.reintentar),
                          ),
                        ),
                      ),
                    )
                  else if (sinCandidatas)
                    const _Mensaje(
                      clave: ClavesAlternativa.selectorVacio,
                      glifo: '⇢',
                      titulo: TextosUbicacionAlternativa.vacioTitulo,
                      detalle: TextosUbicacionAlternativa.vacioDetalle,
                    )
                  else if (sinResultados)
                    const _Mensaje(
                      clave: ClavesAlternativa.selectorSinResultados,
                      glifo: '⌕',
                      titulo: TextosUbicacionAlternativa.sinResultadosTitulo,
                      detalle: TextosUbicacionAlternativa.sinResultadosDetalle,
                    )
                  else ...[
                    Semantics(
                      header: true,
                      child: Text(
                        lista!.porCercania
                            ? TextosUbicacionAlternativa.listaPorCercania
                            : TextosUbicacionAlternativa.lista,
                        key: ClavesAlternativa.selectorRotulo,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          letterSpacing: 1.4,
                          color: ColoresAlta.gris,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final c in lista.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FilaDeUbicacion(
                          candidata: c,
                          esActual: c.ubicacion.id == widget.ubicacionActualId,
                          alElegir: () => _elegir(c.ubicacion),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (!cargando && !conError)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: sinCandidatas
                    ? FilledButton(
                        key: ClavesAlternativa.selectorRegistrar,
                        onPressed: () => unawaited(_registrar()),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: const Text(
                          TextosUbicacionAlternativa.registrar,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : TextButton(
                        key: ClavesAlternativa.selectorRegistrarMas,
                        onPressed: () => unawaited(_registrar()),
                        style: TextButton.styleFrom(
                          foregroundColor: ColoresAlta.azul,
                          minimumSize: const Size.fromHeight(48),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        child: const Text(
                          TextosUbicacionAlternativa.registrarMas,
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CampoDeBusqueda extends StatelessWidget {
  const _CampoDeBusqueda({
    required this.controlador,
    required this.habilitado,
    required this.alCambiar,
  });

  final TextEditingController controlador;
  final bool habilitado;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: habilitado ? Colors.white : ColoresAlta.grisFondo.withValues(alpha: .5),
        border: Border.all(color: ColoresAlta.grisBorde, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(child: Icon(Icons.search, size: 20, color: ColoresAlta.gris)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: ClavesAlternativa.selectorBuscar,
              controller: controlador,
              enabled: habilitado,
              onChanged: (_) => alCambiar(),
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: TextosUbicacionAlternativa.buscar,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(color: ColoresAlta.gris),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                constraints: const BoxConstraints(minHeight: 48),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controlador,
            builder: (context, _) => controlador.text.isEmpty
                ? const SizedBox(width: 14)
                : IconButton(
                    key: ClavesAlternativa.selectorBorrarBusqueda,
                    tooltip: TextosUbicacionAlternativa.limpiarBusqueda,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      controlador.clear();
                      alCambiar();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 22A·03: tres filas de relleno mientras se leen las ubicaciones. Para el lector de pantalla, una sola
/// frase.
class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ClavesAlternativa.selectorCargando,
      liveRegion: true,
      label: TextosUbicacionAlternativa.cargandoUbicaciones,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: 64,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: ColoresAlta.grisFondo.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 22A·04 y 22A·05: un glifo, lo que pasa y qué hacer.
class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.clave,
    required this.glifo,
    required this.titulo,
    required this.detalle,
  });

  final Key clave;
  final String glifo;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: clave,
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ColoresAlta.grisFondo,
                  shape: BoxShape.circle,
                ),
                child: Text(glifo, style: const TextStyle(fontSize: 22, color: ColoresAlta.tinta)),
              ),
            ),
            const SizedBox(height: 14),
            Text(titulo, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaDeUbicacion extends StatelessWidget {
  const _FilaDeUbicacion({required this.candidata, required this.esActual, required this.alElegir});

  final CandidataAlternativa candidata;

  /// Es la alternativa de ahora: lleva la etiqueta «Actual» y el lector la anuncia.
  final bool esActual;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    final u = candidata.ubicacion;
    final distancia = candidata.distanciaMetros == null
        ? null
        : FormatoUbicaciones.distancia(candidata.distanciaMetros!);
    final titulo = FormatoUbicaciones.titulo(u);
    final detalle = FormatoUbicaciones.detalleDelTitulo(u);
    return KeyedSubtree(
      key: ClavesAlternativa.fila(u.id),
      child: TarjetaAlternativa(
        glifo: glifoDelTipo(u.tipo),
        rotulo: esActual ? TextosUbicacionAlternativa.actual : null,
        titulo: titulo,
        detalle: detalle,
        detalle2: distancia == null || distancia.isEmpty
            ? null
            : TextosUbicacionAlternativa.aDistancia(distancia),
        etiquetaSemantica: TextosUbicacionAlternativa.semanticaElegirFila(
          titulo,
          detalle,
          distancia == null || distancia.isEmpty ? null : distancia,
          esActual: esActual,
        ),
        derecha: const ExcludeSemantics(child: Icon(Icons.chevron_right, color: Color(0xFF90A0B7))),
        alTocar: alElegir,
      ),
    );
  }
}
