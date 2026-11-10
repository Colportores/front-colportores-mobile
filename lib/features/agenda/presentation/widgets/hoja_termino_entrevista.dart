import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../jornada/presentation/formato_jornada.dart';
import '../../../jornada/presentation/widgets/hoja_hora_inicio.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart';
import '../../../ventas/presentation/formato_venta.dart' show TextosVenta;
import '../../../ventas/presentation/widgets/piezas_venta.dart' show FilaDeCantidad;
import '../../domain/entities/misionero_dejado.dart';
import '../../domain/services/horas_de_entrevista.dart';
import 'textos_entrevista.dart';

/// Cómo se cerró la hoja «Terminó la entrevista».
sealed class SalidaTerminoEntrevista {
  const SalidaTerminoEntrevista();
}

/// «No, guardar y volver al mapa»: la visita quedó guardada como «Entrevista dada».
final class EntrevistaGuardada extends SalidaTerminoEntrevista {
  const EntrevistaGuardada();
}

/// «Sí, registrar la venta»: sigue la venta (vista 27) con estas horas. **Nada se guardó**: si la
/// venta no se completa, el resultado no se guarda (R44). Quien abre la hoja con [mostrarHojaTerminoEntrevista]
/// recibe esto; [FlujoEntrevista] lo lleva a la venta y devuelve [VentaGuardadaEnLaEntrevista] o
/// [VentaSinCompletar].
final class QuiereRegistrarLaVenta extends SalidaTerminoEntrevista {
  const QuiereRegistrarLaVenta({required this.entrada, required this.salida});

  final DateTime entrada;
  final DateTime salida;
}

/// La venta se guardó y, en la misma transacción, la visita quedó como `VENTA`: la entrevista está
/// cerrada con sus horas (decisión del orquestador, 23/10, #428). Sigue R·08 en la casa.
final class VentaGuardadaEnLaEntrevista extends SalidaTerminoEntrevista {
  const VentaGuardadaEnLaEntrevista({required this.numeroTalonario});

  /// El talonario de la venta («0039»), para el aviso «Venta 0039 guardada.».
  final String numeroTalonario;
}

/// La venta no se completó (se salió de la pantalla, falló el guardado, ya no hay a quién vendérsela):
/// por R44 no se guardó ningún resultado y **la entrevista sigue en curso**. Quien lo recibe no cierra
/// nada más (por ejemplo, la jornada).
final class VentaSinCompletar extends SalidaTerminoEntrevista {
  const VentaSinCompletar();
}

/// Guarda la visita con las horas confirmadas y los misioneros que dejó (producto → cuántos; vacío si
/// no dejó ninguno) y devuelve la falla, o `null` si salió bien.
typedef GuardarEntrevista =
    Future<Failure?> Function(DateTime entrada, DateTime salida, Map<String, int> misioneros);

/// Abre la hoja R·06 / R·07 «Terminó la entrevista» (con velo, como el canvas). Devuelve cómo se
/// cerró, o `null` si la colportora la cerró sin elegir (la entrevista sigue en curso).
///
/// [alGuardar] guarda la visita y devuelve la falla, o `null` si salió bien. [misioneros] son los que
/// puede anotar en «Lo que dejaste» (#608); sin ninguno, ese paso no aparece.
Future<SalidaTerminoEntrevista?> mostrarHojaTerminoEntrevista(
  BuildContext context, {
  required String direccion,
  required String persona,
  required DateTime? entrada,
  required DateTime? salida,
  required bool entradaInferida,
  required GuardarEntrevista alGuardar,
  List<MisioneroParaDejar> misioneros = const [],
  DateTime Function()? reloj,
}) => showModalBottomSheet<SalidaTerminoEntrevista>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  // La asa arrastra y cierra la hoja (la entrevista sigue en curso), salvo mientras guarda: ahí la
  // hoja frena el arrastre ella misma, porque el arrastre no pasa por el `PopScope` (QA #450).
  enableDrag: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaTerminoEntrevista(
    direccion: direccion,
    persona: persona,
    entrada: entrada,
    salida: salida,
    entradaInferida: entradaInferida,
    alGuardar: alGuardar,
    misioneros: misioneros,
    reloj: reloj,
  ),
);

