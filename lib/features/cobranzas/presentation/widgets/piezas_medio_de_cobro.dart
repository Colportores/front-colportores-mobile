import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/usecases/registrar_cobro_use_case.dart';
import '../textos_medio_de_cobro.dart';

// Las piezas de la vista 29 (cobro con tarjeta y por transferencia). Todas crecen con el texto
// (`textScaler` 2.0): nada tiene alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFE3E7EE);

const _estiloRotulo = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10.5,
  letterSpacing: 1.6,
  color: ColoresAgenda.gris,
);

const _formaHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

// 13 y no 13,5: con Inter de verdad (y el espaciado del tema) «Transferencia» mide ~90 dp y la fila de
// tres del canvas tiene que entrar en 360 dp (308 dp útiles, a un tercio cada uno) sin apilarse.
const _estiloSegmento = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

/// Relleno horizontal de cada segmento y borde (1,5 por lado): lo que se suma al ancho del rótulo.
const _rellenoDelSegmento = 4.0;
const _bordeDelSegmento = 1.5;

/// Un control de opciones excluyentes (el «MEDIO» y el «Débito / Crédito» del canvas): una fila de
/// segmentos iguales, o una columna si con la letra grande los rótulos no entran en una fila.
class SegmentadoDeCobro extends StatelessWidget {
  const SegmentadoDeCobro({
    super.key,
    required this.etiqueta,
    required this.opciones,
    required this.elegida,
    required this.alElegir,
    required this.prefijoDeClave,
    this.rotulo,
    this.habilitado = true,
  });

  /// Lo que oye el lector de pantalla al llegar al grupo.
  final String etiqueta;

  /// El rótulo visible de arriba («MEDIO»); el «Débito / Crédito» del canvas no lo tiene.
  final String? rotulo;
  final List<String> opciones;
  final int elegida;
  final ValueChanged<int> alElegir;

  /// Cada segmento lleva la clave `<prefijo>_<posición>`.
  final String prefijoDeClave;

  /// `false` mientras se guarda: no responde.
  final bool habilitado;

  static const _hueco = 6.0;

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rotulo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ExcludeSemantics(child: Text(rotulo!, style: _estiloRotulo)),
          ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: etiqueta,
          child: LayoutBuilder(
            builder: (context, caja) {
              // Si el rótulo más largo no entra en su parte del ancho, los segmentos se apilan: con
              // letra grande nada se corta ni se parte a la mitad de una palabra.
              // Se mide con el mismo estilo con que se dibuja: el del tema (Inter) más el del segmento. Con
              // `_estiloSegmento` solo, el `TextPainter` usa la fuente por defecto y no la de la app.
              final estilo = DefaultTextStyle.of(context).style.merge(_estiloSegmento);
              var masAncho = 0.0;
              for (final texto in opciones) {
                final medida = TextPainter(
                  text: TextSpan(text: texto, style: estilo),
                  textDirection: TextDirection.ltr,
                  textScaler: escala,
                  maxLines: 1,
                )..layout();
                if (medida.width > masAncho) masAncho = medida.width;
                medida.dispose();
              }
              final cuanto = (caja.maxWidth - _hueco * (opciones.length - 1)) / opciones.length;
              final enFila = masAncho + 2 * (_rellenoDelSegmento + _bordeDelSegmento) <= cuanto;
              final segmentos = [
                for (var i = 0; i < opciones.length; i++)
                  _Segmento(
                    key: Key('${prefijoDeClave}_$i'),
                    texto: opciones[i],
                    elegido: i == elegida,
                    habilitado: habilitado,
                    alPresionar: () => alElegir(i),
                  ),
              ];
              if (enFila) {
                return Row(
                  children: [
                    for (var i = 0; i < segmentos.length; i++) ...[
                      if (i > 0) const SizedBox(width: _hueco),
                      Expanded(child: segmentos[i]),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < segmentos.length; i++) ...[
                    if (i > 0) const SizedBox(height: _hueco),
                    segmentos[i],
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Segmento extends StatelessWidget {
  const _Segmento({
    super.key,
    required this.texto,
    required this.elegido,
    required this.habilitado,
    required this.alPresionar,
  });

  final String texto;
  final bool elegido;
  final bool habilitado;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegido,
      inMutuallyExclusiveGroup: true,
      enabled: habilitado,
      label: texto,
      onTap: habilitado ? alPresionar : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: habilitado ? alPresionar : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: _rellenoDelSegmento, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: elegido ? ColoresAgenda.navy : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: elegido ? ColoresAgenda.navy : ColoresAgenda.bordeChip,
                width: _bordeDelSegmento,
              ),
            ),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: _estiloSegmento.copyWith(color: elegido ? Colors.white : ColoresAgenda.tinta),
            ),
          ),
        ),
      ),
    );
  }
}

