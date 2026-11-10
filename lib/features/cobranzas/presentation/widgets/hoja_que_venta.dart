import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart' show AvisoAlta, ColoresAlta;
import '../../domain/entities/venta_con_saldo.dart';
import '../../domain/value_objects/paso_que_venta.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_que_venta.dart';

/// Cuánto se espera la lectura previa de las ventas antes de mostrar la hoja «cargando».
const _esperaPrevia = Duration(milliseconds: 250);

/// Abre «¿Qué venta?» (vista 39, C·08, HU-COB-001) para la persona [personaId] y devuelve la venta que
/// se cobra, o `null` si la colportora tocó «Cancelar» o cerró sin elegir.
///
/// - Con **una sola** venta con saldo **no muestra nada** y devuelve esa venta («Con una sola venta con
///   saldo se salta»).
/// - Con **varias**: la lista, con la más vieja elegida, «Cobrar» y «Cancelar».
/// - Sin ventas con saldo (pagó todo mientras la hoja de la casa estaba abierta): lo dice y se cierra
///   con «Cerrar»; devuelve `null`.
/// - Sin poder leer: el aviso con «Reintentar» y «Cancelar».
///
/// Todo es local: no hay estado «sin conexión». [nombre] es el nombre de pila de quien debe, para el
/// título; `null` si la persona ya no está en la casa.
Future<VentaConSaldo?> mostrarHojaQueVenta(
  BuildContext context, {
  required String personaId,
  String? nombre,
}) async {
  // La lectura previa evita que, con una sola venta, la hoja se abra para cerrarse enseguida.
  List<VentaConSaldo>? previas;
  var fallo = false;
  try {
    final repo = ProviderScope.containerOf(context, listen: false).read(cobranzaRepositoryProvider);
    final leidas = await repo.ventasConSaldoDe(personaId).timeout(_esperaPrevia);
    previas = leidas.fold((_) => null, (ventas) => ventas);
    fallo = previas == null;
    if (previas != null) {
      final paso = PasoQueVenta.de(previas);
      if (paso is UnaVentaConSaldo) return paso.venta;
    }
  } on TimeoutException {
    // No dio tiempo: la hoja se abre «cargando» y lee ella.
  } on Object {
    // Falló la lectura: la hoja lo dice enseguida, con su «Reintentar».
    fallo = true;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<VentaConSaldo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => HojaQueVenta(
      personaId: personaId,
      nombre: nombre,
      ventasLeidas: previas,
      fallaPrevia: fallo,
    ),
  );
}

enum _Lectura { cargando, lista, sinSaldo, conError }

/// La hoja de «¿Qué venta?» (vista 39, C·08). Ver [mostrarHojaQueVenta].
class HojaQueVenta extends ConsumerStatefulWidget {
  const HojaQueVenta({
    super.key,
    required this.personaId,
    this.nombre,
    this.ventasLeidas,
    this.fallaPrevia = false,
  });

  /// Quien debe.
  final String personaId;

  /// Su nombre de pila, para el título.
  final String? nombre;

  /// Lo que ya se leyó antes de abrir la hoja; `null` si no dio tiempo o falló (ver [fallaPrevia]).
  final List<VentaConSaldo>? ventasLeidas;

  /// La lectura de antes de abrir la hoja falló: se abre ya con el aviso y su «Reintentar», sin leer de
  /// nuevo por su cuenta.
  final bool fallaPrevia;

  @override
  ConsumerState<HojaQueVenta> createState() => _HojaQueVentaState();
}

class _HojaQueVentaState extends ConsumerState<HojaQueVenta> {
  var _lectura = _Lectura.cargando;
  List<VentaConSaldo> _ventas = const [];

  /// La venta tocada; `null` = la primera.
  String? _elegidaId;

  /// Hay una lectura en curso: un segundo «Reintentar» no lanza otra.
  var _leyendo = false;

  /// Ya se está cerrando con un resultado: ningún otro toque cierra otra vez.
  var _cerrando = false;

  @override
  void initState() {
    super.initState();
    final previas = widget.ventasLeidas;
    if (previas != null) {
      _aplicar(previas);
    } else if (widget.fallaPrevia) {
      _lectura = _Lectura.conError;
    } else {
      unawaited(_leer(mostrarCarga: false));
    }
  }

