// Arnés de QA de la deuda con la casa editora (vista 33A·01 y 33B, #441): los estados del canvas
// armados de a uno, para recorrerlos en la matriz de tamaños y escalas, y el montaje de Mi Cuenta
// con la tarjeta de la deuda y la conexión a elección.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cuenta_arnes.dart';
import 'deuda_casa_arnes.dart';

/// Una conexión fija para Mi Cuenta.
final class QaConexion implements MonitorConectividad {
  QaConexion(this.tipo);
  final TipoConexion tipo;
  @override
  Future<TipoConexion> actual() async => tipo;
  @override
  Stream<TipoConexion> get cambios => const Stream.empty();
}

/// Los estados de 33B que se recorren en la matriz. Cada uno deja al repositorio como lo dejaría el
/// servidor en ese caso.
enum EstadoQa33B {
  conDeuda,
  sinDeuda,
  error,
  errorSinConexion,
  cargando,
  sinConexionConGuardada,
  servidorCaidoConGuardada,
  aFavor,
  saldosNoDanElTotal,
  hostil,
}

/// Los pedidos de los datos límite: nombres sin espacios, emoji, árabe, 11 cifras y un pedido sin
/// líneas.
DeudaConLaCasa deudaHostil() => deuda(
  total: 99999999999,
  suma: 99999999999,
  pedidos: [
    pedido(
      'h-1',
      DateTime.utc(2026, 1, 1, 3),
      monto: 99999999999,
      pagado: 0,
      lineas: [
        LineaDePedido(nombre: 'A' * 80, cantidad: 123456),
        const LineaDePedido(nombre: 'Revista 📚 «Vida Feliz» 🙏🏽', cantidad: 3),
        const LineaDePedido(nombre: 'كتاب الحياة السعيدة', cantidad: 2),
        const LineaDePedido(nombre: '   ', cantidad: 1),
      ],
    ),
    pedido('h-2', DateTime.utc(2026, 12, 31, 23, 59), monto: 1, pagado: 0),
  ],
);

/// Arma el repositorio de [estado] y lo deja en ese estado, ya pintado.
Future<RepositorioDeDeudaControlable> repoEnEstado(
  WidgetTester tester,
  EstadoQa33B estado,
  Future<void> Function(RepositorioDeDeudaControlable repo) montar,
) async {
  final ayer = DateTime(2026, 11, 3, 21);
  final repo = switch (estado) {
    EstadoQa33B.sinConexionConGuardada || EstadoQa33B.servidorCaidoConGuardada =>
      RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas, leidaEn: ayer)),
    _ => RepositorioDeDeudaControlable(),
  };
  await montar(repo);
  Future<void> asentar() async {
    await tester.pump();
    await tester.pump();
  }

  switch (estado) {
    case EstadoQa33B.cargando:
      break;
    case EstadoQa33B.conDeuda:
      repo.responder(lectura(deudaDelCanvas));
      await asentar();
    case EstadoQa33B.sinDeuda:
      repo.responder(lectura(deuda(total: 0)));
      await asentar();
    case EstadoQa33B.error:
      repo.fallar();
      await asentar();
    case EstadoQa33B.errorSinConexion:
      repo.fallar(const FailureDeudaSinConexion());
      await asentar();
    case EstadoQa33B.sinConexionConGuardada:
      repo.fallar(const FailureDeudaSinConexion());
      await asentar();
    case EstadoQa33B.servidorCaidoConGuardada:
      repo.fallar();
      await asentar();
    case EstadoQa33B.aFavor:
      repo.responder(lectura(deuda(total: -1200, suma: 0)));
      await asentar();
    case EstadoQa33B.saldosNoDanElTotal:
      repo.responder(
        lectura(
          deuda(
            total: 18400,
            suma: 15000,
            pedidos: [
              pedido(
                'p-1',
                DateTime.utc(2026, 10, 2, 15),
                monto: 15000,
                pagado: 0,
                lineas: const [LineaDePedido(nombre: 'Salud y Hogar', cantidad: 10)],
              ),
            ],
          ),
        ),
      );
      await asentar();
    case EstadoQa33B.hostil:
      repo.responder(lectura(deudaHostil()));
      await asentar();
  }
  return repo;
}

/// Los estados de Mi Cuenta (33A·01 con la tarjeta de la deuda) que se recorren.
enum EstadoQa33A { conDeuda, aFavor, sinDeuda, sinNadaLeido, sinConexion }

/// El resumen de Mi Cuenta con «Depositado» bajado el 29/10 a las 21:00.
ResumenDeCuenta resumenConDepositado441() => ResumenDeCuenta(
  depositado: cifra(26900, variacion: 5300),
  depositadoAl: DateTime(2026, 10, 29, 21),
  enMano: cifra(2400, variacion: 1800),
  porCobrar: cifra(9700, variacion: -1300),
);

/// Monta Mi Cuenta en [estado] y la deja pintada. Devuelve el repositorio de la deuda.
Future<RepositorioDeDeudaControlable> montarCuentaEnEstado(
  WidgetTester tester,
  EstadoQa33A estado, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  ResumenDeCuenta? resumen,
}) async {
  final repo = RepositorioDeDeudaControlable(
    guardada: estado == EstadoQa33A.sinConexion
        ? lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 21))
        : null,
  );
  await montarCuenta(
    tester,
    RepositorioDeCuentaControlable(inicial: resumen ?? resumenDelCanvas),
    tamano: tamano,
    escala: escala,
    overrides: [
      ...overridesDeDeuda(repo),
      monitorConectividadProvider.overrideWithValue(
        QaConexion(
          estado == EstadoQa33A.sinConexion ? TipoConexion.sinConexion : TipoConexion.wifi,
        ),
      ),
    ],
  );
  await tester.pump();
  switch (estado) {
    case EstadoQa33A.conDeuda:
      repo.responder(lectura(deudaDelCanvas));
    case EstadoQa33A.aFavor:
      repo.responder(lectura(deuda(total: -1200, suma: 0)));
    case EstadoQa33A.sinDeuda:
      repo.responder(lectura(deuda(total: 0)));
    case EstadoQa33A.sinNadaLeido:
      repo.fallar(const FailureDeudaSinConexion());
    case EstadoQa33A.sinConexion:
      repo.fallar(const FailureDeudaSinConexion());
  }
  await tester.pump();
  await tester.pump();
  return repo;
}

/// Carga las fuentes reales de `assets/fonts/` (sin esto `flutter_test` pinta cajas).
Future<void> cargarFuentesReales(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await c.load();
  }
});
