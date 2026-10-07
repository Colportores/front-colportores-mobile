import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_ubicaciones.dart';
import '../providers/alta_ubicacion_notifier.dart' show CampoDireccion, FuenteCampo;
import '../providers/alta_ubicacion_providers.dart';
import '../providers/modificar_ubicacion_notifier.dart';
import 'aviso_mapa.dart';
import 'campos_ubicacion.dart';
import 'hoja_alta.dart' show TextosAlta;
import 'piezas_alta.dart';

/// Textos de la vista 07 (HU-UBI-004). Los avisos literales de la HU («Esta ubicación tiene N
/// espacios…», «Las nuevas coordenadas están a …», «Esta ubicación está en baja…») salen del caso de
/// uso y del `Failure`; los rótulos son los de «TEXTOS PROPUESTA» del canvas. Lo que el canvas no
/// dice está marcado como provisorio (pendientes de #202).
abstract final class TextosModificar {
  // Canvas 07.
  static const tituloEditar = 'EDITAR UBICACIÓN';
  static const tituloMover = 'MOVER EL PUNTO';
  static const cerrar = 'Cerrar';
  static const moverElPunto = 'Mover el punto';
  static const antes = 'Antes';
  static const nuevaPosicion = 'Nueva posición';
  static const guardarPosicion = 'Guardar posición';
  static const cancelar = 'Cancelar';
  static const direccionNoCambia = 'La dirección no cambia.';
  static const guardarCambios = 'Guardar cambios';
  static const darDeBaja = 'Dar de baja';
  static const volverAMiUbicacion = TextosAlta.volverAMiUbicacion;
  static const descartarTitulo = '¿Descartar los cambios?';
  static const seguirEditando = 'Seguir editando';
  static const descartar = 'Descartar';
  static const guardadoSinConexion =
      'Cambios guardados en tu celular. El estado se sincroniza cuando vuelva la conexión.';

  static String moviste(double metros) =>
      'Moviste el punto ${FormatoUbicaciones.distancia(metros)}';

  static String puntoEstaEn(String direccion) => 'El punto está en $direccion.';

  /// «Cambiaste el tipo y el número. Si salís ahora, se pierden.»
  static String descartarCuerpo(List<String> cambios) {
    final lista = switch (cambios.length) {
      0 => 'algo',
      1 => cambios.first,
      _ => '${cambios.sublist(0, cambios.length - 1).join(', ')} y ${cambios.last}',
    };
    return 'Cambiaste $lista. Si salís ahora, se pierden.';
  }

  // Provisorios: ni la HU ni el canvas los traen.
  static const guardando = 'Guardando…';
  static const confirmar = 'Confirmar';
  static const cargando = 'Cargando la ubicación…';
  static const reintentar = 'Reintentar';
  static const volver = 'Volver';
  static const ciudadSinNombre = 'Ciudad';
  static const sinGps = 'No pudimos tomar tu ubicación. Mové el mapa hasta el lugar.';
  static const noPudimosGuardar =
      'No pudimos guardar los cambios. Lo que cargaste sigue acá: probá de nuevo.';
  static const noPudimosAbrir = 'No pudimos abrir esta ubicación. Probá de nuevo.';
  static const abrirDeNuevo = 'Abrir de nuevo';

  /// «2 espacios», «1 espacio», «Sin espacios».
  static String espacios(int n) => switch (n) {
    0 => 'Sin espacios',
    1 => '1 espacio',
    _ => '$n espacios',
  };

  /// «creada el 12/08»; con el año si no es el de [ahora].
  static String creada(DateTime creada, DateTime ahora) {
    final c = creada.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    final dia = '${dos(c.day)}/${dos(c.month)}';
    return 'creada el ${c.year == ahora.toLocal().year ? dia : '$dia/${c.year}'}';
  }
}

/// El texto del aviso rojo cuando no se pudo guardar: la falla inesperada dice qué pasó y qué hacer;
/// las demás pasan por [mensajePara] con la acción de la edición.
String mensajeFallaEdicion(Failure falla) => switch (falla) {
  FailureInesperado() => TextosModificar.noPudimosGuardar,
  _ => mensajePara(falla, accion: 'guardar los cambios.'),
};

