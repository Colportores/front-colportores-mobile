import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/presentation/flujo_agendar_visita.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../mapa/domain/entities/persona_del_espacio.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../domain/entities/devolucion.dart';
import '../../domain/entities/venta_para_devolver.dart';
import '../../domain/services/reglas_de_devolucion.dart';
import '../../domain/usecases/registrar_devolucion_use_case.dart';
import '../formato_venta.dart';
import '../providers/devolucion_providers.dart';
import '../textos_devolucion.dart';
import '../widgets/piezas_devolucion.dart';
import '../widgets/piezas_venta.dart';

/// «Devolución de una venta» (vista 31, HU-VEN-004, artboards 31-01 a 31-10): la colportora registra
/// qué libros le devuelve el cliente, parcial o total, y qué hace con la plata si pagó de más. La venta
/// original no se borra ni se anula: queda con la devolución anotada. Se abre desde la venta en la ficha
/// de la persona, ya con la venta, la casa y la persona resueltas (contrato de navegación de la vista
/// 39); no las vuelve a pedir.
///
/// - **Elegir** (31-01 y 31-09): una fila por renglón de la venta con su «−  n  +». Sin nada elegido el
///   botón está apagado y dice por qué.
/// - **Seguir** (31-02, 31-03, 31-06 y 31-07): muestra cómo queda la venta. Si el cliente pagó de más hay
///   que decidir qué se hace con la diferencia: viene elegida «Lo retengo» (la salida que no devuelve
///   plata, decisión de Cristian, 23/10, «Debo cliente») y «Se lo devuelvo ahora» y «Se lo devuelvo
///   después» quedan a mano como opciones secundarias; si no, el saldo baja solo. Las filas siguen editables: vaciarlas vuelve a elegir.
/// - **Confirmar** (31-04): la hoja «¿Registrar la devolución?».
/// - **Registrada** (31-05): lo que quedó hecho y, si el dinero quedó pendiente, «Agendar la devolución
///   del dinero».
/// - **Error al guardar** (31-10): se conserva lo elegido y el botón pasa a «Reintentar». El id de la
///   devolución se genera una vez y se repite en los reintentos con los mismos datos: un doble toque o
///   un «Reintentar» no devuelven dos veces.
/// - **Pasaron 72 h** (31-08): solo el coordinador la registra.
/// - **Sin conexión**: no hay estado propio. Todo es local y sube después.
///
/// Además lee la venta (cargando, ya no está, error de lectura) y, si ya se devolvió por completo, lo
/// dice. Devuelve `true` si se registró una devolución, `false` si se cerró sin registrar.
class DevolucionPage extends ConsumerStatefulWidget {
  const DevolucionPage({
    super.key,
    required this.ventaId,
    required this.colportorId,
    required this.espacioId,
    this.personaId,
  });

  /// La venta que se devuelve.
  final String ventaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// La casa o el depto de la venta.
  final String espacioId;

  /// El cliente, o `null` si la venta quedó sin persona.
  final String? personaId;

  /// Abre la pantalla encima de la actual. `true` si se registró una devolución.
  static Future<bool> abrir(
    BuildContext context, {
    required String ventaId,
    required String colportorId,
    required String espacioId,
    String? personaId,
  }) async {
    final registrada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DevolucionPage(
          ventaId: ventaId,
          colportorId: colportorId,
          espacioId: espacioId,
          personaId: personaId,
        ),
      ),
    );
    return registrada ?? false;
  }

  @override
  ConsumerState<DevolucionPage> createState() => _DevolucionPageState();
}

enum _Lectura { cargando, lista, ausente, conError }

class _DevolucionPageState extends ConsumerState<DevolucionPage> {
  final _motivo = TextEditingController();
  final _scroll = ScrollController();

  var _lectura = _Lectura.cargando;
  VentaParaDevolver? _venta;

  /// Pasaron más de 72 h desde la venta (31-08).
  var _fueraDePlazo = false;

  /// Cuántas unidades de cada renglón se devuelven: `venta_item.id` → unidades.
  Map<String, int> _elegidas = {};

  /// Ya tocó «Seguir»: se ve cómo queda la venta (31-02 a 31-07).
  var _siguio = false;

  /// Lo que la colportora tocó para la plata de más; `null` mientras no toque ninguna (rige la salida que
  /// no devuelve plata: [_salida]).
  QueHacerConLaDiferencia? _queHacer;

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// La última falla al guardar (31-10); `null` si no hay.
  Failure? _falla;

