import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/presentation/providers/estado_cuenta_providers.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/resultado_baja_espacio.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/agrupador_espacios.dart';
import '../../domain/usecases/dar_de_baja_espacio_use_case.dart';
import '../../domain/usecases/restaurar_espacio_use_case.dart';
import '../formato_espacios.dart';
import '../formato_ubicaciones.dart';
import '../pages/modificar_ubicacion_page.dart';
import '../providers/espacios_providers.dart';
import 'aviso_con_deshacer.dart';
import 'hoja_depto.dart';
import 'hoja_reactivar.dart' show TextosReactivar;
import 'piezas_alta.dart';
import 'piezas_espacios_baja.dart';
import 'piezas_lista_ubicaciones.dart';

/// Las claves de la hoja de una ubicación (vista 11·01).
abstract final class ClavesHojaUbicacion {
  static const hoja = Key('ubicacion_hoja');
  static const cerrar = Key('ubicacion_hoja_cerrar');
  static const agregarDepto = Key('ubicacion_hoja_agregar_depto');
  static const editar = Key('ubicacion_hoja_editar');
  static const cargando = Key('ubicacion_hoja_cargando');
  static const vacio = Key('ubicacion_hoja_vacio');
  static const error = Key('ubicacion_hoja_error');
  static const reintentar = Key('ubicacion_hoja_reintentar');
  static const cantidad = Key('ubicacion_hoja_cantidad');
  static const aviso = Key('ubicacion_hoja_aviso');

  /// La fila del espacio [id].
  static Key fila(String id) => Key('ubicacion_hoja_fila_$id');

  /// El rótulo del grupo de un piso (`null`: «Sin piso»).
  static Key grupo(String? piso) => Key('ubicacion_hoja_grupo_${piso ?? 'sin_piso'}');
}

/// Cómo se abre «Editar edificio» (la vista 07). Por defecto abre `ModificarUbicacionPage`; un test lo
/// reemplaza.
typedef AbridorEdicionUbicacion =
    Future<SalidaModificarUbicacion?> Function(
      BuildContext context, {
      required String colportorId,
      required String ubicacionId,
    });

final abridorEdicionUbicacionProvider = Provider<AbridorEdicionUbicacion>(
  (ref) => ModificarUbicacionPage.abrir,
);

/// Abre la hoja de la ubicación [ubicacionId] (vista 11·01): su dirección, sus deptos agrupados por
/// piso, «+ Departamento» y «Editar …». Se abre desde «›» de la lista y del inicio. [distanciaMetros] es la distancia desde donde está el colportor, si se sabe (el
/// rótulo «EDIFICIO · A 25 M»).
///
/// Devuelve lo que pasó en la edición de la ubicación ([SalidaModificarUbicacion]) para que quien la
/// abrió lo aplique (seleccionarla en el mapa, dejar de mostrarla si se dio de baja…), o `null` si el
/// colportor solo la cerró.
Future<SalidaModificarUbicacion?> mostrarHojaUbicacion(
  BuildContext context, {
  required String colportorId,
  required String ubicacionId,
  double? distanciaMetros,
}) => showModalBottomSheet<SalidaModificarUbicacion>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black26,
  builder: (_) => HojaUbicacion(
    colportorId: colportorId,
    ubicacionId: ubicacionId,
    distanciaMetros: distanciaMetros,
  ),
);

/// La hoja de una ubicación con sus espacios (vista 11·01, HU-UBI-007). Arranca a la mitad de la
/// pantalla (a casi toda con el texto grande o el lector de pantalla) y se agranda arrastrándola.
///
/// - Sin clientes (decisión de Cristian del 06/10): ni «+ Agregar cliente», ni «Registrar visita», ni
///   el atajo de la casa al alta de una persona; vuelven con #140 (S7) y #151 (S8).
///
/// Para volver a implementar lo diferido (documentado a pedido de Cristian, 06/10):
/// - Ficha del depto (artboard «11 · 04 Departamento con clientes») y «+ Agregar cliente»: hoy tocar una
///   fila abre `HojaDepto` (edición, [_editarDepto]). Con #140 la fila abre la ficha (clientes del
///   espacio, `personasDelEspacioProvider`, y el alta de persona de `AltaPersonaPage`), y la edición y la
///   baja pasan a un botón de esa ficha. «Ver depto N ›» del repetido (11·03) también va a la ficha.
/// - Atajo de la casa al alta de una persona: en [_contenido], rama `esCasa`, hoy solo el encabezado y
///   «Editar casa».
/// - «Registrar visita» y «Agendar» (#151): botones de la hoja de la casa (vista 39), no de esta.
/// - Una casa no tiene deptos: solo el encabezado y «Editar casa».
/// - Tocar un depto abre su edición (11·02 con los datos cargados), donde también se da de baja.
class HojaUbicacion extends ConsumerStatefulWidget {
  const HojaUbicacion({
    super.key,
    required this.colportorId,
    required this.ubicacionId,
    this.distanciaMetros,
  });