/// La hoja de «Editar ubicación» (artboard 07·01): la dirección y el resumen de lo guardado, el tipo,
/// la ciudad, la calle y el número, «Guardar cambios» y, si quien la abre ofrece darla de baja,
/// «Dar de baja».
///
/// - «Guardar cambios» se habilita recién cuando hay un cambio; los campos cambiados dicen «Editado».
/// - De edificio a otro tipo con dos o más espacios no se puede (S17): el aviso lo dice y el botón
///   queda sin efecto. Con un solo depto sí: no hay aviso ni paso de más (el depto pasa a ser el
///   espacio de la casa).
/// - «Guardar cambios» y «Dar de baja» quedan fijos al pie de la hoja y se desplaza el resto: con un
///   teléfono chico o el texto grande la acción principal se ve siempre. Con el teclado abierto «Dar
///   de baja» no se dibuja (se está escribiendo).
class HojaModificarDatos extends ConsumerStatefulWidget {
  const HojaModificarDatos({
    super.key,
    required this.parametros,
    required this.alGuardar,
    required this.alElegirCiudad,
    this.alDarDeBaja,
    this.tecladoAbierto = false,
  });

  final ParametrosModificar parametros;
  final VoidCallback alGuardar;

  /// Abre la lista de ciudades de la campaña («Cambiar»).
  final VoidCallback alElegirCiudad;

  /// «Dar de baja». Sin esto el botón no se dibuja: el flujo de baja es de HU-UBI-005.
  final VoidCallback? alDarDeBaja;

  /// Si el teclado está abierto. Lo informa quien está arriba del `Scaffold`: dentro del cuerpo el
  /// `Scaffold` ya descontó el teclado y `viewInsets.bottom` siempre da 0.
  final bool tecladoAbierto;

  @override
  ConsumerState<HojaModificarDatos> createState() => _HojaModificarDatosState();
}

class _HojaModificarDatosState extends ConsumerState<HojaModificarDatos> {
  late final TextEditingController _calle;
  late final TextEditingController _numero;

  /// El aviso de falla: cuando aparece se lleva a la vista, arriba del botón fijo.
  final _claveFalla = GlobalKey();

  ModificarUbicacionNotifier get _notificador =>
      ref.read(modificarUbicacionProvider(widget.parametros).notifier);

  @override
  void initState() {
    super.initState();
    final estado = ref.read(modificarUbicacionProvider(widget.parametros));
    _calle = TextEditingController(text: estado.calle);
    _numero = TextEditingController(text: estado.numero);
  }