/// Los datos opcionales del cobro con tarjeta (29A·01): débito o crédito, la marca y el número de
/// aprobación. «Otra» marca abre un campo para escribirla.
class BloqueDeTarjeta extends StatelessWidget {
  const BloqueDeTarjeta({
    super.key,
    required this.credito,
    required this.alElegirTipo,
    required this.marca,
    required this.alElegirMarca,
    required this.marcaOtra,
    required this.alEscribir,
    required this.aprobacion,
    this.habilitado = true,
  });

  /// `true` = crédito, `false` = débito.
  final bool credito;
  final ValueChanged<bool> alElegirTipo;

  /// La marca elegida de los chips («Visa», «Otra»…), o `null` si no se eligió ninguna.
  final String? marca;
  final ValueChanged<String?> alElegirMarca;
  final TextEditingController marcaOtra;
  final VoidCallback alEscribir;
  final TextEditingController aprobacion;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentadoDeCobro(
          etiqueta: TextosMedioDeCobro.tipoDeTarjeta,
          opciones: const [TextosMedioDeCobro.debito, TextosMedioDeCobro.credito],
          elegida: credito ? 1 : 0,
          alElegir: (i) => alElegirTipo(i == 1),
          prefijoDeClave: 'cobro_tipo',
          habilitado: habilitado,
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: TextosMedioDeCobro.marca,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Text(TextosMedioDeCobro.marca, style: _estiloRotulo)),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                children: [
                  for (final texto in [...TextosMedioDeCobro.marcas, TextosMedioDeCobro.marcaOtra])
                    ChipDeVenta(
                      key: Key('cobro_marca_$texto'),
                      texto: texto,
                      elegido: marca == texto,
                      // Tocar la marca elegida la quita: es opcional. Mientras se guarda no responde.
                      alPresionar: habilitado
                          ? () => alElegirMarca(marca == texto ? null : texto)
                          : () {},
                    ),
                ],
              ),
            ],
          ),
        ),
        if (marca == TextosMedioDeCobro.marcaOtra) ...[
          const SizedBox(height: 4),
          CampoDeVenta(
            key: const Key('cobro_marca_otra'),
            rotulo: TextosMedioDeCobro.marcaOtraRotulo,
            controlador: marcaOtra,
            alCambiar: (_) => alEscribir(),
            hint: TextosMedioDeCobro.marcaOtraHint,
            maxLargo: RegistrarCobroUseCase.maximoMarca,
            habilitado: habilitado,
            autocorregir: false,
          ),
        ],
        const SizedBox(height: 12),
        CampoDeVenta(
          key: const Key('cobro_aprobacion'),
          rotulo: TextosMedioDeCobro.aprobacion,
          controlador: aprobacion,
          alCambiar: (_) => alEscribir(),
          hint: TextosMedioDeCobro.aprobacionHint,
          maxLargo: RegistrarCobroUseCase.maximoAprobacion,
          habilitado: habilitado,
          autocorregir: false,
        ),
      ],
    );
  }
}

/// Los datos opcionales del cobro por transferencia (29B·01): la referencia y el banco de origen.
class BloqueDeTransferencia extends StatelessWidget {
  const BloqueDeTransferencia({
    super.key,
    required this.referencia,
    required this.alEscribir,
    required this.banco,
    required this.alElegirBanco,
    this.habilitado = true,
  });

  final TextEditingController referencia;
  final VoidCallback alEscribir;

  /// El banco elegido o escrito, o `null` si no hay.
  final String? banco;

  /// `null` = no responde (se está registrando).
  final VoidCallback? alElegirBanco;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CampoDeVenta(
          key: const Key('cobro_referencia'),
          rotulo: TextosMedioDeCobro.referencia,
          controlador: referencia,
          alCambiar: (_) => alEscribir(),
          hint: TextosMedioDeCobro.referenciaHint,
          maxLargo: RegistrarCobroUseCase.maximoReferencia,
          habilitado: habilitado,
          autocorregir: false,
        ),
        const SizedBox(height: 12),
        CampoDeBancoDeOrigen(banco: banco, alElegir: alElegirBanco),
      ],
    );
  }
}

