import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/presentation/hoja_inferior.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/companiero_de_campania.dart';
import '../../domain/entities/transferencia.dart';
import '../textos_transferencias.dart';

// Las piezas de la vista 40 (HU-STK-005, #512). Todas crecen con el texto (`textScaler` 2.0): nada tiene
// alto fijo salvo el mínimo táctil.

const _borde = Color(0xFFE3E7EE);
const _verdeTinta = Color(0xFF1F6E3A);
const _verdeFondo = Color(0xFFDDE8D3);

/// De qué color y con qué glifo se dibuja cada estado (el canvas: ◷ ámbar, ✓ verde, ✕ rojo, – gris).
({String glifo, Color fondo, Color tinta}) _aspectoDe(EstadoDeTransferencia estado) =>
    switch (estado) {
      EstadoDeTransferencia.porAutorizar => (
        glifo: TextosTransferencias.glifoPorAutorizar,
        fondo: ColoresAgenda.ambarFondo,
        tinta: ColoresAgenda.ambarTinta,
      ),
      EstadoDeTransferencia.autorizada => (
        glifo: TextosTransferencias.glifoAutorizada,
        fondo: _verdeFondo,
        tinta: _verdeTinta,
      ),
      EstadoDeTransferencia.rechazada => (
        glifo: TextosTransferencias.glifoRechazada,
        fondo: const Color(0xFFFBEDEC),
        tinta: ColoresAgenda.rojo,
      ),
      EstadoDeTransferencia.cancelada => (
        glifo: TextosTransferencias.glifoCancelada,
        fondo: ColoresAgenda.grisFondo,
        tinta: ColoresAgenda.gris,
      ),
    };

/// Qué dice un aviso: informa, avisa que salió bien, que falló o que no hay conexión.
enum TipoDeBanner { info, ok, error, sinConexion }

/// El aviso de las vistas de la 40 (`banner` del canvas): una línea de texto con su color y, si hay, una
/// acción («Reintentar»).
class BannerDeTransferencia extends StatelessWidget {
  const BannerDeTransferencia({
    super.key,
    required this.texto,
    required this.tipo,
    this.textoAccion,
    this.alAccion,
  });

  final String texto;
  final TipoDeBanner tipo;
  final String? textoAccion;
  final VoidCallback? alAccion;

  @override
  Widget build(BuildContext context) {
    final (fondo, borde, tinta) = switch (tipo) {
      TipoDeBanner.info => (ColoresAgenda.azulFondo, ColoresAgenda.azul, ColoresAgenda.azul),
      TipoDeBanner.ok => (_verdeFondo, _verdeTinta, _verdeTinta),
      TipoDeBanner.error => (Colors.white, ColoresAgenda.rojo, ColoresAgenda.rojo),
      TipoDeBanner.sinConexion => (
        ColoresAgenda.grisFondo,
        ColoresAgenda.bordeChip,
        ColoresAgenda.tinta,
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borde, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(texto, style: TextStyle(fontSize: 13.5, height: 1.35, color: tinta)),
            if (textoAccion != null && alAccion != null)
              TextButton(
                onPressed: alAccion,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  foregroundColor: ColoresAgenda.azul,
                ),
                child: Text(textoAccion!, style: const TextStyle(fontWeight: FontWeight.w600)),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// La pantalla sin nada que mostrar (`hero` del canvas): un glifo, un título y qué hacer.
class HeroDeTransferencias extends StatelessWidget {
  const HeroDeTransferencias({
    super.key,
    required this.glifo,
    required this.titulo,
    required this.texto,
    this.verde = false,
  });

  final String glifo;
  final String titulo;
  final String texto;

  /// El círculo verde de «Transferencia pedida» (40A·06).
  final bool verde;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: verde ? _verdeFondo : ColoresAgenda.grisFondo,
              shape: BoxShape.circle,
            ),
            child: Text(
              glifo,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: verde ? _verdeTinta : ColoresAgenda.azul,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.4, color: ColoresAgenda.gris),
          ),
        ],
      ),
    );
  }
}

/// La fila de una transferencia en la lista (40B·01): su estado con glifo, quién le pidió a quién, qué
/// materiales y cuántos, y «›».
class TarjetaDeTransferencia extends StatelessWidget {
  const TarjetaDeTransferencia({
    super.key,
    required this.estado,
    required this.arriba,
    required this.titulo,
    required this.etiquetaDelEstado,
    required this.alPresionar,
  });

  final EstadoDeTransferencia estado;

  /// «HOY · LE PEDISTE A ANA PEREIRA».
  final String arriba;

  /// «Salud y Hogar × 2».
  final String titulo;