  @override
  void dispose() {
    _calle.dispose();
    _numero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = modificarUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    ref.listen(proveedor.select((s) => s.calle), (_, c) {
      if (c != _calle.text) _calle.text = c;
    });
    ref.listen(proveedor.select((s) => s.numero), (_, n) {
      if (n != _numero.text) _numero.text = n;
    });
    ref.listen(proveedor.select((s) => s.falla), (anterior, nueva) {
      if (nueva == null || nueva == anterior) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final contexto = _claveFalla.currentContext;
        if (mounted && contexto != null) {
          unawaited(Scrollable.ensureVisible(contexto, duration: Duration.zero));
        }
      });
    });
    final original = estado.original!;
    final theme = Theme.of(context);
    final bloqueo = estado.bloqueoPorEspacios;
    final falla = estado.falla;
    // El bloqueo por espacios ya tiene su aviso (con la cuenta que se leyó): el de la falla sería el
    // mismo texto dos veces.
    final mostrarFalla =
        falla != null && !(falla is FailureUbicacionConEspacios && bloqueo != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Encabezado(original: original, espacios: estado.espacios),
                const SizedBox(height: 14),
                SelectorTipoUbicacion(tipo: estado.tipo, alElegir: _notificador.elegirTipo),
                if (bloqueo != null) ...[
                  const SizedBox(height: 10),
                  AvisoAlta(
                    color: ColoresAlta.rojo,
                    glyph: '!',
                    texto: FailureUbicacionConEspacios(cantidadEspacios: bloqueo).mensaje,
                  ),
                ],
                const SizedBox(height: 14),
                CampoCiudadUbicacion(
                  nombre: estado.ciudadNombre ?? TextosModificar.ciudadSinNombre,
                  sinValor: estado.ciudadNombre == null,
                  editada: estado.ciudadCambiada,
                  enlace: TextosCampos.cambiar,
                  alTocar: estado.guardando ? null : widget.alElegirCiudad,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: CampoDireccionUbicacion(
                        etiqueta: TextosCampos.calle,
                        sugerencia: 'Calle',
                        campo: CampoDireccion(
                          estado.calle,
                          estado.calleCambiada ? FuenteCampo.editado : FuenteCampo.vacio,
                        ),
                        controlador: _calle,
                        alCambiar: _notificador.editarCalle,
                        limite: 120,
                        accion: TextInputAction.next,
                        bloqueado: estado.guardando,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CampoDireccionUbicacion(
                        etiqueta: TextosCampos.numero,
                        sugerencia: 'Nº',
                        campo: CampoDireccion(
                          estado.numero,
                          estado.numeroCambiado ? FuenteCampo.editado : FuenteCampo.vacio,
                        ),
                        controlador: _numero,
                        alCambiar: _notificador.editarNumero,
                        limite: 20,
                        accion: TextInputAction.done,
                        bloqueado: estado.guardando,
                      ),
                    ),
                  ],
                ),
                if (mostrarFalla) ...[
                  const SizedBox(height: 14),
                  AvisoAlta(
                    key: _claveFalla,
                    color: ColoresAlta.rojo,
                    glyph: '!',
                    texto: mensajeFallaEdicion(falla),
                    // La ubicación cambió por debajo: con este borrador no hay nada que reintentar.
                    acciones: estado.desactualizada
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: EnlaceAlta(
                              texto: TextosModificar.abrirDeNuevo,
                              alPresionar: () => unawaited(_notificador.abrirDeNuevo()),
                            ),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: estado.puedeGuardar ? widget.alGuardar : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: ColoresAlta.grisFondo,
            disabledForegroundColor: ColoresAlta.gris,
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(
            estado.guardando ? TextosModificar.guardando : TextosModificar.guardarCambios,
            textAlign: TextAlign.center,
          ),
        ),
        if (widget.alDarDeBaja != null && !widget.tecladoAbierto)
          Center(
            child: TextButton(
              onPressed: estado.guardando ? null : widget.alDarDeBaja,
              style: TextButton.styleFrom(
                foregroundColor: ColoresAlta.rojo,
                minimumSize: const Size(48, 48),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextosModificar.darDeBaja),
            ),
          ),
      ],
    );
  }
}

/// «Av. Italia 1234» y, abajo, «Casa · 2 espacios · creada el 12/08»: la ubicación como está guardada.
class _Encabezado extends ConsumerWidget {
  const _Encabezado({required this.original, required this.espacios});

  final Ubicacion original;
  final int? espacios;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.watch(relojAltaUbicacionProvider)();
    final resumen = [
      FormatoUbicaciones.tipo(original.tipo),
      if (espacios != null) TextosModificar.espacios(espacios!),
      TextosModificar.creada(original.auditoria.createdAt, ahora),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            FormatoUbicaciones.direccion(original),
            style: const TextStyle(
              fontFamily: 'SourceSerif4',
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          resumen,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: ColoresAlta.gris, fontSize: 13),
        ),
      ],
    );
  }
}

/// La hoja de «Mover el punto» (artboard 07·02): la posición nueva, lo que el mapa dice de ese
/// punto, «Guardar posición» y «Cancelar».
///
/// «Guardar posición» pasa el punto al borrador de la edición: lo que se escribe en el teléfono es lo
/// de «Guardar cambios».
class HojaMoverPunto extends ConsumerWidget {
  const HojaMoverPunto({super.key, required this.parametros});

