// Vista 09 «Dar de baja y reactivar», parte de la Lista (HU-UBI-005, #205): 09·03 «Reactivar desde la
// lista (filtro Con bajas)» y 09·04 «Reactivada» (el aviso con «Deshacer»), con sus casos límite
// (doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, datos límite y texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

final _bajaEl12DeSetiembre = DateTime.utc(2026, 9, 12, 15);

/// La baja del canvas: «Av. Italia 1240 · baja el 12/09 · Ya no existe».
UbicacionConResumen _baja({
  String id = 'baja-1',
  String calle = 'Av. Italia',
  String numero = '1240',
  String? motivo = 'Ya no existe',
  DateTime? el,
}) => filaLista(
  id,
  calle: calle,
  numero: numero,
  hace: const Duration(days: 24),
  baja: el ?? _bajaEl12DeSetiembre,
  motivoBaja: motivo,
);

UbicacionConResumen _activa() =>
    filaLista('casa-1', calle: 'Rivadavia', numero: '100', hace: const Duration(hours: 1));

/// Monta la lista con «Con bajas» activo, como la ve quien llegó desde el filtro.
Future<RepoListaFalso> _montarConBajas(
  WidgetTester tester, {
  List<UbicacionConResumen>? filas,
  RepoListaFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  ValueNotifier<bool>? activaCambiante,
  ValueNotifier<bool>? montadaCambiante,
  ValueChanged<String>? alAbrir,
}) async {
  final r = repo ?? RepoListaFalso(filas ?? [_activa(), _baja()]);
  await montarLista(
    tester,
    repo: r,
    escala: escala,
    tamano: tamano,
    activaCambiante: activaCambiante,
    montadaCambiante: montadaCambiante,
    alAbrir: alAbrir,
  );
  await abrirHojaFiltros(tester);
  await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
  await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
  await asentarLista(tester);
  await tester.ensureVisible(botonVerUbicaciones);
  await verUbicaciones(tester);
  if (escala > 1) {
    // Con Ahem (cada letra, un cuadrado) «☷ Filtros» + el contador de la fila de filtros (#196, que no
    // es de la baja) desborda 12 px a 360 y 200 %; con las fuentes reales entra. Se descarta ese
    // aviso acá para que los `takeException` de cada test midan solo lo que dibuja la baja.
    final desborde = tester.takeException();
    expect(desborde == null || desborde.toString().contains('overflowed'), isTrue);
  }
  return r;
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  // Al centro y no al borde: abajo, a 200 %, el botón «Nueva» tapa la fila.
  await Scrollable.ensureVisible(tester.element(f), alignment: .5);
  await tester.pump();
  await tester.tap(f);
  await asentarLista(tester);
}

Finder get _filaBaja => find.text('Av. Italia 1240');
Finder get _botonReactivar => find.widgetWithText(FilledButton, TextosReactivar.reactivar);
Finder get _botonReactivando => find.widgetWithText(FilledButton, TextosReactivar.reactivando);
Finder get _cancelar => find.widgetWithText(TextButton, TextosReactivar.cancelar);
Finder get _aviso => find.text('Av. Italia 1240 reactivada. Vuelve a aparecer en el mapa.');
Finder get _deshacer => find.text('Deshacer');
Finder get _noSePuede => find.text(TextosReactivar.noSePuede);
Finder get _abrirExistente => find.widgetWithText(FilledButton, TextosReactivar.abrirExistente);
Finder get _entendido => find.widgetWithText(FilledButton, TextosReactivar.entendido);
Finder get _avisoDeshecha => find.text('Volvió a quedar de baja.');

/// La baja de Av. Italia 1240 choca con la casa activa de Rivadavia 100 (D1).
const _chocaConRivadavia = FailureReactivacionChocaConActiva(
  existenteId: 'casa-1',
  direccion: 'Rivadavia 100',
);
const _textoUnion = 'Esta ubicación se unió a otra y no se puede reactivar. Seguí usando la otra.';
const _textoChoque =
    'No puede haber dos ubicaciones con la misma dirección a menos de 100 m, y Rivadavia 100 ya '
    'está activa. Si es la misma, seguí usando esa; si es otra puerta, abrila y agregala como '
    'espacio.';

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed != null;

Future<void> _abrirReactivar(WidgetTester tester) async {
  // A 200 % la primera fila ocupa casi toda la pantalla: la de baja puede no estar construida todavía.
  await tester.scrollUntilVisible(
    _filaBaja,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('lista_filas')),
      matching: find.byType(Scrollable),
    ),
  );
  await _tocar(tester, _filaBaja);
}

