import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../depositos/presentation/pages/registrar_deposito_page.dart';
import '../../../depositos/presentation/providers/depositos_providers.dart'
    show ticketsDeDepositoRechazadosProvider, ticketsDeDepositoSinSubirProvider;
import '../../../depositos/presentation/widgets/aviso_tickets_sin_subir.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/resumen_de_cuenta.dart';
import '../providers/cuenta_providers.dart';
import '../providers/deuda_casa_providers.dart';
import '../textos_cuenta.dart';
import '../widgets/piezas_cuenta.dart';
import '../widgets/piezas_mi_plata.dart';
import '../widgets/tarjeta_de_deuda.dart';
import 'mi_plata_page.dart';

/// La pestaña «Cuenta» (vista 33A, HU-CTA-001): las cifras de la plata del colportor con cuánto
/// cambiaron contra la semana pasada.
///
/// Vive dentro de la pantalla principal (`IndexedStack`): [activa] dice si la pestaña está a la vista.
/// Todo sale del teléfono, así que sin conexión se ve igual (33A·02); el único dato que puede estar
/// viejo es «Depositado» (viene del servidor) y es el que el aviso nombra. Sin «Depositado» no hay
/// aviso: no hay nada viejo que decir. Mientras se calcula, un bloque gris por tarjeta
/// (33A·03); si la base no se puede leer, el error con «Reintentar» (33A·05), nunca ceros.
///
/// Son cuatro tarjetas: la deuda con la casa editora, Depositado, En mano y Por cobrar. «Depositado» suma
/// solo lo que el coordinador validó y baja del servidor por el pull: mientras el teléfono no bajó nada
/// no se dibuja (ni un cero), y sin conexión un aviso dice de cuándo es (33A·02). La deuda la cuenta el
/// servidor (HU-CTA-002): se muestra lo último que llegó y su toque abre el detalle por pedido (33B).
/// Las tres cifras se tocan y abren su detalle en «Mi plata» (HU-CTA-003, 33C). Debajo, «ACCIONES» con
/// «Registrar depósito» (HU-CTA-004, vista 33 D).
class CuentaPage extends ConsumerStatefulWidget {
  const CuentaPage({super.key, required this.colportorId, this.activa = true});

  /// UUID del colportor con la sesión iniciada: Mi Cuenta es «mi plata».
  final String colportorId;

  /// La pestaña está a la vista.
  final bool activa;

  @override
  ConsumerState<CuentaPage> createState() => _CuentaPageState();
}

class _CuentaPageState extends ConsumerState<CuentaPage> {
  /// Ya se está abriendo «Mi plata»: un segundo toque antes de que termine no abre otra encima.
  var _abriendo = false;

