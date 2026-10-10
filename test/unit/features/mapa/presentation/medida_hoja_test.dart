// La medida de la hoja inferior de las vistas 03 y 07 (#324): cuánto alto pide la hoja con el teclado
// abierto y dónde queda la acción. Son cuentas puras; la geometría real, con las fuentes del proyecto,
// va en `alta_ubicacion_teclado_324_test.dart` y `modificar_ubicacion_teclado_324_test.dart`.
import 'package:colportores_mobile/features/mapa/presentation/widgets/medida_hoja.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const necesidad = NecesidadHoja(campo: 48, boton: 52, motivo: 26);

  double tope(
    double cuerpo, {
    NecesidadHoja? n = necesidad,
    bool teclado = true,
    double arriba = 24,
    double abajo = 0,
  }) => topeDeLaHoja(
    cuerpo: cuerpo,
    barraDeArriba: arriba,
    barraDeAbajo: abajo,
    tecladoAbierto: teclado,
    necesidad: n,
  );

  group('reservaDelMapa', () {
    test('es lo que necesita el pin (88 dp) o, si es más, «Cerrar» bajo la barra de estado', () {
      expect(reservaDelMapa(0), 88);
      expect(reservaDelMapa(24), 88);
      expect(reservaDelMapa(40), 96);
    });
  });

  group('topeDeLaHoja', () {
    test('sin teclado es el 62 % del cuerpo, pida lo que pida', () {
      expect(
        tope(568, teclado: false, n: const NecesidadHoja(campo: 90, boton: 72, motivo: 40)),
        closeTo(568 * .62, .001),
      );
    });

    test('con teclado y antes de medir la hoja es el 62 %', () {
      expect(tope(340, n: null), closeTo(340 * .62, .001));
      expect(tope(340, n: const NecesidadHoja(campo: 0, boton: 52)), closeTo(340 * .62, .001));
    });

    test('con teclado y todo entero dentro del 62 %, no crece', () {
      expect(tope(600), closeTo(600 * .62, .001));
      // 46 + 14 + 52 + 48 + 28 + 26 = 214 y el 62 % de 345 son 213,9: crece 0,1.
      expect(tope(345), closeTo(214, .001));
    });

    test('con teclado crece lo justo para el campo entero sobre la acción y el motivo debajo', () {
      // 46 de borde + 14 + 52 de botón + 48 de campo + 28 de aire + 26 de motivo; el 62 % de 320 es 198,4.
      expect(tope(320), closeTo(46 + 14 + 52 + 48 + 28 + 26, .001));
    });

    test('suma la barra de abajo del sistema al borde', () {
      expect(tope(320, abajo: 10) - tope(320), closeTo(10, .001));
    });

    test('si el motivo dejaría el mapa sin su reserva, pide solo lo del campo y la acción', () {
      // Con el motivo pide 214 y al mapa le quedan 268 - 214 = 54 dp, menos que los 88 de reserva.
      expect(tope(268), closeTo(46 + 14 + 52 + 48 + 28, .001));
      // Con 302 dp de cuerpo el mapa conserva 88 dp con el motivo debajo.
      expect(tope(302), closeTo(214, .001));
      // 301 dp: el mapa quedaría de 87 dp; el motivo va al final de lo que se desplaza.
      expect(tope(301), closeTo(46 + 14 + 52 + 48 + 28, .001));
    });

    test('la reserva del mapa crece con la barra de estado', () {
      // Con 40 dp de barra la reserva es de 96 dp: con 309 de cuerpo el mapa quedaría de 95 con el
      // motivo debajo (la hoja se queda en el 62 %); con 24 dp de barra sí pide el motivo.
      expect(tope(309, arriba: 40), closeTo(309 * .62, .001));
      expect(tope(309), closeTo(214, .001));
      expect(tope(310, arriba: 40), closeTo(214, .001));
    });

    test('nunca pasa del 80 % del cuerpo, ni siquiera para el campo y la acción', () {
      expect(
        tope(200, n: const NecesidadHoja(campo: 90, boton: 72, motivo: 40)),
        closeTo(200 * .8, .001),
      );
    });
  });

  group('lugarDeLaAccion', () {
    LugarDeLaAccion lugar({
      required double contenido,
      required bool teclado,
      double boton = 52,
      double motivo = 18,
      double? campo = 48,
    }) => lugarDeLaAccion(
      contenido: contenido,
      tecladoAbierto: teclado,
      boton: boton,
      motivo: motivo,
      campo: campo,
    );

    test(
      'con teclado: el campo entero sobre la acción y el motivo, la acción fija y el motivo abajo',
      () {
        // 14 + 52 + 8 + 18 de lo fijo y 48 + 28 del campo.
        expect(lugar(contenido: 168, teclado: true), LugarDeLaAccion.fijaConMotivoAbajo);
        expect(lugar(contenido: 167, teclado: true), LugarDeLaAccion.fijaConMotivoArriba);
      },
    );

    test('con teclado: sin lugar para el campo sobre la acción, la acción va al final', () {
      // 14 + 52 + 48 + 28 = 142.
      expect(lugar(contenido: 142, teclado: true), LugarDeLaAccion.fijaConMotivoArriba);
      expect(lugar(contenido: 141, teclado: true), LugarDeLaAccion.alFinalDeLoQueSeDesplaza);
    });

    test('con teclado cuenta el alto medido del botón, no 52', () {
      // Con 52 de botón, 168 alcanzaba para dejarlo fijo con el motivo abajo; con 72 hacen falta 188.
      expect(lugar(contenido: 168, teclado: true, boton: 72), LugarDeLaAccion.fijaConMotivoArriba);
      expect(lugar(contenido: 162, teclado: true, boton: 72), LugarDeLaAccion.fijaConMotivoArriba);
      expect(
        lugar(contenido: 161, teclado: true, boton: 72),
        LugarDeLaAccion.alFinalDeLoQueSeDesplaza,
      );
    });

    test('con teclado y sin medir el campo (primer cuadro) la acción queda fija', () {
      expect(lugar(contenido: 100, teclado: true, campo: null), LugarDeLaAccion.fijaConMotivoAbajo);
    });

    test('sin motivo: la acción fija', () {
      expect(lugar(contenido: 300, teclado: false, motivo: 0), LugarDeLaAccion.fijaConMotivoAbajo);
      expect(lugar(contenido: 142, teclado: true, motivo: 0), LugarDeLaAccion.fijaConMotivoAbajo);
    });

    test('sin teclado: el motivo va abajo mientras lo fijo no pase de dos tercios', () {
      // Lo fijo: 14 + 52 + 8 + 18 = 92; dos tercios de 140 son 93,3 y de 136, 90,7.
      expect(lugar(contenido: 140, teclado: false), LugarDeLaAccion.fijaConMotivoAbajo);
      expect(lugar(contenido: 136, teclado: false), LugarDeLaAccion.fijaConMotivoArriba);
    });

    test(
      'sin teclado: si debajo del botón no queda un campo para lo que se desplaza, va arriba',
      () {
        expect(
          lugar(contenido: 150, teclado: false, campo: 50),
          LugarDeLaAccion.fijaConMotivoAbajo,
        );
        expect(
          lugar(contenido: 150, teclado: false, campo: 90),
          LugarDeLaAccion.fijaConMotivoArriba,
        );
      },
    );

    test('sin teclado la acción nunca pasa al final de lo que se desplaza', () {
      expect(lugar(contenido: 40, teclado: false), LugarDeLaAccion.fijaConMotivoArriba);
    });
  });

  group('NecesidadHoja', () {
    test('es igual con medio punto de diferencia o menos', () {
      expect(
        const NecesidadHoja(campo: 48, boton: 52, motivo: 26),
        const NecesidadHoja(campo: 48.3, boton: 51.8, motivo: 26.2),
      );
      expect(
        const NecesidadHoja(campo: 48, boton: 52, motivo: 26) ==
            const NecesidadHoja(campo: 48, boton: 56, motivo: 26),
        isFalse,
      );
    });

    test('el hash acompaña a la igualdad para lo que se redondea igual', () {
      expect(
        const NecesidadHoja(campo: 48, boton: 52).hashCode,
        const NecesidadHoja(campo: 48.1, boton: 52.1).hashCode,
      );
    });
  });
}