/// El campo «BANCO DE ORIGEN»: muestra el elegido (o «Elegir banco») y abre la hoja del banco.
class CampoDeBancoDeOrigen extends StatelessWidget {
  const CampoDeBancoDeOrigen({super.key, required this.banco, required this.alElegir});

  final String? banco;

  /// `null` = el campo no responde (se está registrando).
  final VoidCallback? alElegir;

  @override
  Widget build(BuildContext context) {
    final habilitado = alElegir != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: ExcludeSemantics(child: Text(TextosMedioDeCobro.banco, style: _estiloRotulo)),
        ),
        Semantics(
          button: true,
          enabled: habilitado,
          label: '${TextosMedioDeCobro.banco}: ${banco ?? TextosMedioDeCobro.bancoHint}',
          excludeSemantics: true,
          onTap: alElegir,
          child: InkWell(
            key: const Key('cobro_banco'),
            onTap: alElegir,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borde, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      banco ?? TextosMedioDeCobro.bancoHint,
                      style: TextStyle(
                        fontSize: 16,
                        color: banco == null ? ColoresAgenda.gris : ColoresAgenda.tinta,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_drop_down,
                    color: habilitado ? ColoresAgenda.azul : ColoresAgenda.gris,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La hoja «Banco de origen» (29B·02): BROU, Itaú, Santander, Scotiabank, BBVA y «Otro», que abre un
/// campo para escribirlo. Devuelve el banco al tocar «Listo» (`''` si no quedó ninguno elegido), o
/// `null` si se la cierra sin confirmar (no cambia nada). [actual] es el banco que ya había: si no es
/// de la lista, la hoja abre en «Otro» con ese texto.
Future<String?> mostrarHojaBancoDeOrigen(BuildContext context, {String? actual}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: _formaHoja,
      builder: (_) => HojaBancoDeOrigen(actual: actual),
    );

class HojaBancoDeOrigen extends StatefulWidget {
  const HojaBancoDeOrigen({super.key, this.actual});

  final String? actual;

  @override
  State<HojaBancoDeOrigen> createState() => _HojaBancoDeOrigenState();
}

class _HojaBancoDeOrigenState extends State<HojaBancoDeOrigen> {
  late String? _elegido;
  late final TextEditingController _otro;

  @override
  void initState() {
    super.initState();
    final actual = widget.actual;
    if (actual == null) {
      _elegido = null;
      _otro = TextEditingController();
    } else if (TextosMedioDeCobro.bancos.contains(actual)) {
      _elegido = actual;
      _otro = TextEditingController();
    } else {
      _elegido = TextosMedioDeCobro.bancoOtro;
      _otro = TextEditingController(text: actual == TextosMedioDeCobro.bancoOtro ? '' : actual);
    }
  }

  @override
  void dispose() {
    _otro.dispose();
    super.dispose();
  }

  /// El banco que queda al tocar «Listo»: el de la lista, lo escrito en «Otro» o, si no escribió nada,
  /// el propio «Otro» (no se pierde que fue otro banco). `''` si no eligió ninguno.
  String get _resultado {
    final elegido = _elegido;
    if (elegido == null) return '';
    if (elegido != TextosMedioDeCobro.bancoOtro) return elegido;
    return RegistrarCobroUseCase.limpiar(_otro.text) ?? TextosMedioDeCobro.bancoOtro;
  }

  void _elegir(String banco) => setState(() {
    // Tocar el elegido otra vez lo quita: el banco es opcional.
    _elegido = _elegido == banco ? null : banco;
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosMedioDeCobro.hojaBancoTitulo,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: TextosMedioDeCobro.elegirUnBanco,
              child: Column(
                children: [
                  for (final banco in [...TextosMedioDeCobro.bancos, TextosMedioDeCobro.bancoOtro])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilaElegible(
                        key: Key('cobro_banco_$banco'),
                        titulo: banco,
                        elegida: _elegido == banco,
                        alPresionar: () => _elegir(banco),
                      ),
                    ),
                ],
              ),
            ),
            if (_elegido == TextosMedioDeCobro.bancoOtro) ...[
              CampoDeVenta(
                key: const Key('cobro_banco_otro'),
                rotulo: TextosMedioDeCobro.bancoOtroRotulo,
                controlador: _otro,
                alCambiar: (_) => setState(() {}),
                hint: TextosMedioDeCobro.bancoOtroHint,
                maxLargo: RegistrarCobroUseCase.maximoBanco,
                autocorregir: false,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('cobro_banco_listo'),
              onPressed: () => Navigator.of(context).pop(_resultado),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosMedioDeCobro.listo,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