  /// «Por autorizar», «En cola»…
  final String etiquetaDelEstado;

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final aspecto = _aspectoDe(estado);
    return Semantics(
      button: true,
      label: '$titulo. $etiquetaDelEstado. $arriba',
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _borde),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: aspecto.fondo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    aspecto.glifo,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: aspecto.tinta,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arriba,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          letterSpacing: 1,
                          color: ColoresAgenda.gris,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        titulo,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: ColoresAgenda.grisFondo,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          etiquetaDelEstado,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: aspecto.tinta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('›', style: TextStyle(fontSize: 22, color: ColoresAgenda.gris)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El lugar donde se elige a quién se le pide (40A·01 a 40A·03): vacío con borde punteado («Elegir
/// colportor») o con la persona elegida y «Cambiar».
class TarjetaDeColportor extends StatelessWidget {
  const TarjetaDeColportor({super.key, required this.elegido, required this.alPresionar});

  final CompanieroDeCampania? elegido;
  final VoidCallback? alPresionar;

  static String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    final a = partes.first.characters.first;
    final b = partes.length > 1 ? partes.last.characters.first : '';
    return '$a$b'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final e = elegido;
    final contenido = Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: e == null ? ColoresAgenda.bordeChip : _borde,
          width: e == null ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: e == null ? ColoresAgenda.grisFondo : ColoresAgenda.navy,
              shape: BoxShape.circle,
            ),
            child: Text(
              e == null ? '+' : _iniciales(e.nombre),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: e == null ? ColoresAgenda.azul : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e != null)
                  const Text(
                    TextosTransferencias.sePediAEsta,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1,
                      color: ColoresAgenda.gris,
                    ),
                  ),
                Text(
                  e?.nombre ?? TextosTransferencias.elegirColportor,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: e == null ? ColoresAgenda.azul : ColoresAgenda.tinta,
                  ),
                ),
                Text(
                  e == null ? TextosTransferencias.deTuCampania : (e.lugar ?? ''),
                  style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris),
                ),
              ],
            ),
          ),
          if (e != null)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                TextosTransferencias.cambiar,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.azul,
                ),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: e == null
          ? TextosTransferencias.elegirColportor
          : '${TextosTransferencias.sePediAEsta} ${e.nombre}. ${TextosTransferencias.cambiar}',
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(14),
          child: contenido,
        ),
      ),
    );
  }
}

/// El esqueleto de la lista mientras se lee (40B·09): una fila de filtros y tres tarjetas.
class EsqueletoDeTransferencias extends StatelessWidget {
  const EsqueletoDeTransferencias({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto) => Container(
      height: alto,
      decoration: BoxDecoration(
        color: ColoresAgenda.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosTransferencias.cargando,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('transferencias_cargando'),
          children: [
            bloque(40),
            const SizedBox(height: 8),
            bloque(72),
            const SizedBox(height: 8),
            bloque(72),
            const SizedBox(height: 8),
            bloque(72),
          ],
        ),
      ),
    );
  }
}

const _formaHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// La hoja «¿A quién le pedís?» (40A·02). Pide la lista con [cargar] (la pantalla no la tiene hasta que
/// el servidor la da) y la dibuja: leyendo, con su falla y «Reintentar», o con los colportores para
/// elegir. Devuelve el elegido con «Listo», o `null` si se cerró sin elegir.
Future<CompanieroDeCampania?> mostrarHojaDeColportores(
  BuildContext context, {
  required Future<CompanierosDeCampania?> Function() cargar,
  required CompanieroDeCampania? elegido,
}) => mostrarHojaInferior<CompanieroDeCampania>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: _formaHoja,
  builder: (_) => HojaDeColportores(cargar: cargar, elegido: elegido),
);

class HojaDeColportores extends StatefulWidget {
  const HojaDeColportores({super.key, required this.cargar, required this.elegido});

  final Future<CompanierosDeCampania?> Function() cargar;
  final CompanieroDeCampania? elegido;

  @override
  State<HojaDeColportores> createState() => _HojaDeColportoresState();
}

class _HojaDeColportoresState extends State<HojaDeColportores> {
  CompanierosDeCampania? _lista;
  var _leyendo = true;
  var _fallo = false;
  String? _idElegido;
  var _respondio = false;

  @override
  void initState() {
    super.initState();
    _idElegido = widget.elegido?.id;
    unawaited(_leer());
  }

  Future<void> _leer() async {
    setState(() {
      _leyendo = true;
      _fallo = false;
    });
    CompanierosDeCampania? lista;
    try {
      lista = await widget.cargar();
    } on Object {
      lista = null;
    }
    if (!mounted) return;
    setState(() {
      _lista = lista;
      _leyendo = false;
      _fallo = lista == null;
    });
  }