  Future<void> _leer({bool mostrarCarga = true}) async {
    if (_leyendo || _cerrando) return;
    _leyendo = true;
    if (mostrarCarga) setState(() => _lectura = _Lectura.cargando);
    try {
      final leidas = await ref.read(cobranzaRepositoryProvider).ventasConSaldoDe(widget.personaId);
      if (!mounted) return;
      leidas.fold(
        (_) => setState(() => _lectura = _Lectura.conError),
        (v) => setState(() => _aplicar(v)),
      );
    } on Object {
      // Nada del error al mensaje: puede traer datos de la venta (convenciones §7.5).
      if (mounted) setState(() => _lectura = _Lectura.conError);
    } finally {
      _leyendo = false;
    }
  }

  /// Decide qué muestra la hoja con lo leído. Con una sola venta se salta: se cierra apenas termina el
  /// cuadro.
  void _aplicar(List<VentaConSaldo> leidas) {
    switch (PasoQueVenta.de(leidas)) {
      case SinVentasConSaldo():
        _ventas = const [];
        _lectura = _Lectura.sinSaldo;
      case UnaVentaConSaldo(:final venta):
        _ventas = [venta];
        _lectura = _Lectura.cargando;
        _saltar(venta);
      case VariasVentasConSaldo(:final ventas):
        _ventas = ventas;
        _lectura = _Lectura.lista;
    }
  }