/// R·06 · «Finalizar: horas y ¿hubo venta?» y R·07 · «Sin inicio registrado» (vista 39).
///
/// Muestra la entrada y la salida (se corrigen de a 5 minutos con la misma hoja de la jornada, −5 /
/// +5) y la duración, y pregunta «¿Hubo venta?». «No, guardar y volver al mapa» guarda la visita
/// como «Entrevista dada»; «Sí, registrar la venta» devuelve [QuiereRegistrarLaVenta] sin guardar.
///
/// - R·07: [entradaInferida] pone el aviso «No registramos el inicio. Tomamos la hora de tu visita
///   anterior (14:10). Revisala.» con la [entrada] que se tomó de esa visita.
/// - Una hora en `null` **no se inventa**: la fila dice «Elegir» y no se puede seguir hasta
///   elegirla. Pasa con la salida cuando la app se cerró con la entrevista abierta o se termina la
///   jornada con ella abierta (decisión de Cristian, 23/10, #450), y con la entrada si no hay
///   ninguna visita anterior de la que tomarla.
/// - Un solo guardado a la vez: con «Guardando…» ningún botón responde y la hoja no se arrastra. Si
///   falla, el aviso dice qué hacer y los botones vuelven a estar habilitados.
/// - «Lo que dejaste» (#608; decisiones de Cristian, 03/11 «Talonario mis» y 04/11 «Misio. entrev»):
///   con [misioneros] en el catálogo, «No hubo venta» pasa a un segundo paso para anotar los
///   misioneros que dejó sin venta, con el selector de 27A·08 y sin montos. Sigue el artboard 42B·08
///   con las decisiones del 10/11: una sola salida «No», pie «Guardar» + «No dejé nada» y sin stock.
class HojaTerminoEntrevista extends StatefulWidget {
  const HojaTerminoEntrevista({
    super.key,
    required this.direccion,
    required this.persona,
    required this.entrada,
    required this.salida,
    required this.entradaInferida,
    required this.alGuardar,
    this.misioneros = const [],
    this.reloj,
  });

  final String direccion;
  final String persona;
  final DateTime? entrada;
  final DateTime? salida;
  final bool entradaInferida;
  final GuardarEntrevista alGuardar;
  final List<MisioneroParaDejar> misioneros;
  final DateTime Function()? reloj;

  @override
  State<HojaTerminoEntrevista> createState() => _HojaTerminoEntrevistaState();
}

class _HojaTerminoEntrevistaState extends State<HojaTerminoEntrevista> {
  DateTime? _entrada;
  DateTime? _salida;
  bool _guardando = false;
  String? _error;

  /// El aviso de error y los botones que siguen: al fallar se llevan a la vista juntos (con la letra
  /// grande el aviso empuja el botón fuera de la pantalla, QA #432).
  final _reintento = GlobalKey();

  /// En el paso «Lo que dejaste».
  bool _enLoQueDejaste = false;

  /// Producto → cuántos dejó.
  final _dejados = <String, int>{};

  int get _totalDejados => _dejados.values.fold(0, (suma, n) => suma + n);

  /// Un hueco por tipo de toque: dos toques seguidos no abren dos hojas de hora ni guardan dos veces.
  bool _eligiendoHora = false;

  @override
  void initState() {
    super.initState();
    _entrada = widget.entrada == null
        ? null
        : HorasDeEntrevista.alMinuto(widget.entrada!.toLocal());
    _salida = widget.salida == null ? null : HorasDeEntrevista.alMinuto(widget.salida!.toLocal());
  }

  DateTime _ahora() => HorasDeEntrevista.alMinuto((widget.reloj ?? DateTime.now)().toLocal());

  bool get _completa => _entrada != null && _salida != null;

  Future<void> _elegirEntrada() async {
    if (_eligiendoHora || _guardando) return;
    // Hasta la salida (o ahora, si todavía no hay), y hasta 12 h antes.
    final tope = _salida ?? _ahora();
    const margen = 12 * 60;
    final actual = _entrada;
    await _elegir(
      tope: tope,
      margen: margen,
      minutosAtras: actual == null ? 0 : tope.difference(actual).inMinutes.clamp(0, margen),
      pregunta: TextosEntrevista.preguntaEntrada,
      campo: TextosEntrevista.campoEntrada,
      alElegir: (hora) => _entrada = hora,
    );
  }