  final ParametrosModificar parametros;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proveedor = modificarUbicacionProvider(parametros);
    final estado = ref.watch(proveedor);
    final notificador = ref.read(proveedor.notifier);
    final punto = estado.puntoMover;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // «Guardar posición» y «Cancelar» quedan fijos al pie; se desplaza lo de arriba.
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AvisoMapaConectado(ambito: estado.ambitoMapa),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        TextosModificar.nuevaPosicion,
                        style: TextStyle(
                          fontFamily: 'SourceSerif4',
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (punto != null)
                      Text(
                        FormatoUbicaciones.coordenadas(punto),
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 12,
                          color: ColoresAlta.tinta,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _EstadoDireccion(
                  estado: estado,
                  alUsarCalle: notificador.usarCalleDelMapa,
                  alUsarNumero: notificador.usarNumeroDelMapa,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 14,
              child: FilledButton(
                onPressed: notificador.guardarPosicion,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text(TextosModificar.guardarPosicion, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 10,
              child: OutlinedButton(
                onPressed: notificador.cancelarMoverPunto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ColoresAlta.tinta,
                  side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text(TextosModificar.cancelar, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Los campos de la dirección que el mapa ve distinto de lo que tiene el borrador.
List<({bool esCalle, String valor})> _diferencias(ModificarUbicacionState e) {
  String norm(String s) => s.trim().toLowerCase();
  final p = e.propuesta;
  if (p == null) return const [];
  final r = <({bool esCalle, String valor})>[];
  final calle = p.calle?.trim() ?? '';
  final numero = p.numero?.trim() ?? '';
  if (calle.isNotEmpty && norm(calle) != norm(e.calle)) r.add((esCalle: true, valor: calle));
  if (numero.isNotEmpty && norm(numero) != norm(e.numero)) {
    r.add((esCalle: false, valor: numero));
  }
  return r;
}

/// «La dirección no cambia. El punto está en Av. Italia 1250.» con «Usar 1250»: mover el punto no
/// pisa la dirección cargada, solo ofrece la que el mapa conoce.
class _EstadoDireccion extends StatelessWidget {
  const _EstadoDireccion({
    required this.estado,
    required this.alUsarCalle,
    required this.alUsarNumero,
  });

  final ModificarUbicacionState estado;
  final VoidCallback alUsarCalle;
  final VoidCallback alUsarNumero;

  @override
  Widget build(BuildContext context) {
    final diferencias = _diferencias(estado);
    final p = estado.propuesta;
    final estilo = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.4, color: ColoresAlta.tinta);
    final partes = <InlineSpan>[];
    if (p != null && diferencias.isNotEmpty) {
      final calle = p.calle?.trim() ?? '';
      final numero = p.numero?.trim() ?? '';
      final calleDifiere = diferencias.any((d) => d.esCalle);
      final numeroDifiere = diferencias.any((d) => !d.esCalle);
      const negrita = TextStyle(fontWeight: FontWeight.w700);
      partes
        ..add(const TextSpan(text: ' El punto está en '))
        ..addAll([
          if (calle.isNotEmpty) TextSpan(text: calle, style: calleDifiere ? negrita : null),
          if (calle.isNotEmpty && numero.isNotEmpty) const TextSpan(text: ' '),
          if (numero.isNotEmpty) TextSpan(text: numero, style: numeroDifiere ? negrita : null),
        ])
        ..add(const TextSpan(text: '.'));
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F1EA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: TextosModificar.direccionNoCambia),
                    ...partes,
                  ],
                ),
                style: estilo,
              ),
            ),
            for (final d in diferencias)
              EnlaceAlta(
                texto: TextosAlta.usar(d.valor),
                alPresionar: d.esCalle ? alUsarCalle : alUsarNumero,
              ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se ve en lugar de la hoja mientras la ubicación se lee, no está o no se pudo leer.
class EstadoCargaModificar extends StatelessWidget {
  const EstadoCargaModificar({
    super.key,
    required this.estado,
    required this.alReintentar,
    required this.alVolver,
  });

  final ModificarUbicacionState estado;
  final VoidCallback alReintentar;
  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget cuerpo;
    switch (estado.carga) {
      case CargaEdicion.cargando:
      case CargaEdicion.lista:
        cuerpo = Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(TextosModificar.cargando, style: theme.textTheme.bodyMedium),
            ],
          ),
        );
      case CargaEdicion.noExiste:
        cuerpo = _Mensaje(
          texto: const FailureUbicacionInexistente().mensaje,
          boton: TextosModificar.volver,
          alPresionar: alVolver,
        );
      case CargaEdicion.noSePudoLeer:
        final falla = estado.fallaCarga;
        cuerpo = _Mensaje(
          texto: falla == null || falla is FailureInesperado
              ? TextosModificar.noPudimosAbrir
              : mensajePara(falla, accion: 'abrir esta ubicación.'),
          boton: TextosModificar.reintentar,
          alPresionar: alReintentar,
        );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: cuerpo,
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, required this.boton, required this.alPresionar});

  final String texto;
  final String boton;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvisoAlta(color: ColoresAlta.gris, glyph: '!', texto: texto),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: alPresionar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(boton, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