  Future<void> _abrir(TipoDeCifra tipo) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await MiPlataPage.abrir(
        context,
        colportorId: widget.colportorId,
        abierta: CategoriaDeMiPlata.de(tipo),
      );
    } finally {
      _abriendo = false;
    }
  }

  /// Ya se está abriendo «Registrar depósito».
  var _abriendoDeposito = false;

  Future<void> _registrarDeposito() async {
    if (_abriendoDeposito) return;
    _abriendoDeposito = true;
    try {
      await RegistrarDepositoPage.abrir(context, colportorId: widget.colportorId);
    } finally {
      _abriendoDeposito = false;
    }
  }

  @override
  void didUpdateWidget(CuentaPage anterior) {
    super.didUpdateWidget(anterior);
    // Al volver a la pestaña se vuelve a leer: «hace una semana» corre con el reloj aunque no haya
    // cambiado ninguna venta. Con el dato anterior a la vista, sin pasar por la carga. Después del
    // cuadro: invalidar un provider durante `didUpdateWidget` marca a quien lo mira en plena
    // construcción.
    if (widget.activa && !anterior.activa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.activa) {
          ref.invalidate(resumenDeCuentaProvider(widget.colportorId));
          // La deuda se vuelve a pedir al servidor; la última que llegó sigue a la vista mientras tanto.
          unawaited(ref.read(deudaConLaCasaProvider(widget.colportorId).notifier).actualizar());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = resumenDeCuentaProvider(widget.colportorId);
    final resumen = ref.watch(provider);

    final List<Widget> cuerpo;
    if (resumen.isLoading && !resumen.hasValue) {
      // También al tocar «Reintentar»: mientras vuelve a calcular no queda el error a la vista ni se
      // puede tocar dos veces.
      cuerpo = const [SliverToBoxAdapter(child: EsqueletoCuenta())];
    } else if (resumen.hasError) {
      cuerpo = [
        SliverToBoxAdapter(child: BannerErrorCuenta(alReintentar: () => ref.invalidate(provider))),
      ];
    } else {
      final datos = resumen.requireValue;
      final depositadoAl = datos.depositadoAl;
      final sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
      // La deuda guardada: su hora entra en el aviso, y si no se pudo actualizar se avisa.
      final deudaLeidaEn = ref.watch(
        deudaConLaCasaProvider(widget.colportorId).select((e) => e.lectura?.leidaEn),
      );
      final falloDeLaDeuda = ref.watch(
        deudaConLaCasaProvider(widget.colportorId).select((e) => e.fallo),
      );
      cuerpo = [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          // Las tarjetas son pocas: una columna y no una lista perezosa, así la segunda existe (y
          // la lee el lector de pantalla) aunque el texto grande la deje fuera de la pantalla.
          sliver: SliverToBoxAdapter(
            child: Column(
              spacing: 8,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sin conexión: el aviso sale si hay alguna hora guardada (la de «Depositado» o la de la
                // deuda) y las nombra. Con red, si la deuda no se pudo actualizar, lo guardado se ve con
                // su hora y un «Reintentar».
                if (sinConexion && (depositadoAl != null || deudaLeidaEn != null))
                  AvisoSinConexionCuenta(
                    texto: FormatoCuenta.sinConexion(
                      depositadoAl,
                      ref.read(relojCuentaProvider)(),
                      deudaLeidaEn: deudaLeidaEn,
                    ),
                  )
                else if (!sinConexion && deudaLeidaEn != null && falloDeLaDeuda != null)
                  BannerErrorCuenta(
                    margen: EdgeInsets.zero,
                    texto: FormatoCuenta.deudaSinActualizar(
                      deudaLeidaEn,
                      ref.read(relojCuentaProvider)(),
                    ),
                    alReintentar: () => unawaited(
                      ref.read(deudaConLaCasaProvider(widget.colportorId).notifier).actualizar(),
                    ),
                  ),
                // 38A-08: la foto de un ticket de depósito no pudo subir. Solo cuando pasa, para no
                // sumar un hueco a la columna.
                if ((ref.watch(ticketsDeDepositoSinSubirProvider).value ?? 0) > 0)
                  const AvisoDeTicketsSinSubir(),
                // La foto que ya no se puede reintentar (P1 del 10/11): avisarle al coordinador.
                if (ref.watch(ticketsDeDepositoRechazadosProvider).value?.isNotEmpty ?? false)
                  const AvisoDeTicketsRechazados(),
                TarjetaDeDeuda(colportorId: widget.colportorId),
                for (final tipo in TipoDeCifra.values)
                  if (_cifraDe(tipo, datos) case final cifra?)
                    TarjetaDeCifra(
                      key: Key('cuenta_${tipo.name}'),
                      tipo: tipo,
                      alAbrir: () => _abrir(tipo),
                      cifra: cifra,
                    ),
                AccionesDeCuenta(
                  acciones: [
                    AccionDeCuenta(
                      texto: TextosCuenta.registrarDeposito,
                      clave: const Key('cuenta_registrar_deposito'),
                      alTocar: () => unawaited(_registrarDeposito()),
                      // Con $ 0 en mano no hay qué depositar (como 33C·03, que no dibuja el botón).
                      apagadaPorque: datos.enMano.totalCentavos > 0
                          ? null
                          : TextosCuenta.sinPlataParaDepositar,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // Todo se desplaza junto: con el texto al 200 % el encabezado y las tarjetas ocupan casi la
    // pantalla y la segunda tiene que poder llegar a la vista.
    return CustomScrollView(
      key: const Key('cuenta_pestana'),
      slivers: [
        const SliverToBoxAdapter(child: CabeceraCuenta()),
        ...cuerpo,
      ],
    );
  }

  /// La cifra de cada tarjeta; `null` = no se dibuja («Depositado» antes de la primera bajada).
  static CifraDeCuenta? _cifraDe(TipoDeCifra tipo, ResumenDeCuenta datos) => switch (tipo) {
    TipoDeCifra.depositado => datos.depositado,
    TipoDeCifra.enMano => datos.enMano,
    TipoDeCifra.porCobrar => datos.porCobrar,
  };
}