  void _saltar(VentaConSaldo venta) {
    if (_cerrando) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cerrarCon(venta);
    });
  }

  void _cerrarCon(VentaConSaldo? venta) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(venta);
  }

  /// La venta elegida de [ventas]: la tocada o, si no se tocó ninguna (o ya no está), la primera.
  VentaConSaldo? _elegidaDe(List<VentaConSaldo> ventas) => ventas.isEmpty
      ? null
      : ventas.firstWhere((v) => v.ventaId == _elegidaId, orElse: () => ventas.first);

  @override
  Widget build(BuildContext context) {
    final cuerpo = switch (_lectura) {
      _Lectura.cargando => _Cargando(alCancelar: () => _cerrarCon(null)),
      _Lectura.conError => _ErrorDeLectura(alReintentar: _leer, alCancelar: () => _cerrarCon(null)),
      _Lectura.sinSaldo => _SinSaldo(nombre: widget.nombre, alCerrar: () => _cerrarCon(null)),
      _Lectura.lista => _lista(context),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Asa(),
          Flexible(child: cuerpo),
        ],
      ),
    );
  }

  /// C·08: una venta por fila (viene elegida la más vieja) y «Cobrar» / «Cancelar» fijos al pie.
  Widget _lista(BuildContext context) {
    final elegida = _elegidaDe(_ventas);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView.separated(
            key: ClavesQueVenta.lista,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            itemCount: _ventas.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) return _Encabezado(titulo: TextosQueVenta.titulo(widget.nombre));
              final venta = _ventas[i - 1];
              return _FilaVenta(
                key: ClavesQueVenta.fila(venta.ventaId),
                venta: venta,
                seleccionada: venta.ventaId == elegida?.ventaId,
                alTocar: () => setState(() => _elegidaId = venta.ventaId),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: ClavesQueVenta.cobrar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: elegida == null ? null : () => _cerrarCon(_elegidaDe(_ventas)),
                child: const Text(TextosQueVenta.cobrar, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              _BotonSecundario(
                clave: ClavesQueVenta.cancelar,
                etiqueta: TextosQueVenta.cancelar,
                alTocar: () => _cerrarCon(null),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// El asa de la hoja.
class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColoresAlta.grisBorde,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// El título de la hoja.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(titulo, style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// Una venta de C·08: el círculo de elección, «Venta 0038 · 12/10», qué se vendió y, a la derecha, lo
/// que falta cobrar. Elegida: fondo azul claro y borde de 2.
class _FilaVenta extends StatelessWidget {
  const _FilaVenta({
    super.key,
    required this.venta,
    required this.seleccionada,
    required this.alTocar,
  });

  final VentaConSaldo venta;
  final bool seleccionada;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navy = theme.colorScheme.primary;
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final descripcion = venta.descripcion.trim();
    return Semantics(
      container: true,
      excludeSemantics: true,
      inMutuallyExclusiveGroup: true,
      checked: seleccionada,
      label: TextosQueVenta.opcionParaLector(venta),
      onTap: alTocar,
      child: Material(
        color: seleccionada ? const Color(0xFFF2F6FB) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: seleccionada
              ? BorderSide(color: navy, width: 2)
              : const BorderSide(color: Color(0xFFE3E7EE)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: seleccionada ? navy : Colors.white,
                      border: Border.all(color: seleccionada ? navy : ColoresAlta.gris, width: 1.5),
                    ),
                    child: seleccionada
                        ? const Icon(Icons.circle, size: 8, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TextosQueVenta.ventaDel(venta),
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (descripcion.isNotEmpty)
                          Text(
                            descripcion,
                            style: theme.textTheme.bodyMedium?.copyWith(color: gris),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    TextosQueVenta.saldo(venta),
                    key: ClavesQueVenta.saldo(venta.ventaId),
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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

/// «Cancelar» o «Cerrar»: la salida sin elegir, de contorno.
class _BotonSecundario extends StatelessWidget {
  const _BotonSecundario({required this.clave, required this.etiqueta, required this.alTocar});

  final Key clave;
  final String etiqueta;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: clave,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      foregroundColor: ColoresAlta.tinta,
      side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
    ),
    onPressed: alTocar,
    child: Text(etiqueta, textAlign: TextAlign.center),
  );
}

/// Mientras llegan las ventas.
class _Cargando extends StatelessWidget {
  const _Cargando({required this.alCancelar});

  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: ClavesQueVenta.cargando,
            liveRegion: true,
            label: TextosQueVenta.cargando,
            child: ExcludeSemantics(
              child: Row(
                spacing: 12,
                children: [
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  Expanded(
                    child: Text(
                      TextosQueVenta.cargando,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _BotonSecundario(
            clave: ClavesQueVenta.cancelar,
            etiqueta: TextosQueVenta.cancelar,
            alTocar: alCancelar,
          ),
        ],
      ),
    );
  }
}

/// No se pudieron leer las ventas: qué pasó y qué hacer (principio 4).
class _ErrorDeLectura extends StatelessWidget {
  const _ErrorDeLectura({required this.alReintentar, required this.alCancelar});

  final VoidCallback alReintentar;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AvisoAlta(
            key: ClavesQueVenta.error,
            color: ColoresAlta.rojo,
            glyph: '!',
            texto: TextosQueVenta.noPudimosLeer,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: ClavesQueVenta.reintentar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: alReintentar,
            child: const Text(TextosQueVenta.reintentar, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 10),
          _BotonSecundario(
            clave: ClavesQueVenta.cancelar,
            etiqueta: TextosQueVenta.cancelar,
            alTocar: alCancelar,
          ),
        ],
      ),
    );
  }
}

/// La persona ya no debe nada: se dice y se cierra.
class _SinSaldo extends StatelessWidget {
  const _SinSaldo({required this.nombre, required this.alCerrar});

  final String? nombre;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AvisoAlta(
            key: ClavesQueVenta.sinSaldo,
            color: ColoresAlta.azul,
            glyph: 'i',
            texto: TextosQueVenta.sinSaldo(nombre),
          ),
          const SizedBox(height: 16),
          _BotonSecundario(
            clave: ClavesQueVenta.cerrar,
            etiqueta: TextosQueVenta.cerrar,
            alTocar: alCerrar,
          ),
        ],
      ),
    );
  }
}

/// Las claves de la hoja «¿Qué venta?» (para los tests y la QA).
abstract final class ClavesQueVenta {
  static const lista = Key('que_venta_lista');
  static const cobrar = Key('que_venta_cobrar');
  static const cancelar = Key('que_venta_cancelar');
  static const cerrar = Key('que_venta_cerrar');
  static const reintentar = Key('que_venta_reintentar');
  static const cargando = Key('que_venta_cargando');
  static const error = Key('que_venta_error');
  static const sinSaldo = Key('que_venta_sin_saldo');

  static Key fila(String ventaId) => Key('que_venta_fila_$ventaId');
  static Key saldo(String ventaId) => Key('que_venta_saldo_$ventaId');
}