  final String colportorId;
  final String ubicacionId;
  final double? distanciaMetros;

  @override
  ConsumerState<HojaUbicacion> createState() => _HojaUbicacionState();
}

class _HojaUbicacionState extends ConsumerState<HojaUbicacion> {
  /// Evita abrir dos veces la hoja de un depto o la edición con dos toques seguidos.
  var _abriendo = false;

  /// El depto que «Ver depto 102 ›» dejó señalado.
  String? _resaltado;

  /// El aviso que se ve DENTRO de la hoja (el freno de la cuenta restringida, la edición que no se
  /// pudo abrir). No es un `SnackBar`: la hoja es un modal y se dibuja encima del borde de abajo donde
  /// se apoya, así que la persona no vería ni oiría nada.
  String? _aviso;
  final _claveAviso = GlobalKey();

  /// Deja el aviso a la vista: con el texto grande la cabecera de la hoja ocupa casi todo el alto y el
  /// aviso, que va debajo de los botones, quedaría fuera de lo que se ve.
  void _avisar(String texto) {
    setState(() => _aviso = texto);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _claveAviso.currentContext;
      if (mounted && contexto != null) {
        unawaited(Scrollable.ensureVisible(contexto, duration: Duration.zero));
      }
    });
  }

  /// Los deptos dados de baja cuya reactivación está en curso: su «Reactivar» dice «Reactivando…» y no
  /// se vuelve a tocar (un doble toque no reactiva dos veces).
  final _reactivando = <String>{};

  /// «Dados de baja» desplegado o plegado (plegado al abrir la hoja).
  var _bajasAbiertas = false;

  /// El aviso con «Deshacer» de la última reactivación, o lo que pasó al deshacerla. Va DENTRO de la
  /// hoja por lo mismo que [_aviso]: un `SnackBar` lo taparía la hoja modal.
  _AvisoReactivado? _reactivado;
  var _serieAviso = 0;
  Timer? _plazo;

  final _claves = <String, GlobalKey>{};

  /// El controlador de la lista que da la hoja arrastrable (cambia en cada dibujo).
  ScrollController? _controlador;

  /// Lo que se dibujó en la lista la última vez (grupos y deptos, en orden): para estimar dónde cae una
  /// fila que todavía no se construyó.
  List<Object> _plana = const [];

  @override
  void dispose() {
    _plazo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ubicacion = ref.watch(ubicacionDeLaHojaProvider(widget.ubicacionId));
    final grande =
        MediaQuery.textScalerOf(context).scale(14) > 18.2 ||
        MediaQuery.accessibleNavigationOf(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: grande ? 0.92 : 0.5,
      minChildSize: grande ? 0.6 : 0.3,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, controlador) {
        _controlador = controlador;
        return Material(
          key: ClavesHojaUbicacion.hoja,
          color: Colors.white,
          elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ubicacion.when(
                loading: () => _Cuerpo(
                  controlador: controlador,
                  alCerrar: _cerrar,
                  hijos: const [
                    _Mensaje(clave: ClavesHojaUbicacion.cargando, texto: TextosEspacios.cargando),
                  ],
                ),
                error: (_, _) => _Cuerpo(
                  controlador: controlador,
                  alCerrar: _cerrar,
                  hijos: [
                    _ErrorLectura(
                      texto: TextosEspacios.errorUbicacion,
                      alReintentar: () =>
                          ref.invalidate(ubicacionDeLaHojaProvider(widget.ubicacionId)),
                    ),
                  ],
                ),
                data: (u) => u == null
                    ? _Cuerpo(
                        controlador: controlador,
                        alCerrar: _cerrar,
                        hijos: const [_Mensaje(texto: TextosEspacios.errorUbicacion)],
                      )
                    : _contenido(context, u, controlador),
              ),
              if (_reactivado case final aviso?)
                Positioned(left: 12, right: 12, bottom: 12, child: _tarjetaReactivado(aviso)),
            ],
          ),
        );
      },
    );
  }

  void _cerrar() => Navigator.of(context).pop();

  Widget _contenido(BuildContext context, Ubicacion u, ScrollController controlador) {
    final esCasa = u.tipo == TipoUbicacion.casa;
    final espacios = esCasa ? null : ref.watch(espaciosDeUbicacionProvider(u.id));
    final bajas = esCasa ? null : ref.watch(espaciosDadosDeBajaProvider(u.id));
    final distancia = widget.distanciaMetros;
    final rotulo = [
      FormatoUbicaciones.tipo(u.tipo),
      if (distancia != null && distancia.isFinite && distancia >= 0)
        'a ${FormatoUbicaciones.distancia(distancia)}',
    ].join(' · ').toUpperCase();

    final total = espacios?.asData?.value.length;
    final hijos = <Widget>[
      _Encabezado(
        rotulo: rotulo,
        titulo: FormatoUbicaciones.direccion(u),
        cantidad: total == null ? null : TextosEspacios.cantidad(total),
        alCerrar: _cerrar,
      ),
      if (_aviso case final aviso?)
        Padding(
          key: _claveAviso,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: AvisoAlta(
            key: ClavesHojaUbicacion.aviso,
            color: ColoresAlta.rojo,
            glyph: '!',
            texto: aviso,
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (!esCasa)
              FilledButton(
                key: ClavesHojaUbicacion.agregarDepto,
                onPressed: _abriendo ? null : () => unawaited(_agregar(u)),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text(TextosEspacios.masDepartamento),
              ),
            OutlinedButton(
              key: ClavesHojaUbicacion.editar,
              onPressed: _abriendo ? null : () => unawaited(_editar(u)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: ColoresAlta.azul,
                side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
              ),
              child: Text(TextosEspacios.editarUbicacion(u.tipo)),
            ),
          ],
        ),
      ),
      const Divider(height: 1, color: ColoresLista.grisBorde),
    ];

    if (esCasa) {
      return _CuerpoSlivers(controlador: controlador, cabecera: hijos, lista: const []);
    }
    return espacios!.when(
      loading: () => _CuerpoSlivers(
        controlador: controlador,
        cabecera: [
          ...hijos,
          const _Mensaje(clave: ClavesHojaUbicacion.cargando, texto: TextosEspacios.cargando),
        ],
        lista: const [],
      ),
      error: (_, _) => _CuerpoSlivers(
        controlador: controlador,
        cabecera: [
          ...hijos,
          _ErrorLectura(
            texto: TextosEspacios.errorLectura,
            alReintentar: () => ref.invalidate(espaciosDeUbicacionProvider(u.id)),
          ),
        ],
        lista: const [],
      ),
      data: (lista) {
        // «Dados de baja» va al pie de la lista, plegado, y solo si hay alguno.
        final pie = _pieDeBajas(bajas);
        final holgura = _holguraAbajo(context);
        if (lista.isEmpty) {
          return _CuerpoSlivers(
            controlador: controlador,
            cabecera: [...hijos, const _VacioEspacios()],
            lista: pie,
            constructor: (contexto, fila) => _construirFila(u, fila),
            holgura: holgura,
          );
        }
        final grupos = AgrupadorEspacios.porPiso(lista);
        final filas = <Object>[
          for (final g in grupos) ...[g, ...g.espacios],
        ];
        _plana = filas;
        return _CuerpoSlivers(
          controlador: controlador,
          cabecera: hijos,
          lista: [...filas, ...pie],
          constructor: (contexto, fila) => _construirFila(u, fila),
          holgura: holgura,
        );
      },
    );
  }

  /// Una fila de la lista: el rótulo de un piso, un depto, o lo de «Dados de baja».
  Widget _construirFila(Ubicacion u, Object fila) => switch (fila) {
    GrupoDePiso() => _CabeceraGrupo(grupo: fila),
    Espacio() => _FilaDepto(
      key: _claveFila(fila.id),
      espacio: fila,
      resaltado: fila.id == _resaltado,
      alTocar: _abriendo ? null : () => unawaited(_editarDepto(u, fila)),
    ),
    _CabeceraBajas(:final cantidad, :final abierta) => CabeceraDadosDeBaja(
      cantidad: cantidad,
      abierta: abierta,
      alAlternar: () => setState(() => _bajasAbiertas = !_bajasAbiertas),
    ),
    _FilaBaja(:final espacio) => FilaDeptoDeBaja(
      espacio: espacio,
      reactivando: _reactivando.contains(espacio.id),
      alReactivar: () => unawaited(_reactivar(u, espacio)),
    ),
    _ErrorBajas() => ErrorDadosDeBaja(
      alReintentar: () => ref.invalidate(espaciosDadosDeBajaProvider(u.id)),
    ),
    _ => const SizedBox.shrink(),
  };

  /// Las filas de «Dados de baja»: la cabecera con la cuenta y, desplegada, un depto por fila. Mientras
  /// carga no se muestra nada; si la lectura falla (y no hay una lista vieja que mostrar), el aviso con
  /// «Reintentar».
  List<Object> _pieDeBajas(AsyncValue<List<Espacio>>? bajas) {
    if (bajas == null) return const [];
    final lista = bajas.value;
    if (lista == null) return bajas.hasError ? const [_ErrorBajas()] : const [];
    if (lista.isEmpty) return const [];
    return [
      _CabeceraBajas(cantidad: lista.length, abierta: _bajasAbiertas),
      if (_bajasAbiertas)
        for (final espacio in lista) _FilaBaja(espacio),
    ];
  }

  /// El espacio libre al final de la lista: con el aviso de «Deshacer» a la vista, lo que alcanza para
  /// que la última fila se pueda subir por encima de él.
  double _holguraAbajo(BuildContext context) {
    if (_reactivado == null) return 24;
    final grande = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    return grande ? 260 : 120;
  }

  GlobalKey _claveFila(String id) => _claves.putIfAbsent(id, GlobalKey.new);

  // ---------------------------------------------------------------- acciones

  /// Frena empezar algo nuevo si la cuenta se restringió con la hoja abierta (#383): el aviso se ve en
  /// la hoja misma. Lo ya abierto se termina y se guarda sin pasar por acá.
  bool _frena() {
    final estado = ref.read(estadoCuentaProvider).value;
    if (estado == null || estado.accedeAModulosDeCampo) return false;
    _avisar(TextosModuloBloqueado.para(estado));
    return true;
  }

  Future<void> _agregar(Ubicacion u) async {
    if (_abriendo) return;
    if (_frena()) return;
    setState(() {
      _aviso = null;
      _abriendo = true;
    });
    try {
      final salida = await mostrarHojaDepto(context, ubicacion: u, colportorId: widget.colportorId);
      _aplicar(salida);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  Future<void> _editarDepto(Ubicacion u, Espacio e) async {
    if (_abriendo) return;
    if (_frena()) return;
    setState(() {
      _aviso = null;
      _abriendo = true;
    });
    try {
      final salida = await mostrarHojaDepto(
        context,
        ubicacion: u,
        colportorId: widget.colportorId,
        espacio: e,
      );
      _aplicar(salida);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  void _aplicar(SalidaHojaDepto? salida) {
    if (!mounted) return;
    switch (salida) {
      case VerDeptoElegido(:final espacioId):
        setState(() => _resaltado = espacioId);
        _mostrarFila(espacioId);
      case DeptoDadoDeBaja(:final espacio):
        setState(() => _resaltado = null);
        ref.invalidate(espaciosDadosDeBajaProvider(widget.ubicacionId));
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            '${TextosEspacios.depto(espacio)} dado de baja.',
            Directionality.of(context),
          ),
        );
      case DeptoAgregado() || DeptoEditado() || null:
        if (_resaltado != null) setState(() => _resaltado = null);
    }
  }

  /// Deja a la vista la fila de [id]. Las filas son perezosas: si todavía no se dibujó, la lista se
  /// acerca por una estimación y se vuelve a intentar.
  void _mostrarFila(String id, {int intento = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contexto = _claves[id]?.currentContext;
      if (contexto != null) {
        unawaited(Scrollable.ensureVisible(contexto, alignment: 0.3));
        return;
      }
      if (intento >= 6) return;
      final controlador = _controlador;
      if (controlador != null && controlador.hasClients) {
        final posicion = controlador.position;
        // Primero la estimación de dónde cae la fila; si todavía no se construyó, se sigue de a media
        // pantalla.
        final destino = intento == 0
            ? _alturaHasta(id)
            : posicion.pixels + posicion.viewportDimension / 2;
        posicion.jumpTo(destino.clamp(0, posicion.maxScrollExtent));
      }
      _mostrarFila(id, intento: intento + 1);
    });
  }

  /// Lo que miden las filas que van antes de la de [id] (un grupo ~34 dp y un depto ~56 dp con el texto
  /// normal).
  double _alturaHasta(String id) {
    var y = 0.0;
    for (final fila in _plana) {
      if (fila is Espacio && fila.id == id) return y;
      y += fila is GrupoDePiso ? 34 : 56;
    }
    return 0;
  }

  // ---------------------------------------------------------------- reactivar

  void _refrescarListas() {
    ref.invalidate(espaciosDeUbicacionProvider(widget.ubicacionId));
    ref.invalidate(espaciosDadosDeBajaProvider(widget.ubicacionId));
  }

  /// «Reactivar» un depto dado de baja y, ya reactivado, el aviso con «Deshacer» de 8 s (la 09·04 de la
  /// casa, dicha para un depto). El depto vuelve a la lista con todo lo suyo: personas, visitas y ventas
  /// no se tocaron con la baja. Un depto a la vez por fila: mientras se reactiva, su botón queda apagado.
  Future<void> _reactivar(Ubicacion u, Espacio e) async {
    if (_reactivando.contains(e.id)) return;
    if (_frena()) return;
    final restaurar = ref.read(restaurarEspacioUseCaseProvider);
    setState(() {
      _aviso = null;
      _reactivando.add(e.id);
    });
    Failure? falla;
    Espacio? reactivado;
    try {
      final resultado = await restaurar(RestaurarEspacioParams(id: e.id));
      falla = resultado.fold<Failure?>((f) => f, (_) => null);
      reactivado = resultado.fold<Espacio?>((_) => null, (r) => r);
    } on Object catch (causa) {
      falla = FailureInesperado(causa: causa);
    }
    if (!mounted) return;
    setState(() => _reactivando.remove(e.id));
    _refrescarListas();
    if (reactivado == null) {
      _avisar(_mensajeReactivar(falla, e, u.tipo));
      return;
    }
    _mostrarReactivado(
      _AvisoReactivado(
        serie: ++_serieAviso,
        texto: TextosEspacios.reactivado(reactivado, u.tipo),
        espacio: reactivado,
      ),
    );
  }

  String _mensajeReactivar(Failure? falla, Espacio e, TipoUbicacion tipo) => switch (falla) {
    FailureValidacion(:final campos) when campos.containsKey('numeroDepto') =>
      TextosEspacios.reactivarRepetido(e, tipo),
    FailureValidacion(:final campos) when campos.containsKey('ubicacionId') =>
      TextosEspacios.ubicacionDeBaja,
    _ => TextosEspacios.noPudimosReactivar,
  };

  /// Pone [aviso] en lugar del anterior (cada «Deshacer» es de su depto) y arranca su plazo de 8 s. Con
  /// un lector de pantalla no hay plazo (WCAG 2.2.1): el aviso queda hasta que se cierre.
  void _mostrarReactivado(_AvisoReactivado aviso) {
    _plazo?.cancel();
    setState(() => _reactivado = aviso);
    if (MediaQuery.accessibleNavigationOf(context)) return;
    final serie = aviso.serie;
    _plazo = Timer(TextosReactivar.duracionDeshacer, () {
      final actual = _reactivado;
      // Un aviso más nuevo, o uno que está deshaciendo, no se cierra por el plazo del anterior.
      if (!mounted || actual == null || actual.serie != serie || actual.ocupado) return;
      setState(() => _reactivado = null);
    });
  }

  /// «Deshacer»: vuelve a dar de baja el depto. Ya estuvo de baja, así que no se vuelve a preguntar por
  /// sus personas. Si no se puede, lo dice y la baja se hace desde la edición del depto.
  Future<void> _deshacer(_AvisoReactivado aviso) async {
    final espacio = aviso.espacio;
    final actual = _reactivado;
    if (espacio == null || actual == null || actual.ocupado || actual.serie != aviso.serie) return;
    final darDeBaja = ref.read(darDeBajaEspacioUseCaseProvider);
    _plazo?.cancel();
    setState(() => _reactivado = aviso.deshaciendo());
    var deshecho = false;
    try {
      final resultado = await darDeBaja(
        DarDeBajaEspacioParams(id: espacio.id, confirmaConPersonas: true),
      );
      deshecho = resultado.fold((_) => false, (r) => r is BajaRealizada);
    } on Object {
      // Cualquier falla se dice igual: no se pudo deshacer.
      deshecho = false;
    }
    if (!mounted) return;
    _refrescarListas();
    final texto = deshecho ? TextosReactivar.deshecha : TextosEspacios.noPudimosDeshacer;
    if (_reactivado?.serie == aviso.serie) {
      _mostrarReactivado(_AvisoReactivado(serie: ++_serieAviso, texto: texto));
    } else if (!deshecho) {
      // Mientras tanto salió otro aviso: el que falló no se pierde, sale arriba.
      _avisar(texto);
    }
  }

  Widget _tarjetaReactivado(_AvisoReactivado aviso) {
    final sinPlazo = MediaQuery.accessibleNavigationOf(context);
    return AvisoDeshacerEnHoja(
      texto: aviso.texto,
      etiquetaDeshacer: aviso.espacio == null ? null : TextosReactivar.deshacer,
      alDeshacer: aviso.ocupado ? null : () => unawaited(_deshacer(aviso)),
      alCerrar: sinPlazo && !aviso.ocupado ? () => setState(() => _reactivado = null) : null,
      etiquetaCerrar: TextosEspacios.cerrarAviso,
    );
  }

  Future<void> _editar(Ubicacion u) async {
    if (_abriendo) return;
    if (_frena()) return;
    setState(() {
      _aviso = null;
      _abriendo = true;
    });
    SalidaModificarUbicacion? salida;
    try {
      salida = await ref.read(abridorEdicionUbicacionProvider)(
        context,
        colportorId: widget.colportorId,
        ubicacionId: u.id,
      );
    } on Object {
      if (mounted) _avisar(TextosEspacios.noPudimosAbrirEdicion);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
    if (!mounted) return;
    if (salida != null) {
      // Lo que pasó con la ubicación (editada, baja, otra elegida) lo aplica el mapa: la hoja se cierra.
      Navigator.of(context).pop(salida);
      return;
    }
    // Se cerró sin guardar: la dirección pudo no cambiar, pero se vuelve a leer por si acaso.
    ref.invalidate(ubicacionDeLaHojaProvider(u.id));
  }
}

/// El aviso con «Deshacer» de una reactivación, o (sin [espacio]) lo que pasó al deshacerla.
final class _AvisoReactivado {
  const _AvisoReactivado({
    required this.serie,
    required this.texto,
    this.espacio,
    this.ocupado = false,
  });

  /// Distingue un aviso de otro: el plazo de uno no cierra al siguiente.
  final int serie;
  final String texto;

  /// El depto que se reactivó y que «Deshacer» vuelve a dar de baja; `null`: no hay nada que deshacer.
  final Espacio? espacio;

  /// «Deshacer» está en curso: el botón queda apagado y el plazo no cierra el aviso.
  final bool ocupado;

  _AvisoReactivado deshaciendo() =>
      _AvisoReactivado(serie: serie, texto: texto, espacio: espacio, ocupado: true);
}

/// Las filas del pie de la lista: la cabecera de «Dados de baja», un depto dado de baja y el error de
/// leerlos.
final class _CabeceraBajas {
  const _CabeceraBajas({required this.cantidad, required this.abierta});

  final int cantidad;
  final bool abierta;
}

final class _FilaBaja {
  const _FilaBaja(this.espacio);

  final Espacio espacio;
}

final class _ErrorBajas {
  const _ErrorBajas();
}

// -------------------------------------------------------------------- piezas

/// El armazón de la hoja cuando no hay nada que listar (cargando, error): el asa, el cierre y [hijos].
class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.controlador, required this.alCerrar, required this.hijos});

  final ScrollController controlador;
  final VoidCallback alCerrar;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => _CuerpoSlivers(
    controlador: controlador,
    cabecera: [
      _Encabezado(rotulo: '', titulo: '', cantidad: null, alCerrar: alCerrar, vacio: true),
      ...hijos,
    ],
    lista: const [],
  );
}

