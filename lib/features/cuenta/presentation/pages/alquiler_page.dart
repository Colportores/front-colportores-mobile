import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../depositos/domain/entities/deposito.dart';
import '../../../depositos/presentation/pages/registrar_deposito_page.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/alquiler.dart';
import '../providers/cuenta_providers.dart';
import '../textos_alquiler.dart';
import '../widgets/piezas_alquiler.dart';
import '../widgets/piezas_cuenta.dart';

/// «Mi alquiler» (vista 38C, HU-CTA-007): lo que falta pagar de alquiler en cada campaña en la que el
/// colportor está inscripto, con el monto fijo, lo pagado y la lista de pagos. Se abre desde la línea
/// «Alquiler» de Mi Cuenta.
///
/// Es una deuda aparte de la de la casa editora y **no bloquea nada**. Todo sale del teléfono (el
/// monto de la campaña y los pagos bajan por el pull), así que se ve igual sin conexión (38C·05).
/// Estados:
/// - **Con deuda** (38C·01): «TE FALTA PAGAR», monto, pagado, pagos y «Cargar pago de alquiler».
/// - **Con un pago por validar** (38C·02): el aviso dice cuánto y que no baja hasta que lo valide el
///   coordinador.
/// - **Pagado** (38C·03): la cifra en verde y sin botón. Si se pagó de más, dice que el excedente bajó
///   la deuda con la casa editora (decisión «Alquiler fav», 28/10).
/// - **La campaña no cobra** (38C·04): si el monto se quita mientras la pantalla está abierta.
/// - **Sin conexión** (38C·05), **cargando** y **error** con «Reintentar» (el canvas no los dibuja).
///
/// Si se dio de baja de una campaña en la que pagó alquiler, esa campaña va después de las demás sin
/// saldo ni botón: dice lo que pagó y si lo pagado queda por decidir o qué decidió el coordinador (#740).
///
/// Si el colportor está en dos campañas, cada una tiene su propio bloque, con su saldo y su botón (el
/// alquiler se lleva por campaña: decisión «Alq. campaña», 25/10).
class AlquilerPage extends ConsumerStatefulWidget {
  const AlquilerPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada: el alquiler es «mi alquiler».
  final String colportorId;

  /// Abre «Mi alquiler» encima de lo que se esté viendo.
  static Future<void> abrir(BuildContext context, {required String colportorId}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'alquiler'),
          builder: (_) => AlquilerPage(colportorId: colportorId),
        ),
      );

  @override
  ConsumerState<AlquilerPage> createState() => _AlquilerPageState();
}

class _AlquilerPageState extends ConsumerState<AlquilerPage> {
  /// Ya se está abriendo «Registrar depósito»: un segundo toque antes de que termine no abre otra
  /// encima.
  var _abriendo = false;

  Future<void> _cargarPago(AlquilerDeCampania campania) async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    try {
      await RegistrarDepositoPage.abrir(
        context,
        colportorId: widget.colportorId,
        concepto: ConceptoDeDeposito.alquiler,
        campaniaId: campania.campaniaId,
      );
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = alquilerDelColportorProvider(widget.colportorId);
    final estado = ref.watch(provider);
    final ahora = ref.read(relojCuentaProvider)();
    final sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;

    final List<Widget> cuerpo;
    if (estado.hasValue) {
      final alquiler = estado.requireValue;
      cuerpo = [
        if (sinConexion)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: AvisoSinConexionCuenta(
                texto: TextosAlquiler.sinConexion(alquiler.bajadoEn, ahora),
              ),
            ),
          ),
        if (!alquiler.hayAlquiler)
          const SliverToBoxAdapter(child: SinAlquiler())
        else
          SliverList.builder(
            itemCount: alquiler.campanias.length + alquiler.bajas.length,
            itemBuilder: (_, i) => i < alquiler.campanias.length
                ? BloqueDeAlquiler(
                    indice: i,
                    alquiler: alquiler.campanias[i],
                    ahora: ahora,
                    conSeparador: i > 0,
                    alCargarPago: _abriendo
                        ? null
                        : () => unawaited(_cargarPago(alquiler.campanias[i])),
                  )
                : BloqueDeAlquilerDeBaja(
                    indice: i - alquiler.campanias.length,
                    baja: alquiler.bajas[i - alquiler.campanias.length],
                    ahora: ahora,
                    conSeparador: i > 0,
                  ),
          ),
      ];
    } else if (estado.isLoading) {
      // Cargando, también al tocar «Reintentar»: mientras vuelve a armar no queda el error a la vista
      // ni se puede tocar dos veces.
      cuerpo = const [SliverToBoxAdapter(child: EsqueletoAlquiler())];
    } else {
      // Sin nada que mostrar: el error con «Reintentar», nunca «no cobra alquiler».
      final falla = estado.error;
      cuerpo = [
        SliverToBoxAdapter(
          child: BannerErrorCuenta(
            texto: falla is Failure ? falla.mensaje : const FailureAlquilerNoDisponible().mensaje,
            alReintentar: () => ref.invalidate(provider),
          ),
        ),
      ];
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('alquiler_lista'),
          slivers: [
            SliverToBoxAdapter(
              child: CabeceraAlquiler(alVolver: () => Navigator.maybePop(context)),
            ),
            ...cuerpo,
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