  void _listo() {
    if (_respondio) return;
    final id = _idElegido;
    final elegido = id == null ? null : _lista?.por(id);
    _respondio = true;
    Navigator.of(context).pop(elegido);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    final Widget cuerpo;
    if (_leyendo) {
      cuerpo = Semantics(
        liveRegion: true,
        child: const Padding(
          key: Key('transferencia_colportores_cargando'),
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Row(
            children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  TextosTransferencias.cargandoColportores,
                  style: TextStyle(fontSize: 14, color: ColoresAgenda.gris),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_fallo || lista == null) {
      cuerpo = Padding(
        padding: const EdgeInsets.only(top: 12),
        child: BannerDeTransferencia(
          key: const Key('transferencia_colportores_error'),
          texto: TextosTransferencias.errorColportores,
          tipo: TipoDeBanner.error,
          textoAccion: TextosTransferencias.reintentar,
          alAccion: _leer,
        ),
      );
    } else {
      cuerpo = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in lista.companieros)
            Padding(
              key: Key('transferencia_colportor_${c.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: _FilaDeColportor(
                companiero: c,
                elegido: c.id == _idElegido,
                alPresionar: () => setState(() => _idElegido = c.id),
              ),
            ),
        ],
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosTransferencias.aQuienLePedis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (lista != null) ...[
              const SizedBox(height: 4),
              Text(
                TextosTransferencias.colportoresDe(lista.campania),
                style: const TextStyle(fontSize: 13.5, color: ColoresAgenda.gris),
              ),
            ],
            const SizedBox(height: 12),
            cuerpo,
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('transferencia_colportores_listo'),
              onPressed: _idElegido == null || lista == null ? null : _listo,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.navy,
                disabledBackgroundColor: ColoresAgenda.navy.withValues(alpha: .6),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosTransferencias.listo,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaDeColportor extends StatelessWidget {
  const _FilaDeColportor({
    required this.companiero,
    required this.elegido,
    required this.alPresionar,
  });

  final CompanieroDeCampania companiero;
  final bool elegido;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegido,
      inMutuallyExclusiveGroup: true,
      label: [companiero.nombre, ?companiero.lugar].join('. '),
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: elegido ? ColoresAgenda.azulFondo : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: elegido ? ColoresAgenda.azul : _borde,
                width: elegido ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companiero.nombre,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      if (companiero.lugar != null)
                        Text(
                          companiero.lugar!,
                          style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris),
                        ),
                    ],
                  ),
                ),
                if (elegido) const Icon(Icons.check_circle, color: ColoresAgenda.azul, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La hoja «¿Cancelar la transferencia?» (40B·03). Devuelve `true` con «Cancelar transferencia» y
/// `false` con «Volver» o al cerrarla sin elegir. Un segundo toque no vuelve a contestar.
Future<bool> mostrarHojaCancelarTransferencia(BuildContext context, {required String quien}) async {
  final si = await mostrarHojaInferior<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: _formaHoja,
    builder: (_) => HojaCancelarTransferencia(quien: quien),
  );
  return si ?? false;
}

class HojaCancelarTransferencia extends StatefulWidget {
  const HojaCancelarTransferencia({super.key, required this.quien});

  final String quien;

  @override
  State<HojaCancelarTransferencia> createState() => _HojaCancelarTransferenciaState();
}

class _HojaCancelarTransferenciaState extends State<HojaCancelarTransferencia> {
  var _respondio = false;

  void _responder(bool si) {
    if (_respondio) return;
    _respondio = true;
    Navigator.of(context).pop(si);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosTransferencias.cancelarTitulo,
                key: const Key('transferencia_cancelar_titulo'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              TextosTransferencias.cancelarTexto(widget.quien),
              key: const Key('transferencia_cancelar_texto'),
              style: const TextStyle(fontSize: 14, height: 1.4, color: ColoresAgenda.tinta),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('transferencia_cancelar_si'),
              onPressed: () => _responder(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.rojo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosTransferencias.cancelarSi,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('transferencia_cancelar_no'),
              onPressed: () => _responder(false),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text(
                TextosTransferencias.cancelarNo,
                style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una línea rótulo / valor del detalle y de «Transferencia pedida»: «Pide · Vos».
class DatoDeTransferencia {
  const DatoDeTransferencia({required this.clave, required this.rotulo, required this.valor});

  final String clave;
  final String rotulo;
  final String valor;
}

/// La tarjeta con las líneas rótulo / valor. El rótulo puede ser el nombre de un material (largo): se parte
/// en renglones en vez de desbordar, también con el texto al 200 %.
class FilasDeLaTransferencia extends StatelessWidget {
  const FilasDeLaTransferencia({super.key, required this.datos});

  final List<DatoDeTransferencia> datos;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('detalle_transferencia_filas'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Column(
        children: [
          for (final d in datos)
            Semantics(
              container: true,
              label: '${d.rotulo}: ${d.valor}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          d.rotulo,
                          style: const TextStyle(fontSize: 14, color: ColoresAgenda.gris),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          d.valor,
                          key: Key(d.clave),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 14, color: ColoresAgenda.tinta),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
