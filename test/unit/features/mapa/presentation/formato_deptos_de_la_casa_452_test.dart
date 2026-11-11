// Cómo se escriben los deptos en la hoja de la casa (vista 39, N·04, N·06, C·09 y C·10, #452).
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_hoja_casa.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/espacios_falsos.dart';
import '../../../../helpers/modificar_ubicacion_falsos.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 23, 15);
  final d3B = espacioDe('d-3b', '3B', piso: '3');
  final sinPiso = espacioDe('d-x', '7');
  final sinNumero = espacioDe('d-s', null);

  ItemListaUbicacion edificio({double? metros = 35, DateTime? baja, TipoUbicacion? tipo}) =>
      ItemListaUbicacion(
        ubicacion: ubicacionGuardada(
          tipo: tipo ?? TipoUbicacion.edificio,
          calle: 'Grecia',
          numero: '3313',
          deBajaDesde: baja,
        ),
        distanciaMetros: metros,
      );

  group('la línea debajo de la dirección del edificio', () {
    test('C·09: el tipo, la cuenta de deptos y la distancia', () {
      expect(
        FormatoDeptosDeLaCasa.subtitulo(edificio(), cantidad: 6, recienRegistrado: false),
        'Edificio · 6 deptos · a 35\u00A0m de vos',
      );
      expect(
        FormatoDeptosDeLaCasa.subtitulo(edificio(), cantidad: 1, recienRegistrado: false),
        'Edificio · 1 depto · a 35\u00A0m de vos',
      );
    });

    test('N·06: «recién registrado» en lugar de la distancia', () {
      expect(
        FormatoDeptosDeLaCasa.subtitulo(edificio(), cantidad: 3, recienRegistrado: true),
        'Edificio · 3 deptos · recién registrado',
      );
    });

    test('sin GPS o lejos (E·05, que ya lo dice el aviso) no dice la distancia', () {
      expect(
        FormatoDeptosDeLaCasa.subtitulo(
          edificio(metros: null),
          cantidad: 2,
          recienRegistrado: false,
        ),
        'Edificio · 2 deptos',
      );
      expect(
        FormatoDeptosDeLaCasa.subtitulo(
          edificio(metros: 650),
          cantidad: 2,
          recienRegistrado: false,
        ),
        'Edificio · 2 deptos',
      );
    });

    test('un negocio dice «Negocio»', () {
      expect(
        FormatoDeptosDeLaCasa.subtitulo(
          edificio(tipo: TipoUbicacion.negocio),
          cantidad: 2,
          recienRegistrado: false,
        ),
        'Negocio · 2 deptos · a 35\u00A0m de vos',
      );
    });

    test('dado de baja dice cuándo, como la casa (E·04)', () {
      final linea = FormatoDeptosDeLaCasa.subtitulo(
        edificio(baja: DateTime.utc(2026, 10, 18, 12)),
        cantidad: 2,
        recienRegistrado: false,
      );
      expect(linea, contains('18/10'));
      expect(linea, isNot(contains('deptos')));
    });
  });

  group('la línea de abajo de cada depto', () {
    test('N·04 (sumando deptos): solo el piso; sin piso, nada', () {
      final r = ResumenDelDepto();
      expect(
        FormatoDeptosDeLaCasa.detalle(d3B, r, ahora, recienRegistrado: true, conEstado: false),
        'Piso 3',
      );
      expect(
        FormatoDeptosDeLaCasa.detalle(sinPiso, r, ahora, recienRegistrado: true, conEstado: false),
        '',
      );
    });

    test('N·06 (eligiendo): el piso y el estado', () {
      expect(
        FormatoDeptosDeLaCasa.detalle(d3B, ResumenDelDepto(), ahora, recienRegistrado: true),
        'Piso 3 · Sin visita',
      );
      expect(
        FormatoDeptosDeLaCasa.detalle(sinPiso, ResumenDelDepto(), ahora, recienRegistrado: true),
        'Sin visita',
      );
    });

    test('C·09: el resultado de visita con cuándo fue', () {
      final ayer = ahora.subtract(const Duration(days: 1));
      for (final (estado, rotulo) in [
        (EstadoCasa.noContesto, 'No contestó'),
        (EstadoCasa.rechazo, 'Rechazó'),
        (EstadoCasa.entrevistaHecha, 'Entrevista hecha'),
      ]) {
        expect(
          FormatoDeptosDeLaCasa.detalle(
            d3B,
            ResumenDelDepto(estado: estado, ultimaVisita: ayer),
            ahora,
            recienRegistrado: false,
          ),
          '$rotulo · ayer',
        );
      }
    });

    test('C·09: la entrevista agendada dice cuándo es; la venta, solo el estado', () {
      final linea = FormatoDeptosDeLaCasa.detalle(
        d3B,
        ResumenDelDepto(
          estado: EstadoCasa.entrevistaAgendada,
          proximaEntrevista: ahora.add(const Duration(days: 1)),
        ),
        ahora,
        recienRegistrado: false,
      );
      expect(linea, startsWith('Entrevista agendada · '));
      expect(
        FormatoDeptosDeLaCasa.detalle(
          d3B,
          ResumenDelDepto(estado: EstadoCasa.cobranzaPendiente, ultimaVisita: ahora),
          ahora,
          recienRegistrado: false,
        ),
        'Cobranza pendiente',
      );
    });

    test('sin el resumen no afirma ningún estado: dice solo el piso, si lo tiene', () {
      expect(FormatoDeptosDeLaCasa.detalle(d3B, null, ahora, recienRegistrado: false), 'Piso 3');
      expect(FormatoDeptosDeLaCasa.detalle(d3B, null, ahora, recienRegistrado: true), 'Piso 3');
      expect(FormatoDeptosDeLaCasa.detalle(sinPiso, null, ahora, recienRegistrado: false), '');
    });
  });

  group('el depto como una casa (C·10)', () {
    test('el título lleva el depto; sin número, «Sin número»', () {
      expect(FormatoDeptosDeLaCasa.tituloDelDepto('Grecia 3313', d3B), 'Grecia 3313 · Depto 3B');
      expect(
        FormatoDeptosDeLaCasa.tituloDelDepto('Grecia 3313', sinNumero),
        'Grecia 3313 · Sin número',
      );
      expect(FormatoDeptosDeLaCasa.tituloDelDepto(' ', d3B), 'Depto 3B');
    });

    test('la línea de abajo: el estado del depto y el piso en minúscula', () {
      expect(
        FormatoDeptosDeLaCasa.subtituloDelDepto(
          d3B,
          ResumenDelDepto(estado: EstadoCasa.cobranzaPendiente),
          ahora,
        ),
        'Cobranza pendiente · piso 3',
      );
      expect(FormatoDeptosDeLaCasa.subtituloDelDepto(d3B, null, ahora), 'piso 3');
      expect(
        FormatoDeptosDeLaCasa.subtituloDelDepto(sinPiso, ResumenDelDepto(), ahora),
        'Sin visita',
      );
    });
  });

  test('«6 DEPTOS», «1 DEPTO» y «Edificio en Grecia 3307»', () {
    expect(TextosDeptosDeLaCasa.cantidad(6), '6 DEPTOS');
    expect(TextosDeptosDeLaCasa.cantidad(1), '1 DEPTO');
    expect(TextosDeptosDeLaCasa.edificioEn('Grecia 3307'), 'Edificio en Grecia 3307');
  });
}