  Future<void> _elegirSalida() async {
    if (_eligiendoHora || _guardando) return;
    final ahora = _ahora();
    // Desde la entrada y hasta ahora, sin pasar de 12 h desde la entrada. Sin entrada todavía, el
    // rango es el de las últimas 12 h.
    final entrada = _entrada;
    final tope = entrada == null
        ? ahora
        : HorasDeEntrevista.topeDeLaSalida(entrada: entrada, ahora: ahora);
    final margen = entrada == null ? 12 * 60 : tope.difference(entrada).inMinutes.clamp(0, 12 * 60);
    final actual = _salida;
    await _elegir(
      tope: tope,
      margen: margen,
      minutosAtras: actual == null ? 0 : tope.difference(actual).inMinutes.clamp(0, margen),
      pregunta: TextosEntrevista.preguntaSalida,
      campo: TextosEntrevista.campoSalida,
      alElegir: (hora) => _salida = hora,
    );
  }

  Future<void> _elegir({
    required DateTime tope,
    required int margen,
    required int minutosAtras,
    required String pregunta,
    required String campo,
    required void Function(DateTime hora) alElegir,
  }) async {
    _eligiendoHora = true;
    try {
      final elegida = await mostrarHojaHoraInicio(
        context,
        ahora: tope,
        margenMinutos: margen,
        minutosAtras: minutosAtras,
        pregunta: pregunta,
        etiquetaCampo: campo,
        mostrarRelativo: false,
        notaDeHora: (hora) {
          final texto = TextosEntrevista.horaConDia(hora, _ahora());
          return texto == horaCorta(hora) ? null : diaCorto(hora);
        },
      );
      if (elegida == null || !mounted) return;
      setState(() {
        alElegir(HorasDeEntrevista.alMinuto(elegida.hora.toLocal()));
        _error = null;
      });
    } finally {
      _eligiendoHora = false;
    }
  }

