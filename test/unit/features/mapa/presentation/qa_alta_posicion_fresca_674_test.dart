// QA #674 (issue #670, decisión de Cristian del 05/11, «GPS viejo»): «la lectura vieja deja de
// existir». Decisión P2 del orquestador (comentario del PR #674): con el mapa en «libre» no hay
// stream, así que el alta y «Volver a mi ubicación» piden una lectura nueva al abrir; con
// seguimiento usan la posición viva. Acá se prueba lo que pasa en «libre» y en la ventana en que el
// stream recién se abrió.
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';
import '../../../../helpers/lista_ubicaciones_falsos.dart';
import '../../../../helpers/zonas_falsas.dart';

/// Donde estaba Ana cuando abrió el mapa (`puntoItalia`) y donde está ahora, a unos 400 m.
const _ahora = Coordenadas(lat: -34.8840, lon: -56.1302);

/// Los tests de un hallazgo se saltan con el motivo; `--dart-define=QA_HALLAZGOS=true` los corre.
Object _omitir(String motivo) => const bool.fromEnvironment('QA_HALLAZGOS') ? false : motivo;

LecturaGps _lectura(Coordenadas punto) => LecturaGps(coordenadas: punto, precisionMetros: 5);

final class _Banco {
  _Banco() : gps = GpsFalso() {
    contenedor = ProviderContainer(
      overrides: [
        ...overridesLista(repo: RepoListaFalso(), gps: gps),
        geocodificadorInversoProvider.overrideWithValue(GeocodificadorFalso()),
        ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
        esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
        generadorIdUbicacionProvider.overrideWithValue(() => 'id-1'),
      ],
    );
    addTearDown(contenedor.dispose);
    contenedor.listen(ubicacionColportorProvider, (_, _) {});
  }

  final GpsFalso gps;
  late final ProviderContainer contenedor;

  UbicacionColportorNotifier get ubicacion => contenedor.read(ubicacionColportorProvider.notifier);
  UbicacionColportorState get estado => contenedor.read(ubicacionColportorProvider);
  AltaUbicacionState get alta => contenedor.read(altaUbicacionProvider(parametrosAlta));
  AltaUbicacionNotifier get altaNotifier =>
      contenedor.read(altaUbicacionProvider(parametrosAlta).notifier);

  /// Ana abrió la pestaña Mapa: leyó el GPS una vez y el mapa está a la vista.
  Future<void> abrirElMapa() async {
    await ubicacion.alAbrirPestana();
    ubicacion.mapaALaVista(true);
    await pumpEventQueue();
  }

  void abrirAlta() => contenedor.listen(altaUbicacionProvider(parametrosAlta), (_, _) {});
}

void main() {
  group('«Mapa libre»: el alta no parte de una lectura vieja (P2, opción a)', () {
    test(
      'dado el mapa libre y Ana que caminó 400 m, cuando abre el alta, entonces pide una lectura '
      'nueva y el pin parte de donde está ahora',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        expect(b.gps.lecturas, 1, reason: 'la del Mapa al abrirse');
        b.gps.respuesta = Right(_lectura(_ahora));

        b.abrirAlta();
        await pumpEventQueue();

        expect(b.estado.modo, ModoSeguimiento.libre);
        expect(b.gps.lecturas, 2, reason: 'en libre se pide una lectura nueva al abrir');
        expect(
          b.alta.punto,
          _ahora,
          reason: 'el pin parte de la posición de ahora, no de la vieja',
        );
      },
      skip: _omitir(
        'QA #674: en «Mapa libre» el alta parte de la última lectura (la de abrir la pestaña) sin pedir otra; contradice P2 (a) y el cuerpo del PR',
      ),
    );

    test(
      'dado el alta abierta con el pin a mano y Ana en otro lugar, cuando toca «Volver a mi '
      'ubicación» en libre, entonces lee de nuevo y el pin va adonde está ahora',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        b.abrirAlta();
        await pumpEventQueue();
        b.altaNotifier.marcarPunto(const Coordenadas(lat: -34.7, lon: -56.0));
        await pumpEventQueue();
        b.gps.respuesta = Right(_lectura(_ahora));

        b.altaNotifier.volverAMiUbicacion();
        await pumpEventQueue();

        expect(b.gps.lecturas, 2, reason: 'sin seguimiento hay que leer de nuevo');
        expect(b.alta.punto, _ahora);
      },
      skip: _omitir(
        'QA #674: «Volver a mi ubicación» del alta en libre usa la lectura guardada (vieja) y no lee de nuevo, a diferencia de Modificar',
      ),
    );

    test(
      'control: con seguimiento el pin del alta parte de la posición viva sin otra lectura',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);
        b.gps.moverse(_lectura(_ahora));
        await pumpEventQueue();

        b.abrirAlta();
        await pumpEventQueue();

        expect(b.alta.punto, _ahora);
        expect(b.gps.lecturas, 1);
      },
    );
  });

  group('la ventana entre abrir el stream y su primera lectura', () {
    test(
      'recién pasado a «seguir», y antes de que llegue algo, la posición no se da por viva',
      () async {
        final b = _Banco();
        await b.abrirElMapa();
        // Ana camina; la lectura que quedó es la de abrir la pestaña.
        b.ubicacion.cambiarModo(ModoSeguimiento.seguir);

        expect(b.estado.enVivo, isTrue);
        expect(
          b.estado.lecturaViva,
          isNull,
          reason: 'ningún evento del stream llegó: la lectura sigue siendo la vieja',
        );
      },
      skip: _omitir(
        'QA #674: lecturaViva devuelve la lectura vieja apenas se abre el stream; el alta/Modificar pueden partir de ella hasta el primer evento',
      ),
    );
  });
}