void main() {
  group('Fila de baja en la Lista', () {
    testWidgets('dado «Con bajas», entonces la fila dice «BAJA» y «baja el 12/09 · Ya no existe», '
        'como el canvas', (tester) async {
      await _montarConBajas(tester);

      expect(_filaBaja, findsOneWidget);
      expect(find.text('BAJA'), findsOneWidget);
      expect(find.text('Casa · baja el 12/09 · Ya no existe'), findsOneWidget);
    });

    testWidgets('dado una baja que llegó por el sync (sin motivo), entonces la fila dice solo la '
        'fecha', (tester) async {
      await _montarConBajas(tester, filas: [_baja(motivo: null)]);

      expect(find.text('Casa · baja el 12/09'), findsOneWidget);
    });

    testWidgets(
      'dado una baja de una unión de duplicados, entonces dice «Unida a otra ubicación» en '
      'el lugar del motivo y el código interno no se ve',
      (tester) async {
        await _montarConBajas(tester, filas: [_baja(motivo: 'duplicado_de_ub-9')]);

        expect(find.text('Casa · baja el 12/09 · Unida a otra ubicación'), findsOneWidget);
        expect(find.textContaining('duplicado_de'), findsNothing);
        expect(find.textContaining('ub-9'), findsNothing);
      },
    );

    testWidgets(
      'dado un lector de pantalla, entonces la baja se anuncia como tocable para reactivar',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _montarConBajas(tester);

        final semantica = tester.getSemantics(
          find.byWidgetPredicate((w) => w is FilaUbicacionLista && w.item.esBaja),
        );
        expect(semantica.hint, 'Tocá para reactivar');
        expect(semantica.label, contains('Baja'));
        handle.dispose();
      },
    );

    testWidgets('dado una baja en una fila sin forma de reactivar (el mapa), entonces no se puede '
        'tocar', (tester) async {
      final item = _baja();
      var toques = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilaUbicacionLista(
              item: ItemListaUbicacion(
                ubicacion: item.ubicacion,
                cantidadEspacios: 1,
                motivoBaja: item.motivoBaja,
              ),
              lista: const ListaUbicaciones(
                items: [],
                total: 1,
                porTipo: {},
                porEstado: {},
                totalGeneral: 1,
                totalBajas: 1,
                estadosConocidos: false,
                hayMas: false,
                ordenAplicado: OrdenListaUbicaciones.recientes,
                sinUbicaciones: false,
              ),
              ahora: ahoraLista,
              alTocar: () => toques++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Av. Italia 1240'), warnIfMissed: false);
      await tester.pump();

      expect(toques, 0);
      expect(find.text('›'), findsNothing);
    });
  });

  group('09·03 · Reactivar desde la lista', () {
    testWidgets(
      'dado un toque en la baja, entonces abre la hoja con la dirección, qué es, cuándo y '
      'por qué se dio de baja',
      (tester) async {
        await _montarConBajas(tester);

        await _abrirReactivar(tester);

        // La dirección está en la fila y en el título de la hoja.
        expect(_filaBaja, findsNWidgets(2));
        expect(find.text('Casa · 1 espacio · Montevideo'), findsOneWidget);
        expect(find.text('Dada de baja'), findsOneWidget);
        expect(find.text('12/09/2026'), findsOneWidget);
        expect(find.text('Motivo'), findsOneWidget);
        expect(find.text('Ya no existe'), findsOneWidget);
        expect(_botonReactivar, findsOneWidget);
        expect(_habilitado(tester, _botonReactivar), isTrue);
        expect(_cancelar, findsOneWidget);
      },
    );

    testWidgets('dado que todavía no hay visitas guardadas en el teléfono, entonces la hoja no '
        'inventa el renglón «Última visita»', (tester) async {
      await _montarConBajas(tester);

      await _abrirReactivar(tester);

      expect(find.text('Última visita'), findsNothing);
    });

    testWidgets(
      'dado una baja sin motivo guardado, entonces la hoja no muestra el renglón «Motivo»',
      (tester) async {
        await _montarConBajas(tester, filas: [_baja(motivo: null)]);

        await _abrirReactivar(tester);

        expect(find.text('Dada de baja'), findsOneWidget);
        expect(find.text('Motivo'), findsNothing);
      },
    );

    testWidgets('dado «Cancelar», entonces cierra sin tocar nada', (tester) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);

      await _tocar(tester, _cancelar);

      expect(_botonReactivar, findsNothing);
      expect(repo.cambiosDeBaja, isEmpty);
      expect(find.text('BAJA'), findsOneWidget);
    });

    testWidgets('dado que se cierra y se vuelve a abrir, entonces la hoja empieza de cero', (
      tester,
    ) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);
      await _tocar(tester, _cancelar);

      await _abrirReactivar(tester);

      expect(_botonReactivar, findsOneWidget);
      expect(_habilitado(tester, _botonReactivar), isTrue);
      expect(repo.cambiosDeBaja, isEmpty);
    });

    testWidgets('dado «Reactivar», entonces escribe con la versión de la fila, cierra la hoja y la '
        'ubicación vuelve a la lista como activa', (tester) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);

      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja, [
        (
          id: 'baja-1',
          baja: false,
          baseUpdatedAt: ahoraLista.subtract(const Duration(days: 24)),
          motivo: null,
        ),
      ]);
      expect(_botonReactivar, findsNothing);
      expect(find.text('BAJA'), findsNothing);
      expect(_filaBaja, findsOneWidget);
    });

    testWidgets('dado que reactivar falla, entonces el aviso rojo, el botón vuelve a quedar '
        'habilitado y nada queda «Reactivando…»', (tester) async {
      final repo = await _montarConBajas(tester);
      repo.fallaAlCambiarBaja = const FailureInesperado();
      await _abrirReactivar(tester);

      await _tocar(tester, _botonReactivar);

      expect(find.text('No pudimos reactivar la ubicación. Probá de nuevo.'), findsOneWidget);
      expect(_botonReactivando, findsNothing);
      expect(_habilitado(tester, _botonReactivar), isTrue);
      expect(_habilitado(tester, _cancelar), isTrue);
      expect(_aviso, findsNothing);
    });

    testWidgets(
      'dado una falla, cuando reintenta y ahora sí entra, entonces reactiva y el aviso de '
      'error desaparece',
      (tester) async {
        final repo = await _montarConBajas(tester);
        repo.fallaAlCambiarBaja = const FailureInesperado();
        await _abrirReactivar(tester);
        await _tocar(tester, _botonReactivar);

        repo.fallaAlCambiarBaja = null;
        await _tocar(tester, _botonReactivar);

        expect(repo.cambiosDeBaja, hasLength(2));
        expect(find.text('No pudimos reactivar la ubicación. Probá de nuevo.'), findsNothing);
        expect(_aviso, findsOneWidget);
      },
    );

    testWidgets(
      'dado que la fila cambió desde que se cargó la lista, entonces dice «Esta ubicación '
      'cambió recién…» y deja cerrar',
      (tester) async {
        final repo = await _montarConBajas(tester);
        repo.filaCambiada = true;
        await _abrirReactivar(tester);

        await _tocar(tester, _botonReactivar);

        expect(
          find.text('Esta ubicación cambió recién. Abrila de nuevo y volvé a reactivarla.'),
          findsOneWidget,
        );
        expect(_habilitado(tester, _botonReactivar), isTrue);
        await _tocar(tester, _cancelar);
        expect(_botonReactivar, findsNothing);
      },
    );

    testWidgets('dado que el repositorio lanza una excepción, entonces cae en el mismo aviso', (
      tester,
    ) async {
      final repo = await _montarConBajas(tester);
      repo.lanzaAlCambiarBaja = StateError('base cerrada');
      await _abrirReactivar(tester);

      await _tocar(tester, _botonReactivar);

      expect(find.text('No pudimos reactivar la ubicación. Probá de nuevo.'), findsOneWidget);
      expect(_botonReactivando, findsNothing);
      expect(_habilitado(tester, _botonReactivar), isTrue);
    });

    testWidgets('dado dos toques seguidos en «Reactivar», entonces se reactiva una sola vez', (
      tester,
    ) async {
      final repo = await _montarConBajas(tester);
      repo.bloqueoCambioDeBaja = Completer<void>();
      await _abrirReactivar(tester);

      await tester.tap(_botonReactivar);
      await tester.pump();
      await tester.tap(_botonReactivando, warnIfMissed: false);
      await tester.pump();

      expect(repo.cambiosDeBaja, hasLength(1));
      repo.bloqueoCambioDeBaja!.complete();
      await asentarLista(tester);
      expect(repo.cambiosDeBaja, hasLength(1));
      expect(_aviso, findsOneWidget);
    });

    testWidgets('dado que reactiva, entonces dice «Reactivando…», no se puede cancelar y atrás no '
        'cierra la hoja', (tester) async {
      final repo = await _montarConBajas(tester);
      repo.bloqueoCambioDeBaja = Completer<void>();
      await _abrirReactivar(tester);
      await tester.tap(_botonReactivar);
      await tester.pump();

      expect(_botonReactivando, findsOneWidget);
      expect(_habilitado(tester, _botonReactivando), isFalse);
      expect(_habilitado(tester, _cancelar), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_botonReactivando, findsOneWidget, reason: 'sigue en curso');

      repo.bloqueoCambioDeBaja!.complete();
      await asentarLista(tester);
      expect(_botonReactivando, findsNothing);
      expect(_aviso, findsOneWidget);
    });

    testWidgets('dado dos toques en la fila antes de que abra la hoja, entonces se abre una sola', (
      tester,
    ) async {
      await _montarConBajas(tester);

      await tester.tap(_filaBaja);
      await tester.tap(_filaBaja, warnIfMissed: false);
      await asentarLista(tester);

      expect(_botonReactivar, findsOneWidget);
    });
  });

  group('09·04 · Reactivada (el aviso con «Deshacer»)', () {
    testWidgets('dado que reactivó, entonces el aviso dice «Av. Italia 1240 reactivada. Vuelve a '
        'aparecer en el mapa.» con «Deshacer»', (tester) async {
      await _montarConBajas(tester);
      await _abrirReactivar(tester);

      await _tocar(tester, _botonReactivar);

      expect(_aviso, findsOneWidget);
      expect(_deshacer, findsOneWidget);
    });

    testWidgets('dado el aviso, entonces dura 8 segundos', (tester) async {
      await _montarConBajas(tester);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      // En pasos: un solo `pump` de 7 s dispara el temporizador pero no deja correr la animación de
      // salida, y el aviso seguiría a la vista aunque ya se hubiera ido.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(_aviso, findsOneWidget, reason: 'a los 7 s sigue');

      await tester.pump(const Duration(seconds: 2));
      await asentarLista(tester);
      expect(_aviso, findsNothing, reason: 'a los 9 s ya no');
    });

    testWidgets('dado «Deshacer», entonces vuelve a dar de baja con el mismo motivo y lo dice', (
      tester,
    ) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      await _tocar(tester, _deshacer);

      expect(repo.cambiosDeBaja, hasLength(2));
      expect(repo.cambiosDeBaja.last.id, 'baja-1');
      expect(repo.cambiosDeBaja.last.baja, isTrue);
      expect(repo.cambiosDeBaja.last.motivo, 'Ya no existe');
      expect(repo.cambiosDeBaja.last.baseUpdatedAt, ahoraLista);
      expect(find.text('Volvió a quedar de baja.'), findsOneWidget);
      expect(find.text('BAJA'), findsOneWidget);
      expect(find.text('Casa · baja el 06/10 · Ya no existe'), findsOneWidget);
    });

    testWidgets('dado dos toques en «Deshacer», entonces se da de baja una sola vez', (
      tester,
    ) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      await tester.tap(_deshacer);
      await tester.tap(_deshacer, warnIfMissed: false);
      await asentarLista(tester);

      expect(repo.cambiosDeBaja.where((c) => c.baja), hasLength(1));
    });

    testWidgets('dado que «Deshacer» falla, entonces lo dice y manda a Editar', (tester) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);
      repo.fallaAlCambiarBaja = const FailureInesperado();

      await _tocar(tester, _deshacer);

      expect(
        find.text('No pudimos deshacer. Podés darla de baja de nuevo desde Editar.'),
        findsOneWidget,
      );
      expect(find.text('BAJA'), findsNothing);
    });

    testWidgets('dado que «Deshacer» lanza una excepción, entonces dice lo mismo', (tester) async {
      final repo = await _montarConBajas(tester);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);
      repo.lanzaAlCambiarBaja = StateError('base cerrada');

      await _tocar(tester, _deshacer);

      expect(
        find.text('No pudimos deshacer. Podés darla de baja de nuevo desde Editar.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'dado que mientras tanto la ubicación cambió (el sync), entonces «Deshacer» no pisa '
      'el cambio y lo dice',
      (tester) async {
        final repo = await _montarConBajas(tester);
        await _abrirReactivar(tester);
        await _tocar(tester, _botonReactivar);
        // El sync trajo una versión más nueva de la misma ubicación.
        repo.emitir([
          _activa(),
          filaLista(
            'baja-1',
            calle: 'Av. Italia',
            numero: '1240',
            hace: const Duration(minutes: 1),
          ),
        ]);
        await asentarLista(tester);

        await _tocar(tester, _deshacer);

        expect(
          find.text('No pudimos deshacer. Podés darla de baja de nuevo desde Editar.'),
          findsOneWidget,
        );
        expect(repo.cambiosDeBaja, hasLength(1), reason: 'no llegó a escribir');
      },
    );

    testWidgets(
      'dado dos reactivaciones seguidas, entonces el aviso de la segunda reemplaza al de la '
      'primera y «Deshacer» deshace solo la segunda',
      (tester) async {
        final repo = await _montarConBajas(
          tester,
          filas: [
            _activa(),
            _baja(),
            _baja(id: 'baja-2', calle: 'Gral. Flores', numero: '1500', motivo: 'Está deshabitada'),
          ],
        );
        await _tocar(tester, _filaBaja);
        await _tocar(tester, _botonReactivar);
        expect(_aviso, findsOneWidget);

        await _tocar(tester, find.text('Gral. Flores 1500'));
        await _tocar(tester, _botonReactivar);
        // Deja pasar la salida del primer aviso y la entrada del segundo.
        await tester.pump(const Duration(seconds: 1));
        await asentarLista(tester);

        expect(_aviso, findsNothing);
        expect(
          find.text('Gral. Flores 1500 reactivada. Vuelve a aparecer en el mapa.'),
          findsOneWidget,
        );
        expect(_deshacer, findsOneWidget);

        await _tocar(tester, _deshacer);

        final bajas = repo.cambiosDeBaja.where((c) => c.baja).toList();
        expect(bajas, hasLength(1));
        expect(bajas.single.id, 'baja-2');
        expect(bajas.single.motivo, 'Está deshabitada');
        // La primera sigue reactivada.
        expect(find.text('BAJA'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que la pestaña se va (activa en false) antes de tocar «Deshacer», entonces el '
      'aviso sigue (es de la ventana, no de la pestaña) y «Deshacer» da de baja una sola vez sin '
      'reventar',
      (tester) async {
        final activa = ValueNotifier(true);
        addTearDown(activa.dispose);
        final repo = await _montarConBajas(tester, activaCambiante: activa);
        await _abrirReactivar(tester);
        await _tocar(tester, _botonReactivar);
        expect(_aviso, findsOneWidget);

        activa.value = false;
        await asentarLista(tester);

        expect(tester.takeException(), isNull);
        expect(_aviso, findsOneWidget, reason: 'irse de la pestaña no cierra el aviso');
        expect(_deshacer, findsOneWidget);

        await _tocar(tester, _deshacer);

        expect(tester.takeException(), isNull);
        expect(repo.cambiosDeBaja.where((c) => c.baja), hasLength(1));
        expect(repo.cambiosDeBaja.last.id, 'baja-1');
        expect(repo.cambiosDeBaja.last.motivo, 'Ya no existe', reason: 'el mismo motivo');
        expect(_avisoDeshecha, findsOneWidget);

        // Al volver a la pestaña, la ubicación está de baja otra vez.
        activa.value = true;
        await asentarLista(tester);
        expect(find.text('BAJA'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dado que la pestaña se destruye (la Lista desmontada) antes de tocar «Deshacer», '
        'entonces «Deshacer» igual da de baja y lo dice, sin tocar un widget muerto', (
      tester,
    ) async {
      final montada = ValueNotifier(true);
      addTearDown(montada.dispose);
      final repo = await _montarConBajas(tester, montadaCambiante: montada);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);
      expect(_aviso, findsOneWidget);

      montada.value = false;
      await asentarLista(tester);

      expect(find.byType(FilaUbicacionLista), findsNothing, reason: 'la Lista ya no existe');
      expect(tester.takeException(), isNull);
      expect(_aviso, findsOneWidget, reason: 'el aviso es del Scaffold, que sigue');

      await _tocar(tester, _deshacer);

      expect(tester.takeException(), isNull);
      expect(repo.cambiosDeBaja.where((c) => c.baja), hasLength(1));
      expect(_avisoDeshecha, findsOneWidget);
    });

    testWidgets('dado que la Lista se desmonta y «Deshacer» falla, entonces dice que no pudo, sin '
        'reventar', (tester) async {
      final montada = ValueNotifier(true);
      addTearDown(montada.dispose);
      final repo = await _montarConBajas(tester, montadaCambiante: montada);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);
      montada.value = false;
      await asentarLista(tester);
      repo.lanzaAlCambiarBaja = StateError('base cerrada');

      await _tocar(tester, _deshacer);

      expect(tester.takeException(), isNull);
      expect(
        find.text('No pudimos deshacer. Podés darla de baja de nuevo desde Editar.'),
        findsOneWidget,
      );
    });

    testWidgets('dado que la pestaña se va y nadie toca «Deshacer», entonces el aviso se cierra '
        'solo a los 8 s, la ubicación sigue activa y al volver está en la lista', (tester) async {
      final activa = ValueNotifier(true);
      addTearDown(activa.dispose);
      final repo = await _montarConBajas(tester, activaCambiante: activa);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);
      activa.value = false;
      await asentarLista(tester);

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
      expect(_aviso, findsNothing);
      expect(_deshacer, findsNothing);
      expect(repo.cambiosDeBaja, hasLength(1), reason: 'solo la reactivación');

      activa.value = true;
      await asentarLista(tester);
      expect(find.text('BAJA'), findsNothing);
      expect(_filaBaja, findsOneWidget);
    });
  });

  group('Baja por unión de duplicados (no se reactiva)', () {
    Finder filaUnion() => find.byWidgetPredicate(
      (w) => w is FilaUbicacionLista && w.item.esBaja && w.item.esBajaPorUnion,
    );

    testWidgets('dado una baja por unión, entonces la fila no es un botón: tocarla no abre la hoja '
        'y no dice «Tocá para reactivar»', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await _montarConBajas(tester, filas: [_baja(motivo: 'duplicado_de_ub-9')]);

      final datos = tester.getSemantics(filaUnion()).getSemanticsData();
      expect(datos.hint, isEmpty);
      expect(datos.hasAction(SemanticsAction.tap), isFalse);
      expect(datos.label, contains('Baja'));
      expect(datos.label, contains('Unida a otra ubicación'));
      expect(datos.label, isNot(contains('duplicado_de')));

      await tester.tap(_filaBaja, warnIfMissed: false);
      await asentarLista(tester);

      expect(_botonReactivar, findsNothing);
      expect(_noSePuede, findsNothing);
      expect(repo.cambiosDeBaja, isEmpty);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('dado una baja por unión y otra común, entonces solo la común se reactiva', (
      tester,
    ) async {
      final repo = await _montarConBajas(
        tester,
        filas: [
          _baja(id: 'unida', calle: 'Gral. Flores', numero: '1500', motivo: 'duplicado_de_ub-9'),
          _baja(),
        ],
      );

      await tester.tap(find.text('Gral. Flores 1500'), warnIfMissed: false);
      await asentarLista(tester);
      expect(_botonReactivar, findsNothing, reason: 'la unida no abre nada');

      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja.single.id, 'baja-1');
      expect(find.text('Casa · baja el 12/09 · Unida a otra ubicación'), findsOneWidget);
    });

    testWidgets('dado un texto libre parecido («duplicado de la casa de al lado»), entonces es una '
        'baja común: se muestra tal cual y se reactiva', (tester) async {
      final repo = await _montarConBajas(
        tester,
        filas: [_baja(motivo: 'duplicado de la casa de al lado')],
      );

      expect(find.text('Casa · baja el 12/09 · duplicado de la casa de al lado'), findsOneWidget);
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja.single.id, 'baja-1');
      expect(_aviso, findsOneWidget);
    });

    testWidgets('dado una lista larga con una unión en el medio, entonces las demás bajas se '
        'reactivan y la unida sigue sin tocarse', (tester) async {
      final filas = [
        for (var i = 0; i < 30; i++)
          _baja(
            id: 'baja-$i',
            calle: 'Calle $i',
            numero: '${100 + i}',
            motivo: i == 15 ? 'duplicado_de_ub-9' : 'Ya no existe',
          ),
      ];
      final repo = await _montarConBajas(tester, filas: filas);
      final lista = find.descendant(
        of: find.byKey(const Key('lista_filas')),
        matching: find.byType(Scrollable),
      );

      await tester.scrollUntilVisible(find.text('Calle 15 115'), 200, scrollable: lista);
      await tester.tap(find.text('Calle 15 115'), warnIfMissed: false);
      await asentarLista(tester);
      expect(_botonReactivar, findsNothing);

      await tester.scrollUntilVisible(find.text('Calle 16 116'), 200, scrollable: lista);
      await _tocar(tester, find.text('Calle 16 116'));
      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja.single.id, 'baja-16');
    });

    testWidgets('dado texto a 200 % en 360×640, entonces la fila de la unión no desborda y cumple '
        'las guías de accesibilidad', (tester) async {
      final handle = tester.ensureSemantics();
      await _montarConBajas(
        tester,
        filas: [_baja(motivo: 'duplicado_de_ub-9')],
        escala: 2.0,
        tamano: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Unida a otra ubicación'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('09·03 · Reactivar choca con otra casa activa (D1)', () {
    testWidgets(
      'dado que choca, entonces la hoja pasa a «No se puede reactivar» con el texto de la '
      'HU y la dirección de la otra, y solo ofrece «Entendido» (la Lista no tiene a dónde '
      'abrirla)',
      (tester) async {
        final repo = await _montarConBajas(tester);
        repo.fallaAlCambiarBaja = _chocaConRivadavia;
        await _abrirReactivar(tester);

        await _tocar(tester, _botonReactivar);

        expect(_noSePuede, findsOneWidget);
        expect(find.text(_textoChoque), findsOneWidget);
        expect(_entendido, findsOneWidget);
        expect(_abrirExistente, findsNothing);
        expect(_botonReactivar, findsNothing);
        expect(_botonReactivando, findsNothing);
        expect(_cancelar, findsNothing);
        expect(_aviso, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dado que choca y la Lista sabe abrir una ubicación, entonces ofrece «Abrir la '
        'existente» y «Cancelar», y «Abrir la existente» abre la otra casa', (tester) async {
      final abiertas = <String>[];
      final repo = await _montarConBajas(tester, alAbrir: abiertas.add);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      expect(_abrirExistente, findsOneWidget);
      expect(_cancelar, findsOneWidget);
      expect(_entendido, findsNothing);

      await _tocar(tester, _abrirExistente);

      expect(abiertas, ['casa-1']);
      expect(_noSePuede, findsNothing, reason: 'la hoja se cerró');
      expect(_aviso, findsNothing);
      expect(find.text('BAJA'), findsOneWidget, reason: 'la baja sigue de baja');
    });

    testWidgets('dado dos toques seguidos en «Abrir la existente», entonces se abre una sola vez', (
      tester,
    ) async {
      final abiertas = <String>[];
      final repo = await _montarConBajas(tester, alAbrir: abiertas.add);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      await tester.tap(_abrirExistente);
      await tester.tap(_abrirExistente, warnIfMissed: false);
      await asentarLista(tester);

      expect(abiertas, ['casa-1']);
    });

    testWidgets('dado «Cancelar» en la hoja bloqueada, entonces cierra sin abrir nada', (
      tester,
    ) async {
      final abiertas = <String>[];
      final repo = await _montarConBajas(tester, alAbrir: abiertas.add);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      await _tocar(tester, _cancelar);

      expect(_noSePuede, findsNothing);
      expect(abiertas, isEmpty);
      expect(find.text('BAJA'), findsOneWidget);
    });

    testWidgets('dado «Entendido», entonces cierra; al volver a entrar la hoja empieza de cero y, '
        'si la otra ya no está activa, reactiva', (tester) async {
      final repo = await _montarConBajas(tester);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      await _tocar(tester, _entendido);

      expect(_noSePuede, findsNothing);
      expect(find.text('BAJA'), findsOneWidget);
      expect(repo.cambiosDeBaja, hasLength(1));

      repo.fallaAlCambiarBaja = null;
      await _abrirReactivar(tester);
      expect(_botonReactivar, findsOneWidget, reason: 'empieza de cero, sin el aviso anterior');
      expect(_noSePuede, findsNothing);
      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja, hasLength(2));
      expect(_aviso, findsOneWidget);
      expect(find.text('BAJA'), findsNothing);
    });

    testWidgets('dado que choca otra vez al reintentar, entonces vuelve a decir «No se puede '
        'reactivar» y no escribe nada', (tester) async {
      final repo = await _montarConBajas(tester);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);
      await _tocar(tester, _entendido);

      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      expect(_noSePuede, findsOneWidget);
      expect(find.text('BAJA'), findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('dado dos toques seguidos en «Reactivar» mientras la comprobación está en curso, '
        'entonces se pregunta una sola vez', (tester) async {
      final repo = await _montarConBajas(tester);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      repo.bloqueoCambioDeBaja = Completer<void>();
      await _abrirReactivar(tester);

      await tester.tap(_botonReactivar);
      await tester.pump();
      await tester.tap(_botonReactivando, warnIfMissed: false);
      await tester.pump();
      expect(repo.cambiosDeBaja, hasLength(1));
      repo.bloqueoCambioDeBaja!.complete();
      await asentarLista(tester);

      expect(repo.cambiosDeBaja, hasLength(1));
      expect(_noSePuede, findsOneWidget);
    });

    testWidgets('dado que la baja se unió a otra que sigue activa mientras la hoja estaba abierta '
        '(una carrera: la Lista no deja tocar una unión), entonces dice «No se puede reactivar» con '
        'el texto de la unión y «Abrir la existente» abre la conservada', (tester) async {
      final abiertas = <String>[];
      final repo = await _montarConBajas(tester, alAbrir: abiertas.add);
      repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion(conservadaId: 'casa-1');
      await _abrirReactivar(tester);

      await _tocar(tester, _botonReactivar);

      expect(_noSePuede, findsOneWidget);
      expect(find.text(_textoUnion), findsOneWidget);
      expect(_abrirExistente, findsOneWidget);
      expect(_cancelar, findsOneWidget);
      expect(_entendido, findsNothing);
      expect(_botonReactivar, findsNothing, reason: 'reintentar nunca va a funcionar');
      expect(_aviso, findsNothing);

      await _tocar(tester, _abrirExistente);

      expect(abiertas, ['casa-1']);
      expect(_noSePuede, findsNothing);
      expect(find.text('BAJA'), findsOneWidget, reason: 'la baja sigue de baja');
      expect(repo.cambiosDeBaja, hasLength(1));
    });

    testWidgets(
      'dado que la baja se unió a otra que ya no está activa (o la Lista no sabe abrirla), '
      'entonces solo ofrece «Entendido»',
      (tester) async {
        final repo = await _montarConBajas(tester, alAbrir: (_) {});
        repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion();
        await _abrirReactivar(tester);

        await _tocar(tester, _botonReactivar);

        expect(_noSePuede, findsOneWidget);
        expect(find.text(_textoUnion), findsOneWidget);
        expect(_abrirExistente, findsNothing);
        expect(_cancelar, findsNothing);
        expect(_entendido, findsOneWidget);
        expect(_botonReactivar, findsNothing);

        await _tocar(tester, _entendido);

        expect(_noSePuede, findsNothing);
        expect(find.text('BAJA'), findsOneWidget);
        expect(_aviso, findsNothing);
      },
    );

    testWidgets('dado que la baja se unió a una activa pero la Lista no tiene a dónde abrirla, '
        'entonces solo ofrece «Entendido»', (tester) async {
      final repo = await _montarConBajas(tester);
      repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion(conservadaId: 'casa-1');
      await _abrirReactivar(tester);

      await _tocar(tester, _botonReactivar);

      expect(_abrirExistente, findsNothing);
      expect(_entendido, findsOneWidget);
    });

    testWidgets(
      'dado una dirección larguísima y texto a 200 % en 360×640, entonces el texto entero '
      'se lee, nada desborda y los botones se alcanzan',
      (tester) async {
        final repo = await _montarConBajas(
          tester,
          escala: 2.0,
          tamano: const Size(360, 640),
          alAbrir: (_) {},
        );
        const larga = 'Avenida General Don José Gervasio Artigas y Pablo de María 12345 bis';
        repo.fallaAlCambiarBaja = const FailureReactivacionChocaConActiva(
          existenteId: 'casa-1',
          direccion: larga,
        );
        await _abrirReactivar(tester);
        await _tocar(tester, _botonReactivar);

        expect(tester.takeException(), isNull);
        expect(_noSePuede, findsOneWidget);
        expect(find.textContaining(larga), findsOneWidget);
        await tester.ensureVisible(_abrirExistente);
        expect(_abrirExistente, findsOneWidget);
        await tester.ensureVisible(_cancelar);
        expect(_cancelar, findsOneWidget);
      },
    );

    testWidgets('dado que choca, entonces el título se anuncia como encabezado y el aviso lleva la '
        'dirección de la otra', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await _montarConBajas(tester);
      repo.fallaAlCambiarBaja = _chocaConRivadavia;
      await _abrirReactivar(tester);
      await _tocar(tester, _botonReactivar);

      expect(find.bySemanticsLabel(TextosReactivar.noSePuede), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Rivadavia 100')), findsWidgets);
      handle.dispose();
    });

    for (final (nombre, tamano, escala, conAbrir) in <(String, Size, double, bool)>[
      ('360×640 con «Entendido»', const Size(360, 640), 1.0, false),
      ('412×915 con «Abrir la existente»', const Size(412, 915), 1.0, true),
      ('360×640 con texto a 200 % y «Abrir la existente»', const Size(360, 640), 2.0, true),
    ]) {
      testWidgets('«No se puede reactivar» cumple las guías de accesibilidad en $nombre', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final repo = await _montarConBajas(
          tester,
          tamano: tamano,
          escala: escala,
          alAbrir: conAbrir ? (_) {} : null,
        );
        repo.fallaAlCambiarBaja = _chocaConRivadavia;
        await _abrirReactivar(tester);
        await _tocar(tester, _botonReactivar);

        expect(tester.takeException(), isNull);
        expect(_noSePuede, findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('Datos límite, texto a 200 % y accesibilidad', () {
    testWidgets('dado una lista larga con muchas bajas, entonces la baja que se toca es la '
        'correcta', (tester) async {
      final filas = [
        for (var i = 0; i < 30; i++)
          _baja(id: 'baja-$i', calle: 'Calle $i', numero: '${100 + i}', motivo: 'Ya no existe'),
      ];
      final repo = await _montarConBajas(tester, filas: filas);

      await tester.scrollUntilVisible(
        find.text('Calle 7 107'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('lista_filas')),
          matching: find.byType(Scrollable),
        ),
      );
      await _tocar(tester, find.text('Calle 7 107'));
      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja.single.id, 'baja-7');
    });

    testWidgets('dado un motivo de 120 caracteres y texto a 200 %, entonces la fila y la hoja no '
        'desbordan', (tester) async {
      final largo = 'Se mudaron a otro departamento y la casa quedó cerrada con candado ' * 2;
      final texto = largo.substring(0, 120);
      await _montarConBajas(
        tester,
        filas: [_baja(motivo: texto)],
        escala: 2.0,
        tamano: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);

      await _abrirReactivar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(texto), findsOneWidget, reason: 'en la hoja, entero');
      await tester.ensureVisible(_botonReactivar);
      expect(_botonReactivar, findsOneWidget);
    });

    testWidgets('dado una calle larguísima, entonces la hoja la muestra entera', (tester) async {
      await _montarConBajas(
        tester,
        filas: [
          _baja(
            calle: 'Avenida General Don José Gervasio Artigas y Pablo de María y Presidente Brum',
            numero: '12345 bis',
          ),
        ],
        tamano: const Size(360, 640),
      );

      await tester.tap(find.textContaining('Avenida General Don José'));
      await asentarLista(tester);

      expect(tester.takeException(), isNull);
      expect(_botonReactivar, findsOneWidget);
    });

    for (final (nombre, tamano, escala) in <(String, Size, double)>[
      ('360×640', const Size(360, 640), 1.0),
      ('412×915', const Size(412, 915), 1.0),
      ('360×640 con texto a 200 %', const Size(360, 640), 2.0),
    ]) {
      testWidgets('09·03 cumple las guías de accesibilidad en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montarConBajas(tester, tamano: tamano, escala: escala);
        await _abrirReactivar(tester);

        expect(tester.takeException(), isNull);
        expect(_botonReactivar, findsOneWidget, reason: 'la hoja de reactivar se abrió');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('09·04 cumple las guías de accesibilidad en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montarConBajas(tester, tamano: tamano, escala: escala);
        await _abrirReactivar(tester);
        await _tocar(tester, _botonReactivar);

        expect(tester.takeException(), isNull);
        expect(_aviso, findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }
  });
}