  /// Guarda la entrevista: [conMisioneros] manda lo anotado en «Lo que dejaste»; «No dejé nada» (y
  /// «No hubo venta» sin misioneros en el catálogo) guardan sin misioneros.
  Future<void> _guardar({bool conMisioneros = false}) async {
    final entrada = _entrada;
    final salida = _salida;
    if (entrada == null || salida == null || _guardando) return;
    // La guarda es un campo: dos toques llegan antes de que el `setState` reconstruya.
    _guardando = true;
    setState(() => _error = null);
    Failure? falla;
    try {
      falla = await widget.alGuardar(entrada, salida, {
        if (conMisioneros)
          for (final e in _dejados.entries)
            if (e.value > 0) e.key: e.value,
      });
    } on Object {
      falla = const FailureInesperado();
    }
    if (!mounted) return;
    if (falla == null) {
      Navigator.of(context).pop(const EntrevistaGuardada());
      return;
    }
    setState(() {
      _guardando = false;
      _error = switch (falla) {
        FailureValidacion(:final mensaje) => mensaje,
        _ => TextosEntrevista.noPudimosGuardar,
      };
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bloque = _reintento.currentContext;
      if (!mounted || bloque == null) return;
      unawaited(
        Scrollable.ensureVisible(
          bloque,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  /// «No hubo venta» (42B·08A, decisión del 10/11: una sola salida «No»): con misioneros en el
  /// catálogo lleva a «Lo que dejaste», vacío, sin guardar todavía; sin ninguno, guarda en ese toque.
  void _noHuboVenta() {
    if (!_completa || _guardando) return;
    if (widget.misioneros.isEmpty) {
      unawaited(_guardar());
      return;
    }
    setState(() {
      _dejados.clear();
      _enLoQueDejaste = true;
      _error = null;
    });
  }

  /// Atrás desde «Lo que dejaste»: a R·06, y las cantidades marcadas se descartan (42B·06).
  void _volverALasHoras() {
    if (_guardando || !_enLoQueDejaste) return;
    setState(() {
      _dejados.clear();
      _enLoQueDejaste = false;
      _error = null;
    });
  }

  void _registrarVenta() {
    final entrada = _entrada;
    final salida = _salida;
    if (entrada == null || salida == null || _guardando) return;
    // Un solo toque: la hoja se cierra con las horas y la venta sigue por su lado.
    _guardando = true;
    Navigator.of(context).pop(QuiereRegistrarLaVenta(entrada: entrada, salida: salida));
  }

  String? get _avisoDeHora {
    if (_entrada == null && _salida == null) return TextosEntrevista.pedirAmbas;
    if (_entrada == null) return TextosEntrevista.pedirEntrada;
    if (_salida == null) return TextosEntrevista.pedirSalida;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con el guardado en vuelo la hoja no se cierra: sin ella, nadie recibe el resultado y la
      // colportora se queda sin la confirmación (o sin el aviso de que no se guardó). En «Lo que
      // dejaste», atrás vuelve a las horas.
      canPop: !_guardando && !_enLoQueDejaste,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _volverALasHoras();
      },
      child: GestureDetector(
        // Mientras guarda, el arrastre de la hoja se frena acá: el `PopScope` no lo ve.
        onVerticalDragStart: _guardando ? (_) {} : null,
        onVerticalDragUpdate: _guardando ? (_) {} : null,
        onVerticalDragEnd: _guardando ? (_) {} : null,
        child: SafeArea(
          top: false,
          child: _enLoQueDejaste ? _pasoLoQueDejaste(context) : _pasoHoras(context),
        ),
      ),
    );
  }

  /// R·06 / R·07: las horas y «¿Hubo venta?».
  Widget _pasoHoras(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final lugar = TextosEntrevista.lugarYPersona(widget.direccion, widget.persona);
    final entrada = _entrada;
    final salida = _salida;
    final aviso = _avisoDeHora;
    return SingleChildScrollView(
      key: ClavesEntrevista.hojaTermino,
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Asa(),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(TextosEntrevista.terminoTitulo, style: theme.textTheme.headlineMedium),
          ),
          if (lugar.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lugar, style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris)),
          ],
          const SizedBox(height: 16),
          if (widget.entradaInferida && entrada != null) ...[
            AvisoAlta(
              key: ClavesEntrevista.avisoSinInicio,
              color: ColoresAlta.ambarBorde,
              glyph: '!',
              texto: TextosEntrevista.sinInicio(horaCorta(entrada)),
            ),
            const SizedBox(height: 12),
          ],
          _TarjetaDeHoras(
            ahora: _ahora(),
            entrada: entrada,
            salida: salida,
            alElegirEntrada: _guardando ? null : _elegirEntrada,
            alElegirSalida: _guardando ? null : _elegirSalida,
            // R·07: la entrada se tomó de la visita anterior, así que «Duración» no se afirma
            // (el canvas no la dibuja).
            conDuracion: !widget.entradaInferida,
          ),
          if (aviso != null) ...[
            const SizedBox(height: 12),
            AvisoAlta(
              key: ClavesEntrevista.avisoPedirHora,
              color: ColoresAlta.tinta,
              glyph: 'i',
              texto: aviso,
            ),
          ],
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text(
              TextosEntrevista.hayVenta,
              style: theme.textTheme.labelSmall?.copyWith(color: colores.gris, letterSpacing: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: ClavesEntrevista.registrarVenta,
            onPressed: _completa && !_guardando ? _registrarVenta : null,
            child: const Text(TextosEntrevista.registrarVenta),
          ),
          const SizedBox(height: 10),
          Column(
            key: _reintento,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                AvisoAlta(
                  key: ClavesEntrevista.avisoError,
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: _error!,
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton(
                key: ClavesEntrevista.guardarYVolver,
                onPressed: _completa && !_guardando ? _noHuboVenta : null,
                child: Text(
                  _guardando ? TextosEntrevista.guardando : TextosEntrevista.guardarYVolver,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// «Lo que dejaste» (vista 42, 42B·08B y 08C, #608): los misioneros que dejó sin venta, con el
  /// selector de 27A·08 sin precios. Sin «Tenés N en mano» ni 08D: el stock queda para después
  /// (decisión de Cristian del 09/11, «Stock/avisos»).
  Widget _pasoLoQueDejaste(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final lugar = TextosEntrevista.lugarYPersona(widget.direccion, widget.persona);
    final total = _totalDejados;
    return SingleChildScrollView(
      key: ClavesEntrevista.loQueDejaste,
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Asa(),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(TextosEntrevista.loQueDejasteTitulo, style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 4),
          Text(
            TextosEntrevista.loQueDejasteLugar(lugar),
            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
          ),
          const SizedBox(height: 14),
          // Mientras guarda, las cantidades no se tocan: lo que se guarda es lo que se ve.
          IgnorePointer(
            ignoring: _guardando,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in widget.misioneros)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilaDeCantidad(
                      key: ValueKey('entrevista_misionero_${m.productoId}'),
                      titulo: m.nombre,
                      cantidad: _dejados[m.productoId] ?? 0,
                      alCambiar: (n) => setState(() {
                        _dejados[m.productoId] = n;
                        _error = null;
                      }),
                      etiqueta: TextosVenta.misionero,
                      tintaEtiqueta: const Color(0xFF1F6E3A),
                      fondoEtiqueta: const Color(0xFFDDE8D3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            total > 0 ? TextosEntrevista.dejas(total) : TextosEntrevista.loQueDejasteVacio,
            key: ClavesEntrevista.avisoLoQueDejaste,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: total > 0 ? null : colores.gris,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Column(
            key: _reintento,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                AvisoAlta(
                  key: ClavesEntrevista.avisoError,
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: _error!,
                ),
                const SizedBox(height: 10),
              ],
              FilledButton(
                key: ClavesEntrevista.guardarLoQueDejaste,
                onPressed: _guardando || total == 0
                    ? null
                    : () => unawaited(_guardar(conMisioneros: true)),
                child: Text(
                  _guardando ? TextosEntrevista.guardando : TextosEntrevista.guardarLoQueDejaste,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: ClavesEntrevista.noDejeNada,
                onPressed: _guardando ? null : () => unawaited(_guardar()),
                child: const Text(TextosEntrevista.noDejeNada),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Las filas Entrada, Salida y Duración del canvas (`kv`): tarjeta blanca con borde, cada hora
/// tocable con su ✎.
class _TarjetaDeHoras extends StatelessWidget {
  const _TarjetaDeHoras({
    required this.ahora,
    required this.entrada,
    required this.salida,
    required this.alElegirEntrada,
    required this.alElegirSalida,
    required this.conDuracion,
  });

  final DateTime ahora;
  final DateTime? entrada;
  final DateTime? salida;
  final VoidCallback? alElegirEntrada;
  final VoidCallback? alElegirSalida;

  /// `false` en R·07, donde la hora de entrada es una suposición.
  final bool conDuracion;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).extension<ColoresColportaje>()!;
    // Con el reloj atrasado la salida quedaría antes de la entrada: no se muestra una duración que
    // miente («menos de 1 min»).
    final diferencia = entrada != null && salida != null ? salida!.difference(entrada!) : null;
    final duracion = conDuracion && diferencia != null && !diferencia.isNegative
        ? diferencia
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colores.borde),
      ),
      child: Column(
        children: [
          _FilaDeHora(
            key: ClavesEntrevista.filaEntrada,
            rotulo: TextosEntrevista.entrada,
            ahora: ahora,
            hora: entrada,
            alTocar: alElegirEntrada,
          ),
          Divider(height: 1, color: colores.borde),
          _FilaDeHora(
            key: ClavesEntrevista.filaSalida,
            rotulo: TextosEntrevista.salida,
            ahora: ahora,
            hora: salida,
            alTocar: alElegirSalida,
          ),
          if (duracion != null) ...[
            Divider(height: 1, color: colores.borde),
            Padding(
              key: ClavesEntrevista.duracion,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    TextosEntrevista.duracion,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.gris),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      duracionCorta(duracion),
                      textAlign: TextAlign.end,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaDeHora extends StatelessWidget {
  const _FilaDeHora({
    super.key,
    required this.rotulo,
    required this.ahora,
    required this.hora,
    required this.alTocar,
  });

  final String rotulo;
  final DateTime ahora;
  final DateTime? hora;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final texto = hora == null
        ? TextosEntrevista.elegirLaHora
        : TextosEntrevista.horaConDia(hora!, ahora);
    return Semantics(
      container: true,
      button: true,
      enabled: alTocar != null,
      excludeSemantics: true,
      label: '$rotulo, ${hora == null ? 'sin elegir' : texto}',
      onTapHint: 'Cambiar la hora',
      onTap: alTocar,
      child: InkWell(
        onTap: alTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(rotulo, style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '$texto  ✎',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: hora == null ? ColoresAlta.azul : null,
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

class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).extension<ColoresColportaje>()!;
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colores.bordeInput,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