  /// El registro se rechazó porque lo elegido ya no es válido (otra devolución se llevó el libro): la
  /// venta se vuelve a leer y este aviso dice qué hacer. `null` si no hay.
  FailureDevolucionInvalida? _invalida;

  /// La devolución registrada (31-05); `null` mientras se está cargando o eligiendo.
  DevolucionRegistrada? _registrada;

  /// Los nombres de lo que se devolvió, para el aviso de 31-05.
  List<String> _titulosDevueltos = const [];

  /// Hay una hoja o una pantalla abierta desde acá: no admite otra encima.
  var _navegando = false;

  /// La pantalla se está cerrando: un segundo toque no vuelve a hacer `pop`.
  var _cerrando = false;

  /// El aviso «¿Descartar lo que escribiste?» está abierto: otro atrás no abre uno segundo.
  var _preguntando = false;

  /// El último intento de guardar: con los mismos datos se repite el id de la devolución; con otros,
  /// es otra devolución.
  ({String datos, String id})? _intento;

  @override
  void initState() {
    super.initState();
    unawaited(_leerLaVenta());
  }

  @override
  void dispose() {
    _motivo.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime _ahora() => ref.read(relojDevolucionProvider)();

  // --- Leer la venta -----------------------------------------------------------------------

  Future<void> _leerLaVenta({bool mostrarCarga = true}) async {
    if (mostrarCarga) setState(() => _lectura = _Lectura.cargando);
    try {
      final leida = await ref.read(devolucionRepositoryProvider).ventaParaDevolver(widget.ventaId);
      if (!mounted) return;
      leida.fold(
        (_) => _alNoPoderLeer(mostrarCarga),
        (venta) => setState(() {
          _venta = venta;
          _lectura = venta == null ? _Lectura.ausente : _Lectura.lista;
          if (venta != null) {
            _fueraDePlazo = ReglasDeDevolucion.estaFueraDePlazo(venta.fecha, _ahora());
            // Lo que había elegido se ajusta a lo que queda por devolver ahora.
            _elegidas = ReglasDeDevolucion.ajustar(venta, _elegidas);
            if (_elegidas.isEmpty) _siguio = false;
          }
        }),
      );
    } on Object {
      if (mounted) _alNoPoderLeer(mostrarCarga);
    }
  }

  /// Sin poder leer la venta: si todavía no se había leído, el error de lectura con «Reintentar»; si
  /// ya se mostraba el formulario (se volvió a leer tras un rechazo), el aviso de «Reintentar».
  void _alNoPoderLeer(bool mostrarCarga) => setState(() {
    if (mostrarCarga || _venta == null) {
      _lectura = _Lectura.conError;
    } else {
      _falla = _generica;
    }
    _verElAviso();
  });

  // --- Lo que eligió -----------------------------------------------------------------------

  CuentaDeLaDevolucion _cuenta(VentaParaDevolver venta) =>
      ReglasDeDevolucion.cuenta(venta, _elegidas);

  void _cambiarCantidad(RenglonDeLaVenta renglon, int cantidad) {
    if (_enviando) return;
    final venta = _venta;
    // La plata de más que había que decidir, antes del cambio.
    final pagoDeMasAntes = venta == null ? 0 : _cuenta(venta).pagoDeMasCentavos;
    setState(() {
      final n = cantidad.clamp(0, renglon.disponibles);
      _elegidas = {..._elegidas, if (n > 0) renglon.ventaItemId: n};
      if (n == 0) _elegidas.remove(renglon.ventaItemId);
      // Si cambió el monto a decidir, la elección era para otro monto: vuelve a regir la salida que no
      // devuelve plata y, si quiere devolver, lo elige de nuevo para el monto nuevo.
      if (venta != null && _cuenta(venta).pagoDeMasCentavos != pagoDeMasAntes) _queHacer = null;
      if (_elegidas.isEmpty) {
        // Sin nada elegido se vuelve a la primera etapa; lo de la plata de más ya no corresponde.
        _siguio = false;
        _queHacer = null;
      }
      _falla = null;
      _invalida = null;
    });
  }

  bool _sePuedeSeguir() => !_enviando && _elegidas.values.any((n) => n > 0);

  /// Qué se hace con la plata de más (31-02 y 31-03): lo que tocó o, mientras no toque nada, «Lo
  /// retengo», la salida que no devuelve plata (decisión de Cristian, 23/10, «Debo cliente»: devolver
  /// es una opción a mano pero secundaria). `null` si no hay plata de más que decidir.
  QueHacerConLaDiferencia? _salida(CuentaDeLaDevolucion cuenta) =>
      cuenta.hayQueElegir ? (_queHacer ?? QueHacerConLaDiferencia.retener) : null;

  bool _sePuedeRegistrar() => !_enviando && _siguio && _sePuedeSeguir();

  void _seguir() {
    if (!_sePuedeSeguir()) return;
    setState(() => _siguio = true);
  }

  // --- Registrar ---------------------------------------------------------------------------

  /// Qué se muestra en la hoja de confirmar (31-04). En V1 no hay stock ni beca (decisión de Cristian,
  /// 23/10): solo lo que vuelve y cómo queda la plata.
  List<DatoDeDevolucion> _datosDeLaHoja(VentaParaDevolver venta) {
    final cuenta = _cuenta(venta);
    final salida = _salida(cuenta);
    final destino = ReglasDeDevolucion.destinoDeLaDiferencia(cuenta.pagoDeMasCentavos, salida);
    return [
      DatoDeDevolucion(TextosDevolucion.devuelve, TextosDevolucion.loQueVuelve(venta, _elegidas)),
      if (salida != null && destino != null)
        switch (salida) {
          QueHacerConLaDiferencia.devolverAhora => DatoDeDevolucion(
            TextosDevolucion.leDevolves,
            FormatoVenta.monto(cuenta.pagoDeMasCentavos),
            fuerte: true,
          ),
          QueHacerConLaDiferencia.retener => DatoDeDevolucion(
            TextosDevolucion.retenes,
            FormatoVenta.monto(cuenta.pagoDeMasCentavos),
            fuerte: true,
          ),
          QueHacerConLaDiferencia.devolverDespues => DatoDeDevolucion(
            TextosDevolucion.deboAlCliente,
            FormatoVenta.monto(cuenta.pagoDeMasCentavos),
            fuerte: true,
          ),
        }
      else
        DatoDeDevolucion(
          TextosDevolucion.saldoNuevo,
          FormatoVenta.monto(cuenta.saldoNuevoCentavos),
          fuerte: true,
        ),
    ];
  }

  /// 31-04: pregunta antes de registrar.
  Future<void> _pedirConfirmacion() async {
    final venta = _venta;
    if (venta == null || !_sePuedeRegistrar() || _navegando) return;
    _navegando = true;
    bool? confirmo;
    try {
      confirmo = await mostrarHojaConfirmarDevolucion(context, datos: _datosDeLaHoja(venta));
    } finally {
      _navegando = false;
    }
    if (confirmo != true || !mounted) return;
    await _registrar();
  }

  Future<void> _registrar() async {
    final venta = _venta;
    if (venta == null || !_sePuedeRegistrar()) return;
    setState(() {
      _enviando = true;
      _falla = null;
      _invalida = null;
    });
    try {
      final elegidas = {..._elegidas};
      final salida = _salida(_cuenta(venta));
      final motivo = _motivo.text;
      final datos = [
        for (final k in (elegidas.keys.toList()..sort())) '$k:${elegidas[k]}',
        salida?.name ?? '',
        motivo,
      ].join('|');
      final previo = _intento;
      final id = previo != null && previo.datos == datos
          ? previo.id
          : ref.read(generadorIdDevolucionProvider)();
      _intento = (datos: datos, id: id);
      final titulos = [
        for (final r in venta.renglones)
          if ((elegidas[r.ventaItemId] ?? 0) > 0) r.titulo,
      ];
      final resultado = await ref.read(registrarDevolucionUseCaseProvider)(
        RegistrarDevolucionParams(
          devolucionId: id,
          ventaId: venta.ventaId,
          colportorId: widget.colportorId,
          unidadesPorRenglon: elegidas,
          queHacer: salida,
          motivo: motivo,
        ),
      );
      if (!mounted) return;
      resultado.fold(_alFallar, (registrada) => _alRegistrar(registrada, titulos));
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailureDevolucionNoGuardada(causa: 'excepcion'));
        _verElAviso();
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _alRegistrar(DevolucionRegistrada registrada, List<String> titulos) {
    // La confirmación empieza arriba, no donde estaba el formulario.
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _registrada = registrada;
      _titulosDevueltos = titulos;
    });
  }