/// El cuerpo desplazable: la cabecera (asa, título, botones), y la lista perezosa de filas.
class _CuerpoSlivers extends StatelessWidget {
  const _CuerpoSlivers({
    required this.controlador,
    required this.cabecera,
    required this.lista,
    this.constructor,
    this.holgura = 24,
  });

  final ScrollController controlador;
  final List<Widget> cabecera;
  final List<Object> lista;
  final Widget Function(BuildContext, Object)? constructor;

  /// El espacio libre al final de la lista.
  final double holgura;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controlador,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      color: ColoresLista.chevron,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              ...cabecera,
            ],
          ),
        ),
        if (lista.isNotEmpty)
          SliverList.builder(
            itemCount: lista.length,
            itemBuilder: (contexto, i) => constructor!(contexto, lista[i]),
          ),
        SliverToBoxAdapter(child: SizedBox(height: holgura)),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.rotulo,
    required this.titulo,
    required this.cantidad,
    required this.alCerrar,
    this.vacio = false,
  });

  final String rotulo;
  final String titulo;
  final String? cantidad;
  final VoidCallback alCerrar;
  final bool vacio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: vacio
                ? const SizedBox(height: 48)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rotulo,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            letterSpacing: 1.4,
                            color: ColoresAlta.gris,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Semantics(
                          header: true,
                          child: Text(
                            titulo,
                            style: const TextStyle(
                              fontFamily: 'SourceSerif4',
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (cantidad != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              cantidad!,
                              key: ClavesHojaUbicacion.cantidad,
                              style: const TextStyle(fontSize: 13, color: ColoresLista.grisTexto),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          IconButton(
            key: ClavesHojaUbicacion.cerrar,
            tooltip: TextosEspacios.cerrar,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: alCerrar,
            icon: const ExcludeSemantics(child: Text('✕', style: TextStyle(fontSize: 18))),
          ),
        ],
      ),
    );
  }
}

