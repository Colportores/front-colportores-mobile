// «Mi plata» (vista 33C, HU-CTA-003, #172 y #431): un test por artboard (33C·01 a 33C·03), «Depositado»
// con lo validado y, aparte, lo que espera su validación, cargando y error (los de Mi Cuenta) y los
// casos límite de cada flujo: doble toque, ir y volver, la falla a mitad, las listas largas y el texto
// al 200 %.
import 'package:colportores_mobile/features/cuenta/domain/entities/detalle_de_mi_plata.dart';
import 'package:colportores_mobile/features/cuenta/presentation/widgets/piezas_mi_plata.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/totales_de_depositos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

/// Lo que el lector de pantalla dice de un elemento.
String _etiqueta(WidgetTester tester, Key llave) => tester.getSemantics(find.byKey(llave)).label;

Future<void> _tocar(WidgetTester tester, Key llave) async {
  await tester.tap(find.byKey(llave));
  await tester.pumpAndSettle();
}

/// Desplaza hasta que el centro de [llave] caiga dentro de la pantalla (con el texto grande un
/// widget puede estar construido pero fuera de la vista, y `dragUntilVisible` no lo trae) y lo toca.
Future<void> _verYTocar(WidgetTester tester, Key llave) async {
  final alto = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 80; i++) {
    final encontrado = find.byKey(llave);
    if (encontrado.evaluate().isNotEmpty) {
      final y = tester.getCenter(encontrado).dy;
      if (y > 0 && y < alto - 24) break;
    }
    await tester.drag(find.byKey(const Key('mi_plata_lista')), const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _tocar(tester, llave);
}

/// El detalle del canvas con «Depositado» a gusto del test.
DetalleDeMiPlata _conDepositos({
  List<DepositoDeLaLista> validados = const [],
  List<DepositoDeLaLista> porValidar = const [],
}) => DetalleDeMiPlata(
  depositado: DepositadoEnMiPlata(validados: validados, porValidar: porValidar),
  enManoCentavos: detalleDelCanvas.enManoCentavos,
  enMano: detalleDelCanvas.enMano,
  porCobrarCentavos: detalleDelCanvas.porCobrarCentavos,
  porCobrar: detalleDelCanvas.porCobrar,
);

void main() {
  group('33C·01 · En mano abierto', () {
    testWidgets('dado que toco «En mano» en Mi Cuenta, veo Mi plata con En mano desplegado: cada '
        'cobro con su cliente, su fecha y su monto', (tester) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      await _tocar(tester, const Key('cuenta_enMano'));

      expect(find.text('Mi plata'), findsOneWidget);
      expect(find.text('MI CUENTA'), findsOneWidget);
      expect(find.text(r'$ 2.400  ▴'), findsOneWidget);
      expect(find.text('María Fernández · 20/10'), findsOneWidget);
      expect(find.text(r'$ 600'), findsNWidgets(2));
      expect(find.text('Pedro Gómez · 21/10'), findsOneWidget);
      expect(find.text(r'$ 1.200'), findsOneWidget);
      expect(find.text('Ana Rodríguez · 23/10'), findsOneWidget);
      // «Por cobrar» está cerrada: su total, sin sus filas.
      expect(find.text(r'$ 9.700  ▾'), findsOneWidget);
      expect(find.text('Raúl Castro · desde 01/10'), findsNothing);
    });

    testWidgets('«Registrar depósito» y «Mis tickets» no se dibujan: esperan su pantalla', (
      tester,
    ) async {
      await montarMiPlata(tester, RepositorioDeDetalleControlable(inicial: detalleDelCanvas));

      for (final texto in ['Registrar depósito', 'Mis tickets']) {
        expect(find.textContaining(texto), findsNothing, reason: texto);
      }
      expect(find.textContaining('Próximamente'), findsNothing);
    });

    testWidgets('«Depositado» va primero, plegado, con su total (33C·01)', (tester) async {
      await montarMiPlata(tester, RepositorioDeDetalleControlable(inicial: detalleDelCanvas));

      expect(find.text(r'$ 26.900  ▾'), findsOneWidget);
      final depositado = tester.getTopLeft(find.byKey(const Key('mi_plata_categoria_depositado')));
      final enMano = tester.getTopLeft(find.byKey(const Key('mi_plata_categoria_enMano')));
      expect(depositado.dy, lessThan(enMano.dy));
      expect(find.text('Casa editora · Banco · 12/10'), findsNothing);
    });
  });

  group('33C·02 · Por cobrar abierto', () {
    testWidgets('dado que toco «Por cobrar» en Mi Cuenta, veo Mi plata con Por cobrar desplegado: '
        'cada cliente con desde cuándo y cuánto', (tester) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      await _tocar(tester, const Key('cuenta_porCobrar'));

      expect(find.text(r'$ 9.700  ▴'), findsOneWidget);
      expect(find.text('Raúl Castro · desde 01/10'), findsOneWidget);
      expect(find.text(r'$ 4.900'), findsOneWidget);
      expect(find.text('Laura Méndez · desde 08/10'), findsOneWidget);
      expect(find.text(r'$ 3.600'), findsOneWidget);
      expect(find.text('María Fernández · desde 12/10'), findsOneWidget);
      expect(find.text(r'$ 1.200'), findsOneWidget);
      expect(find.text(r'$ 2.400  ▾'), findsOneWidget);
      expect(find.text('María Fernández · 20/10'), findsNothing);
    });

    testWidgets('cada categoría se abre y se cierra con un toque, sin cerrar la otra', (
      tester,
    ) async {
      await montarMiPlata(tester, RepositorioDeDetalleControlable(inicial: detalleDelCanvas));
      expect(find.text('Ana Rodríguez · 23/10'), findsOneWidget);

      await _tocar(tester, const Key('mi_plata_categoria_porCobrar'));
      expect(find.text('Raúl Castro · desde 01/10'), findsOneWidget);
      expect(find.text('Ana Rodríguez · 23/10'), findsOneWidget);

      await _tocar(tester, const Key('mi_plata_categoria_enMano'));
      expect(find.text('Ana Rodríguez · 23/10'), findsNothing);
      expect(find.text('Raúl Castro · desde 01/10'), findsOneWidget);
    });
  });

  group('33C·03 · Nada en mano', () {
    testWidgets('dado que no tengo efectivo sin depositar, «En mano» abierto lo dice', (
      tester,
    ) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: DetalleDeMiPlata(
            enManoCentavos: 0,
            enMano: const [],
            porCobrarCentavos: 970000,
            porCobrar: detalleDelCanvas.porCobrar,
          ),
        ),
      );

      expect(find.text(r'$ 0  ▴'), findsOneWidget);
      expect(find.text('No tenés efectivo sin depositar.'), findsOneWidget);
    });

    testWidgets('«Por cobrar» sin nada también lo dice', (tester) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(inicial: DetalleDeMiPlata.vacio),
        abierta: CategoriaDeMiPlata.porCobrar,
      );

      expect(find.text('No tenés nada por cobrar.'), findsOneWidget);
    });
  });

  group('33C · Depositado abierto', () {
    testWidgets('dado que toco «Depositado» en Mi Cuenta, veo Mi plata con Depositado desplegado: '
        'cada depósito validado con para qué era, dónde, la fecha y el monto', (tester) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenConDepositado),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      await _tocar(tester, const Key('cuenta_depositado'));

      expect(find.text('Mi plata'), findsOneWidget);
      expect(find.text(r'$ 26.900  ▴'), findsOneWidget);
      expect(find.text('Casa editora · Banco · 12/10'), findsOneWidget);
      expect(find.text(r'$ 10.000'), findsOneWidget);
      expect(find.text('Casa editora · Oficina · 15/10'), findsOneWidget);
      expect(find.text(r'$ 9.000'), findsOneWidget);
      expect(find.text('Alquiler · Banco · 19/10'), findsOneWidget);
      expect(find.text(r'$ 7.900'), findsOneWidget);
      // Nada espera su validación: no hay aparte.
      expect(find.byKey(const Key('mi_plata_por_validar')), findsNothing);
      // «En mano» y «Por cobrar» quedan plegadas.
      expect(find.text(r'$ 2.400  ▾'), findsOneWidget);
      expect(find.text(r'$ 9.700  ▾'), findsOneWidget);
    });

    testWidgets('lo que espera su validación va aparte y no suma a la cifra', (tester) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: _conDepositos(
            validados: [depositoDe(10000, 12)],
            porValidar: [
              depositoDe(1800, 22, validado: false),
              depositoDe(
                500,
                23,
                validado: false,
                destino: DestinoDeDeposito.retiroCoordinador,
                concepto: ConceptoDeDeposito.alquiler,
              ),
            ],
          ),
        ),
        abierta: CategoriaDeMiPlata.depositado,
      );

      // La cifra es solo lo validado.
      expect(find.text(r'$ 10.000  ▴'), findsOneWidget);
      expect(find.text('Casa editora · Banco · 12/10'), findsOneWidget);
      // Aparte: el total de lo que espera, qué pasa con eso y cada depósito.
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
      expect(find.text('Por validar'), findsOneWidget);
      expect(find.text(r'$ 2.300'), findsOneWidget);
      expect(find.text('Suman a «Depositado» cuando tu coordinador los valide.'), findsOneWidget);
      expect(find.text('Casa editora · Banco · 22/10'), findsOneWidget);
      expect(find.text(r'$ 1.800'), findsOneWidget);
      expect(find.text('Alquiler · Retiro · 23/10'), findsOneWidget);
      expect(find.text(r'$ 500'), findsOneWidget);
      // Lo que espera va debajo de lo validado.
      final validado = tester.getTopLeft(find.byKey(const Key('mi_plata_fila_depositado_0')));
      final aparte = tester.getTopLeft(find.byKey(const Key('mi_plata_por_validar')));
      expect(aparte.dy, greaterThan(validado.dy));
    });

    testWidgets('si solo hay depósitos por validar, la cifra es cero y no dice que no hay '
        'depósitos', (tester) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: _conDepositos(porValidar: [depositoDe(1800, 22, validado: false)]),
        ),
        abierta: CategoriaDeMiPlata.depositado,
      );

      expect(find.text(r'$ 0  ▴'), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_vacio_depositado')), findsNothing);
      expect(find.text('Casa editora · Banco · 22/10'), findsOneWidget);
      // El total del aparte y la fila: el mismo monto dos veces.
      expect(find.text(r'$ 1.800'), findsNWidgets(2));
    });

    testWidgets('sin ningún depósito, dice que todavía no registró ninguno', (tester) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(inicial: _conDepositos()),
        abierta: CategoriaDeMiPlata.depositado,
      );

      expect(find.text(r'$ 0  ▴'), findsOneWidget);
      expect(find.text('Todavía no registraste ningún depósito.'), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsNothing);
    });

    testWidgets('mientras el teléfono no bajó nada del servidor, «Depositado» no se dibuja: ni un '
        'cero inventado', (tester) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: DetalleDeMiPlata(
            enManoCentavos: detalleDelCanvas.enManoCentavos,
            enMano: detalleDelCanvas.enMano,
            porCobrarCentavos: detalleDelCanvas.porCobrarCentavos,
            porCobrar: detalleDelCanvas.porCobrar,
          ),
        ),
      );

      expect(find.byKey(const Key('mi_plata_categoria_depositado')), findsNothing);
      expect(find.text('Depositado'), findsNothing);
      expect(find.text('En mano'), findsOneWidget);
    });

    testWidgets('cuando baja la validación de un depósito, pasa de «por validar» a lo validado sin '
        'recargar', (tester) async {
      final repo = RepositorioDeDetalleControlable(
        inicial: _conDepositos(
          validados: [depositoDe(10000, 12)],
          porValidar: [depositoDe(1800, 22, validado: false)],
        ),
      );
      await montarMiPlata(tester, repo, abierta: CategoriaDeMiPlata.depositado);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);

      repo.emitir(_conDepositos(validados: [depositoDe(10000, 12), depositoDe(1800, 22)]));
      await tester.pumpAndSettle();

      expect(find.text(r'$ 11.800  ▴'), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsNothing);
      expect(find.text('Casa editora · Banco · 22/10'), findsOneWidget);
    });

    testWidgets('el lector de pantalla lee cada depósito de una vez y el aparte con su aviso', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: _conDepositos(
            validados: [depositoDe(10000, 12)],
            porValidar: [depositoDe(1800, 22, validado: false)],
          ),
        ),
        abierta: CategoriaDeMiPlata.depositado,
      );

      expect(
        _etiqueta(tester, const Key('mi_plata_categoria_depositado')),
        r'Depositado, $ 10.000, desplegado',
      );
      expect(
        _etiqueta(tester, const Key('mi_plata_fila_depositado_0')),
        r'Casa editora · Banco · 12/10, $ 10.000',
      );
      expect(
        tester.getSemantics(find.text('Por validar')).label,
        r'Por validar, $ 1.800. Suman a «Depositado» cuando tu coordinador los valide.',
      );
      expect(
        _etiqueta(tester, const Key('mi_plata_fila_porValidar_0')),
        r'Casa editora · Banco · 22/10, $ 1.800',
      );
      manejador.dispose();
    });

    testWidgets('una lista larga de depósitos se arma de a poco y se alcanza desplazando', (
      tester,
    ) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: _conDepositos(
            validados: [for (var i = 0; i < 200; i++) depositoDe(100 + i, 1 + i % 28)],
            porValidar: [depositoDe(1800, 22, validado: false)],
          ),
        ),
        abierta: CategoriaDeMiPlata.depositado,
      );

      expect(find.byKey(const Key('mi_plata_fila_depositado_199')), findsNothing);
      await tester.dragUntilVisible(
        find.byKey(const Key('mi_plata_fila_porValidar_0')),
        find.byKey(const Key('mi_plata_lista')),
        const Offset(0, -600),
      );
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('cargando y error (los de Mi Cuenta)', () {
    testWidgets('mientras calcula, un bloque gris por tarjeta y ninguna cifra', (tester) async {
      await montarMiPlata(tester, RepositorioDeDetalleControlable());

      expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_esqueleto_porCobrar')), findsOneWidget);
      expect(find.text('En mano'), findsNothing);
      expect(find.text('Mi plata'), findsOneWidget);
    });

    testWidgets('si no se puede calcular, dice qué pasó y ofrece «Reintentar», sin ceros', (
      tester,
    ) async {
      await montarMiPlata(tester, RepositorioDeDetalleControlable()..fallaAlSuscribir = true);

      expect(find.text('No pudimos calcular tu cuenta.'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget);
      expect(find.textContaining(r'$ 0'), findsNothing);
    });

    testWidgets('«Reintentar» vuelve a calcular, y si vuelve a fallar el botón sigue disponible', (
      tester,
    ) async {
      final repo = RepositorioDeDetalleControlable()..fallaAlSuscribir = true;
      await montarMiPlata(tester, repo);

      await _tocar(tester, const Key('cuenta_reintentar'));
      expect(repo.suscripciones, 2);
      expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget);

      repo
        ..fallaAlSuscribir = false
        ..inicial = detalleDelCanvas;
      await _tocar(tester, const Key('cuenta_reintentar'));

      expect(repo.suscripciones, 3);
      expect(find.text('María Fernández · 20/10'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_reintentar')), findsNothing);
    });

    testWidgets('la falla después de los primeros datos también se dice: no sigue mostrando listas '
        'que ya no se sabe si están al día', (tester) async {
      final repo = RepositorioDeDetalleControlable(inicial: detalleDelCanvas);
      await montarMiPlata(tester, repo);
      expect(find.text('María Fernández · 20/10'), findsOneWidget);

      repo.fallar();
      await tester.pumpAndSettle();

      expect(find.text('No pudimos calcular tu cuenta.'), findsOneWidget);
      expect(find.text('María Fernández · 20/10'), findsNothing);
    });
  });

  group('entrar, volver y reentrar', () {
    testWidgets('el botón «Volver» y el atrás del sistema vuelven a Mi Cuenta', (tester) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      await _tocar(tester, const Key('cuenta_enMano'));
      await _tocar(tester, const Key('mi_plata_volver'));
      expect(find.text('Mi plata'), findsNothing);
      expect(find.text('Mi Cuenta'), findsOneWidget);

      await _tocar(tester, const Key('cuenta_porCobrar'));
      expect(find.text('Mi plata'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Mi plata'), findsNothing);
    });

    testWidgets('al reentrar llega con la categoría tocada y lo plegado vuelve a su lugar', (
      tester,
    ) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      await _tocar(tester, const Key('cuenta_enMano'));
      await _tocar(tester, const Key('mi_plata_categoria_porCobrar'));
      await _tocar(tester, const Key('mi_plata_volver'));
      await _tocar(tester, const Key('cuenta_porCobrar'));

      expect(find.text('Raúl Castro · desde 01/10'), findsOneWidget);
      expect(find.text('María Fernández · 20/10'), findsNothing);
    });

    testWidgets('dos toques seguidos en la tarjeta abren una sola vez Mi plata', (tester) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      await tester.tap(find.byKey(const Key('cuenta_enMano')));
      await tester.tap(find.byKey(const Key('cuenta_enMano')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Mi plata'), findsOneWidget);

      await _tocar(tester, const Key('mi_plata_volver'));

      // Un solo «atrás» alcanza: no quedó otra Mi plata debajo.
      expect(find.text('Mi plata'), findsNothing);
      expect(find.text('Mi Cuenta'), findsOneWidget);
    });

    testWidgets('después de volver se puede abrir otra vez: el toque no quedó trabado', (
      tester,
    ) async {
      await montarCuentaConDetalle(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
      );

      for (var i = 0; i < 3; i++) {
        await _tocar(tester, const Key('cuenta_enMano'));
        expect(find.text('Mi plata'), findsOneWidget);
        await _tocar(tester, const Key('mi_plata_volver'));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('una venta o un cobro nuevo cambia la lista abierta sin recargar', (tester) async {
      final repo = RepositorioDeDetalleControlable(inicial: detalleDelCanvas);
      await montarMiPlata(tester, repo);

      repo.emitir(
        DetalleDeMiPlata(
          enManoCentavos: 300000,
          enMano: [
            ...detalleDelCanvas.enMano,
            MovimientoEnMano(cliente: 'Lucía Silva', fecha: dia(24), centavos: 60000),
          ],
          porCobrarCentavos: detalleDelCanvas.porCobrarCentavos,
          porCobrar: detalleDelCanvas.porCobrar,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lucía Silva · 24/10'), findsOneWidget);
      expect(find.text(r'$ 3.000  ▴'), findsOneWidget);
    });
  });

  group('lo que lee el lector de pantalla', () {
    testWidgets('las categorías son botones que dicen su estado, y cada fila se lee de una vez', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarMiPlata(tester, RepositorioDeDetalleControlable(inicial: detalleDelCanvas));

      expect(
        _etiqueta(tester, const Key('mi_plata_categoria_enMano')),
        r'En mano, $ 2.400, desplegado',
      );
      expect(
        _etiqueta(tester, const Key('mi_plata_categoria_porCobrar')),
        r'Por cobrar, $ 9.700, plegado',
      );
      expect(
        _etiqueta(tester, const Key('mi_plata_categoria_depositado')),
        r'Depositado, $ 26.900, plegado',
      );
      expect(
        tester.getSemantics(find.byKey(const Key('mi_plata_categoria_enMano'))),
        isSemantics(isButton: true, hasTapAction: true, hasExpandedState: true, isExpanded: true),
      );
      expect(
        _etiqueta(tester, const Key('mi_plata_fila_enMano_1')),
        r'Pedro Gómez · 21/10, $ 1.200',
      );
      manejador.dispose();
    });

    testWidgets('el botón de volver tiene nombre y mide al menos 48 dp', (tester) async {
      final manejador = tester.ensureSemantics();
      await montarMiPlata(tester, RepositorioDeDetalleControlable(inicial: detalleDelCanvas));

      expect(find.byTooltip('Volver'), findsOneWidget);
      final tamano = tester.getSize(find.byKey(const Key('mi_plata_volver')));
      expect(tamano.width, greaterThanOrEqualTo(48));
      expect(tamano.height, greaterThanOrEqualTo(48));
      manejador.dispose();
    });
  });

  group('datos límite y texto grande', () {
    testWidgets('una lista larga se arma de a poco y la última fila se alcanza desplazando', (
      tester,
    ) async {
      final muchos = [
        for (var i = 0; i < 300; i++)
          SaldoDeCliente(cliente: 'Cliente $i', desde: dia(1), centavos: 100000 + i * 100),
      ];
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: DetalleDeMiPlata(
            enManoCentavos: 0,
            enMano: const [],
            porCobrarCentavos: muchos.fold<int>(0, (s, c) => s + c.centavos),
            porCobrar: muchos,
          ),
        ),
        abierta: CategoriaDeMiPlata.porCobrar,
      );

      expect(find.byKey(const Key('mi_plata_fila_porCobrar_299')), findsNothing);
      await tester.dragUntilVisible(
        find.byKey(const Key('mi_plata_fila_porCobrar_299')),
        find.byKey(const Key('mi_plata_lista')),
        const Offset(0, -600),
      );
      expect(find.text('Cliente 299 · desde 01/10'), findsOneWidget);
    });

    testWidgets('un nombre largo y un monto grande entran: el nombre baja de línea', (
      tester,
    ) async {
      await montarMiPlata(
        tester,
        RepositorioDeDetalleControlable(
          inicial: DetalleDeMiPlata(
            enManoCentavos: 99999999999,
            enMano: [
              MovimientoEnMano(
                cliente: 'María de los Ángeles Fernández de la Cuesta y Rodríguez',
                fecha: dia(20),
                centavos: 99999999999,
              ),
            ],
            porCobrarCentavos: 0,
            porCobrar: const [],
          ),
        ),
        escala: 2,
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('María de los Ángeles Fernández de la Cuesta y Rodríguez'),
        findsOneWidget,
      );
    });

    for (final tam in const {
      '320x568': Size(320, 568),
      '360x640': Size(360, 640),
      '412x915': Size(412, 915),
    }.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'a ${tam.key}, texto $escala: sin overflow, las tres categorías, el aparte «por validar» y las '
          'filas se alcanzan, y los toques miden 48 dp',
          (tester) async {
            final manejador = tester.ensureSemantics();
            final detalle = DetalleDeMiPlata(
              depositado: DepositadoEnMiPlata(
                validados: detalleDelCanvas.depositado!.validados,
                porValidar: [depositoDe(1800, 22, validado: false)],
              ),
              enManoCentavos: 240000,
              enMano: detalleDelCanvas.enMano,
              porCobrarCentavos: 970000,
              porCobrar: detalleDelCanvas.porCobrar,
            );
            await montarMiPlata(
              tester,
              RepositorioDeDetalleControlable(inicial: detalle),
              tamano: tam.value,
              escala: escala,
            );
            // Con el texto grande las últimas categorías quedan fuera de la pantalla: se llega
            // desplazando.
            await _verYTocar(tester, const Key('mi_plata_categoria_depositado'));
            await tester.dragUntilVisible(
              find.byKey(const Key('mi_plata_fila_porValidar_0')),
              find.byKey(const Key('mi_plata_lista')),
              const Offset(0, -200),
            );
            expect(find.text('Casa editora · Banco · 22/10'), findsOneWidget);
            await _verYTocar(tester, const Key('mi_plata_categoria_porCobrar'));

            expect(tester.takeException(), isNull);
            expect(find.text('Por cobrar'), findsOneWidget);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            manejador.dispose();
          },
        );
      }
    }
  });
}