  /// El aviso de falla está arriba del formulario: con letra grande hay que subir para verlo. Se sube
  /// de una (sin animar): el aviso está fuera de la lista armada hasta que llega el principio, y el
  /// lector de pantalla solo lo anuncia cuando existe.
  void _verElAviso() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    _scroll.jumpTo(0);
  }

  void _alFallar(Failure falla) {
    switch (falla) {
      case FailureDevolucionFueraDePlazo():
        setState(() => _fueraDePlazo = true);
      case FailureDevolucionSinVenta():
        setState(() => _lectura = _Lectura.ausente);
      case FailureDevolucionInvalida():
        // Lo que quedaba por devolver cambió desde que se abrió: se lee de nuevo, las filas lo dicen y
        // el aviso de arriba explica qué hacer.
        setState(() => _invalida = falla);
        _verElAviso();
        unawaited(_leerLaVenta(mostrarCarga: false));
      default:
        setState(() => _falla = falla is FailureDevolucionNoGuardada ? falla : _generica);
        _verElAviso();
    }
  }

  static const _generica = FailureDevolucionNoGuardada(causa: 'otra_falla');

  // --- Salir -------------------------------------------------------------------------------

  void _cerrar({required bool registrada}) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(registrada);
  }

  /// Hay algo elegido o escrito que se perdería al salir, antes de registrar.
  bool get _hayLoEscrito =>
      _registrada == null &&
      (_elegidas.isNotEmpty || _motivo.text.trim().isNotEmpty || _queHacer != null);

  Future<void> _atras() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (_hayLoEscrito) {
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar(registrada: _registrada != null);
  }

  Future<void> _agendarElDinero() async {
    if (_navegando || _cerrando) return;
    _navegando = true;
    try {
      final agendada = await FlujoAgendarVisita.abrir(
        context,
        espacioId: widget.espacioId,
        espacioPersonaId: _vinculoId(),
        colportorId: widget.colportorId,
        tipo: TipoAgenda.cobranza,
      );
      if (agendada && mounted) _cerrar(registrada: true);
    } finally {
      _navegando = false;
    }
  }

  // --- Dibujo ------------------------------------------------------------------------------

  PersonaDelEspacio? _personaDelEspacio() {
    final personaId = widget.personaId;
    if (personaId == null) return null;
    final personas = ref.watch(personasDelEspacioProvider(widget.espacioId)).asData?.value;
    return personas?.where((p) => p.persona.id == personaId).firstOrNull;
  }

  /// El vínculo persona ↔ espacio del cliente, o `null` si no se sabe quién es.
  String? _vinculoId() {
    final personaId = widget.personaId;
    if (personaId == null) return null;
    final personas = ref.read(personasDelEspacioProvider(widget.espacioId)).asData?.value;
    return personas?.where((p) => p.persona.id == personaId).firstOrNull?.vinculo.id;
  }

  @override
  Widget build(BuildContext context) {
    final venta = _venta;
    final Widget cuerpo;
    if (_registrada case final registrada?) {
      cuerpo = _exito(registrada);
    } else {
      cuerpo = switch (_lectura) {
        _Lectura.cargando => _marco(
          cabecera: _cabecera(null),
          hijos: const [EsqueletoDeDevolucion()],
        ),
        _Lectura.ausente => _marco(
          cabecera: _cabecera(null),
          hijos: const [
            AvisoDeVenta(key: Key('devolucion_sin_venta'), texto: TextosDevolucion.sinLaVenta),
          ],
          cta: _botonVolver(),
        ),
        _Lectura.conError => _marco(
          cabecera: _cabecera(null),
          hijos: [
            AvisoDeVenta(
              key: const Key('devolucion_error_lectura'),
              texto: TextosDevolucion.errorDeLectura,
              textoAccion: TextosDevolucion.reintentar,
              alAccion: () => unawaited(_leerLaVenta()),
            ),
          ],
        ),
        _Lectura.lista when venta != null && _fueraDePlazo => _fueraDelPlazo(venta),
        _Lectura.lista when venta != null && venta.estaTodoDevuelto => _yaDevuelta(venta),
        _Lectura.lista when venta != null => _formulario(venta),
        _ => _marco(cabecera: _cabecera(null), hijos: const [EsqueletoDeDevolucion()]),
      };
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) unawaited(_atras());
      },
      child: cuerpo,
    );
  }

  /// «DEVOLUCIÓN · VENTA 0042» y el título de la etapa.
  Widget _cabecera(
    VentaParaDevolver? venta, {
    String titulo = TextosDevolucion.titulo,
    String? subtitulo,
    bool conSalida = true,
    bool soloVenta = false,
    bool cerrar = true,
  }) => CabeceraVenta(
    eyebrow: venta == null
        ? 'DEVOLUCIÓN'
        : soloVenta
        ? TextosDevolucion.eyebrowSolo(venta.numeroTalonario)
        : TextosDevolucion.eyebrow(venta.numeroTalonario),
    titulo: titulo,
    subtitulo: subtitulo,
    cerrar: cerrar,
    alVolver: conSalida && !_enviando ? () => unawaited(_atras()) : null,
  );

  Widget _botonVolver() => BotonDeVenta(
    key: const Key('devolucion_volver'),
    texto: TextosDevolucion.volver,
    alPresionar: () => _cerrar(registrada: false),
  );

  Widget _marco({required Widget cabecera, required List<Widget> hijos, Widget? cta}) {
    return Scaffold(
      key: const Key('devolucion_pagina'),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [cabecera, ...hijos],
              ),
            ),
            if (cta != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: cta),
          ],
        ),
      ),
    );
  }

  /// 31-08: pasaron más de 72 h; la registra el coordinador.
  Widget _fueraDelPlazo(VentaParaDevolver venta) => _marco(
    cabecera: _cabecera(
      venta,
      titulo: TextosDevolucion.tituloFueraDePlazo,
      soloVenta: true,
      cerrar: false,
    ),
    hijos: const [
      AvisoDeVenta(
        key: Key('devolucion_fuera_de_plazo'),
        error: false,
        texto: TextosDevolucion.fueraDePlazo,
      ),
    ],
    cta: _botonVolver(),
  );

  /// La venta ya volvió entera: no queda nada para devolver.
  Widget _yaDevuelta(VentaParaDevolver venta) => _marco(
    cabecera: _cabecera(venta, titulo: TextosDevolucion.tituloFueraDePlazo, soloVenta: true),
    hijos: const [
      AvisoDeVenta(
        key: Key('devolucion_ya_devuelta'),
        error: false,
        texto: TextosDevolucion.yaDevuelta,
      ),
    ],
    cta: _botonVolver(),
  );

  /// 31-01 a 31-04, 31-06, 31-07, 31-09 y 31-10: el formulario.
  Widget _formulario(VentaParaDevolver venta) {
    final cuenta = _cuenta(venta);
    final persona = _personaDelEspacio();
    final nombre = persona == null
        ? null
        : '${persona.persona.nombre} ${persona.persona.apellido}'.trim();
    final subtitulo = TextosDevolucion.pago(nombre, venta.yaPagoCentavos, venta.seQuedaConCentavos);
    final titulo = _siguio && !cuenta.estaVacia
        ? TextosDevolucion.tituloDeLaEleccion(venta, _elegidas, cuenta.esTotal)
        : TextosDevolucion.titulo;
    final puedeRegistrar = _sePuedeRegistrar();
    final puedeSeguir = _sePuedeSeguir();
    final Widget cta;
    if (_siguio) {
      cta = BotonDeVenta(
        texto: _falla != null ? TextosDevolucion.reintentar : TextosDevolucion.registrarDevolucion,
        textoOcupado: TextosDevolucion.registrando,
        ocupado: _enviando,
        alPresionar: puedeRegistrar
            ? () => unawaited(_falla != null ? _registrar() : _pedirConfirmacion())
            : null,
      );
    } else {
      cta = BotonDeVenta(
        texto: TextosDevolucion.seguir,
        nota: !_enviando && !puedeSeguir ? TextosDevolucion.elegiAlMenosUno : null,
        alPresionar: puedeSeguir ? _seguir : null,
      );
    }
    return _marco(
      cabecera: _cabecera(venta, titulo: titulo, subtitulo: subtitulo),
      hijos: [
        if (_falla != null) ...[
          const AvisoDeVenta(key: Key('devolucion_error'), texto: TextosDevolucion.errorAlGuardar),
          const SizedBox(height: 9),
        ],
        if (_invalida case final invalida?) ...[
          AvisoDeVenta(key: const Key('devolucion_invalida'), texto: invalida.mensaje),
          const SizedBox(height: 9),
        ],
        const RotuloDeSeccion(TextosDevolucion.enLaVenta),
        const SizedBox(height: 6),
        for (final r in venta.renglones) ...[
          FilaDeCantidad(
            key: Key('devolucion_fila_${r.ventaItemId}'),
            titulo: r.titulo,
            precio: TextosDevolucion.vendidos(
              r.cantidad,
              r.unidadesDevueltas,
              r.precioUnitarioCentavos,
            ),
            cantidad: _elegidas[r.ventaItemId] ?? 0,
            maximo: r.disponibles,
            alCambiar: _enviando ? (_) {} : (n) => _cambiarCantidad(r, n),
          ),
          const SizedBox(height: 8),
        ],
        if (!_siguio) ...[
          const SizedBox(height: 4),
          Text(
            TextosDevolucion.plazo(venta.fecha),
            key: const Key('devolucion_plazo'),
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: ColoresAgenda.gris),
          ),
        ] else if (!cuenta.estaVacia) ...[
          const SizedBox(height: 4),
          TarjetaDeDatos(
            key: const Key('devolucion_cuentas'),
            datos: [
              DatoDeDevolucion(
                TextosDevolucion.seQuedaCon,
                FormatoVenta.monto(cuenta.seQuedaConCentavos),
              ),
              if (cuenta.hayQueElegir) ...[
                DatoDeDevolucion(
                  TextosDevolucion.yaPago,
                  FormatoVenta.monto(cuenta.yaPagoCentavos),
                ),
                DatoDeDevolucion(
                  TextosDevolucion.pagoDeMas,
                  FormatoVenta.monto(cuenta.pagoDeMasCentavos),
                  fuerte: true,
                ),
              ] else if (cuenta.saldoNuevoCentavos > 0) ...[
                DatoDeDevolucion(
                  TextosDevolucion.yaPago,
                  FormatoVenta.monto(cuenta.yaPagoCentavos),
                ),
                DatoDeDevolucion(
                  TextosDevolucion.saldoNuevo,
                  FormatoVenta.monto(cuenta.saldoNuevoCentavos),
                  fuerte: true,
                ),
              ],
            ],
          ),
          if (cuenta.hayQueElegir) ...[
            const SizedBox(height: 12),
            OpcionesDeLaDiferencia(
              rotulo: TextosDevolucion.queHaces(cuenta.pagoDeMasCentavos),
              elegida: _salida(cuenta),
              alElegir: _enviando ? null : (o) => setState(() => _queHacer = o),
            ),
          ],
          const SizedBox(height: 4),
          CampoDeVenta(
            key: const Key('devolucion_motivo'),
            rotulo: TextosDevolucion.motivo,
            controlador: _motivo,
            alCambiar: (_) => setState(() => _falla = null),
            ayuda: TextosDevolucion.avisoMotivo,
            hint: TextosDevolucion.motivoHint,
            maxLargo: ReglasDeDevolucion.largoMaximoMotivo,
            lineas: 3,
            teclado: TextInputType.multiline,
            habilitado: !_enviando,
          ),
        ],
      ],
      cta: cta,
    );
  }

  /// 31-05: la devolución quedó registrada.
  Widget _exito(DevolucionRegistrada registrada) {
    final venta = _venta;
    final debo = registrada.deboAlClienteCentavos;
    return _marco(
      cabecera: CabeceraVenta(
        eyebrow: venta == null ? 'DEVOLUCIÓN' : TextosDevolucion.eyebrow(venta.numeroTalonario),
        titulo: TextosDevolucion.tituloRegistrada,
      ),
      hijos: [
        TarjetaDeDatos(
          key: const Key('devolucion_resumen'),
          datos: [
            DatoDeDevolucion(
              TextosDevolucion.totalDeLaVenta,
              FormatoVenta.monto(registrada.totalCentavos),
            ),
            DatoDeDevolucion(TextosDevolucion.saldo, FormatoVenta.monto(registrada.saldoCentavos)),
            if (debo > 0)
              DatoDeDevolucion(
                TextosDevolucion.deboAlCliente,
                FormatoVenta.monto(debo),
                fuerte: true,
                alerta: true,
              ),
          ],
        ),
        const SizedBox(height: 12),
        AvisoDeDevolucionHecha(
          texto: TextosDevolucion.registramos(_titulosDevueltos, todo: registrada.eraTotal),
        ),
      ],
      cta: debo > 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BotonDeVenta(
                  key: const Key('devolucion_agendar'),
                  texto: TextosDevolucion.agendarElDinero,
                  alPresionar: () => unawaited(_agendarElDinero()),
                ),
                TextButton(
                  key: const Key('devolucion_listo'),
                  onPressed: () => _cerrar(registrada: true),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text(
                    TextosDevolucion.listo,
                    style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
                  ),
                ),
              ],
            )
          : BotonDeVenta(
              key: const Key('devolucion_listo'),
              texto: TextosDevolucion.listo,
              alPresionar: () => _cerrar(registrada: true),
            ),
    );
  }
}