class _CabeceraGrupo extends StatelessWidget {
  const _CabeceraGrupo({required this.grupo});

  final GrupoDePiso grupo;

  @override
  Widget build(BuildContext context) {
    final nombre = grupo.piso == null
        ? TextosEspacios.grupoSinPiso
        : TextosEspacios.piso(grupo.piso!);
    return Semantics(
      header: true,
      child: Container(
        key: ClavesHojaUbicacion.grupo(grupo.piso),
        width: double.infinity,
        color: ColoresLista.filaBaja,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                nombre,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: ColoresAlta.gris,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${grupo.espacios.length}',
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                color: ColoresAlta.gris,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaDepto extends StatelessWidget {
  const _FilaDepto({
    super.key,
    required this.espacio,
    required this.resaltado,
    required this.alTocar,
  });

  final Espacio espacio;
  final bool resaltado;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final sinNumero = espacio.sinNumero;
    return Semantics(
      button: true,
      label: TextosEspacios.filaSemantica(espacio),
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        color: resaltado ? ColoresLista.azulFondo : Colors.white,
        child: InkWell(
          key: ClavesHojaUbicacion.fila(espacio.id),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: ColoresLista.grisBorde)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      TextosEspacios.depto(espacio),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: sinNumero ? ColoresLista.grisTexto : ColoresLista.tinta,
                        fontStyle: sinNumero ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('›', style: TextStyle(fontSize: 22, color: ColoresLista.chevron)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, this.clave});

  final String texto;
  final Key? clave;

  @override
  Widget build(BuildContext context) => Padding(
    key: clave,
    padding: const EdgeInsets.all(24),
    child: Semantics(
      liveRegion: true,
      child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
    ),
  );
}

class _VacioEspacios extends StatelessWidget {
  const _VacioEspacios();

  @override
  Widget build(BuildContext context) => Padding(
    key: ClavesHojaUbicacion.vacio,
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
    child: Column(
      children: [
        Semantics(
          header: true,
          child: const Text(
            TextosEspacios.vacioTitulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          TextosEspacios.vacioCuerpo,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: ColoresLista.grisTexto),
        ),
      ],
    ),
  );
}

class _ErrorLectura extends StatelessWidget {
  const _ErrorLectura({required this.texto, required this.alReintentar});

  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) => Padding(
    key: ClavesHojaUbicacion.error,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: texto),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ClavesHojaUbicacion.reintentar,
          onPressed: alReintentar,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text(TextosEspacios.reintentar),
        ),
      ],
    ),
  );
}
