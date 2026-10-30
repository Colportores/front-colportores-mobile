// «Foto del ticket de tarjeta» (vista 29, grupo C, HU-COB-007, #427): los ocho artboards 29C-01 a
// 29C-08, el paso «Datos del ticket» y los casos límite de cada flujo (doble toque, falla a mitad,
// dos acciones seguidas, volver y reentrar, datos límite y letra grande).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/presentation/flujo_ticket_de_tarjeta.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/ticket_tarjeta_arnes.dart';
import '../../helpers/tickets_falsos.dart';

final _enviar = find.byKey(const Key('ticket_enviar'));
final _listo = find.byKey(const Key('ticket_listo'));

Future<void> _escribir(WidgetTester tester, Finder campo, String texto) async {
  await traerTicketAlAlcance(tester, campo);
  await tester.enterText(campo, texto);
  await asentarAgendar(tester, 3);
}

/// El ticket ya subió: la cola dejó la foto en el bucket y el servidor devolvió su fila.
void _subido(ArnesTicket a, {String? campania = 'camp-1', bool llego = true}) => a.repo.cambiar(
  estado: EstadoDeSubida.subida,
  urlCloud: 'col-1/tk-1.jpg',
  subidoEn: llego ? DateTime.utc(2026, 10, 23, 15, 1) : null,
  campaniaValidadoraId: campania,
  quitarElError: true,
);

void main() {
  group('29C-01 · Cámara', () {
    testWidgets('muestra el marco, «Sacar foto» y la galería como alternativa', (tester) async {
      await montarTicket(tester);

      expect(find.text('TICKET DE TARJETA'), findsOneWidget);
      expect(find.text('Encuadrá el ticket entero dentro del marco'), findsOneWidget);
      expect(find.text('Sacar foto'), findsOneWidget);
      expect(find.text('Elegir de la galería'), findsOneWidget);
      expect(find.text('María Fernández · Mataojo 2044 · 3B'), findsOneWidget);
    });

    testWidgets('«✕» cierra el flujo sin sacar nada y avisa que se canceló', (tester) async {
      final a = await montarTicket(tester);

      await tocarTicket(tester, atrasTicket);

      expect(paginaTicket, findsNothing);
      expect(a.resultados, [ResultadoDelFlujoDeTicket.cancelado]);
      expect(a.capturador.vecesCamara, 0);
    });

    testWidgets('cerrar la cámara del teléfono sin sacar nada deja la pantalla lista', (
      tester,
    ) async {
      final a = await montarTicket(tester, capturador: CapturadorDePrueba(camara: const [CapturaCancelada()]));

      await sacarLaFoto(tester);

      expect(find.text('Sacar foto'), findsOneWidget);
      expect(find.byKey(const Key('ticket_aviso_captura')), findsNothing);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
      expect(a.capturador.vecesCamara, 1);
    });

    testWidgets('si la cámara falla avisa qué hacer y el botón vuelve a estar habilitado', (
      tester,
    ) async {
      await montarTicket(tester, capturador: CapturadorDePrueba(camara: const [CapturaFallida()]));

      await sacarLaFoto(tester);

      expect(
        find.text('No pudimos abrir la cámara. Probá de nuevo o elegí una foto de la galería.'),
        findsOneWidget,
      );
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });

    testWidgets('una excepción de la cámara se trata como falla, sin trabar el botón', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      a.capturador.lanzar = StateError('cámara rota');

      await sacarLaFoto(tester);

      expect(find.byKey(const Key('ticket_aviso_captura')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });

    testWidgets('doble toque en «Sacar foto» abre la cámara una sola vez', (tester) async {
      final a = await montarTicket(tester);
      a.capturador.compuerta = Completer<void>();

      await tester.tap(find.byKey(const Key('ticket_sacar_foto')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ticket_sacar_foto')), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byKey(const Key('ticket_galeria')), warnIfMissed: false);
      await asentarAgendar(tester, 2);

      expect(a.capturador.vecesCamara, 1);
      expect(a.capturador.vecesGaleria, 0);
      expect(elBotonPrincipal(tester).onPressed, isNull);

      a.capturador.compuerta!.complete();
      await asentarAgendar(tester);
      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
    });

    testWidgets('una foto que no se puede achicar vuelve a la cámara con el aviso', (tester) async {
      await montarTicket(tester, compresor: CompresorDePrueba([1000], legible: false));

      await sacarLaFoto(tester);

      expect(
        find.text('No pudimos preparar esa foto. Sacá otra, con el ticket entero y bien de cerca.'),
        findsOneWidget,
      );
      expect(find.text('Sacar foto'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });
  });

  group('29C-07 · Sin permiso de cámara', () {
    testWidgets('dice qué hacer y ofrece ajustes, galería y «Después»', (tester) async {
      await montarTicket(
        tester,
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );

      await sacarLaFoto(tester);

      expect(find.text('Necesitamos la cámara'), findsOneWidget);
      expect(
        find.text(
          'Para sacarle foto al ticket, permití que Colportaje use la cámara en los ajustes del teléfono.',
        ),
        findsOneWidget,
      );
      expect(find.text('Abrir ajustes'), findsOneWidget);
      expect(find.text('Elegir de la galería'), findsOneWidget);
      expect(find.text('Después'), findsOneWidget);
    });

    testWidgets('«Abrir ajustes» abre los ajustes y deja la cámara lista para volver a intentar', (
      tester,
    ) async {
      final a = await montarTicket(
        tester,
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );
      await sacarLaFoto(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_abrir_ajustes')));

      expect(a.capturador.vecesAjustes, 1);
      expect(find.text('Encuadrá el ticket entero dentro del marco'), findsOneWidget);
    });

    testWidgets('elegir de la galería sigue con la vista previa', (tester) async {
      final a = await montarTicket(
        tester,
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );
      await sacarLaFoto(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_galeria')));

      expect(a.capturador.vecesGaleria, 1);
      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
    });

    testWidgets('«Después» sale del flujo sin ticket', (tester) async {
      final a = await montarTicket(
        tester,
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );
      await sacarLaFoto(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_despues')));

      expect(paginaTicket, findsNothing);
      expect(a.resultados, [ResultadoDelFlujoDeTicket.despues]);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('«✕» cierra el flujo como cancelado', (tester) async {
      final a = await montarTicket(
        tester,
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );
      await sacarLaFoto(tester);

      await tocarTicket(tester, atrasTicket);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cancelado]);
    });
  });

  group('29C-02 · Vista previa', () {
    testWidgets('pregunta si se lee bien, con las tres salidas del canvas', (tester) async {
      final a = await montarTicket(tester);

      await sacarLaFoto(tester);

      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
      expect(
        find.text('Revisá que se lean el monto, la fecha y el número de aprobación.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket_foto')), findsOneWidget);
      expect(find.text('Se lee bien, subir'), findsOneWidget);
      expect(find.text('Sacar otra'), findsOneWidget);
      // El primer paso de la escalera entró en 200 KB: no hay un nivel más alto que probar.
      expect(find.text('Probar con más calidad'), findsNothing);
      expect(a.compresor.llamadas, hasLength(1));
    });

    testWidgets('«Sacar otra» vuelve a la cámara y descarta la foto', (tester) async {
      final a = await montarTicket(tester);
      await sacarLaFoto(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_otra')));

      expect(find.text('Sacar foto'), findsOneWidget);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('«‹» de la vista previa también vuelve a la cámara', (tester) async {
      await montarTicket(tester);
      await sacarLaFoto(tester);

      await tocarTicket(tester, atrasTicket);

      expect(find.text('Encuadrá el ticket entero dentro del marco'), findsOneWidget);
    });

    testWidgets('«Probar con más calidad» sube un nivel y desaparece al llegar al más alto', (
      tester,
    ) async {
      final a = await montarTicket(
        tester,
        compresor: CompresorDePrueba([300 * 1024, 250 * 1024, 150 * 1024]),
      );
      await sacarLaFoto(tester);
      // Salió por el tercer paso (índice 2): quedan dos niveles más altos.
      expect(find.text('Probar con más calidad'), findsOneWidget);

      await tocarTicket(tester, find.byKey(const Key('ticket_mas_calidad')));
      expect(find.text('Probar con más calidad'), findsOneWidget);
      await tocarTicket(tester, find.byKey(const Key('ticket_mas_calidad')));

      expect(find.text('Probar con más calidad'), findsNothing);
      expect(a.compresor.llamadas.map((l) => l.calidad), [85, 80, 70, 80, 85]);
    });

    testWidgets('si el nivel más alto no entra en 2 MiB, avisa quitando la opción', (tester) async {
      await montarTicket(
        tester,
        compresor: CompresorDePrueba([300 * 1024, 250 * 1024, 150 * 1024, 3 * 1024 * 1024]),
      );
      await sacarLaFoto(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_mas_calidad')));

      expect(find.text('Probar con más calidad'), findsNothing);
      expect(find.text('Se lee bien, subir'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });
  });

  group('Datos del ticket', () {
    testWidgets('llegan precargados con lo que guardó el cobro', (tester) async {
      await montarTicket(tester);

      await irALosDatos(tester);

      expect(find.text('Datos del ticket'), findsOneWidget);
      expect(tester.widget<TextField>(campoMontoTicket).controller!.text, '1.200');
      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, '004512');
      expect(find.text('Hoy, 23/10'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Enviar ticket'), findsOneWidget);
      expect(find.byKey(const Key('ticket_aviso_monto')), findsNothing);
    });

    testWidgets('el número de autorización es obligatorio: sin él el botón dice por qué', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await _escribir(tester, campoAutorizacion, '   ');

      expect(find.text('Falta el número de autorización.'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNull);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('sin monto el botón se apaga y dice «Ingresá el monto del ticket.»', (tester) async {
      await montarTicket(tester);
      await irALosDatos(tester);

      await _escribir(tester, campoMontoTicket, '');

      expect(find.text('Ingresá el monto del ticket.'), findsWidgets);
      expect(elBotonPrincipal(tester).onPressed, isNull);
    });

    testWidgets('un monto que no es un monto marca el campo', (tester) async {
      await montarTicket(tester);
      await irALosDatos(tester);

      await _escribir(tester, campoMontoTicket, 'abc');

      expect(find.text('Escribí un monto válido, por ejemplo 600.'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNull);
    });

    testWidgets('un monto distinto del cobro avisa y no bloquea', (tester) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await _escribir(tester, campoMontoTicket, '1500');

      expect(
        find.text(
          r'El monto del ticket ($ 1.500) no coincide con el cobro ($ 1.200). Revisalo; si es correcto, podés enviarlo igual.',
        ),
        findsOneWidget,
      );
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
      await tocarTicket(tester, _enviar);
      expect(a.repo.recibidos.single.ticket.montoCentavos, 150000);
    });

    testWidgets('«Enviar ticket» guarda con lo cargado y liga el cobro', (tester) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      final r = a.repo.recibidos.single;
      expect(r.ticket.id, 'tk-1');
      expect(r.ticket.tipo, TipoDeTicket.cobroTarjeta);
      expect(r.ticket.montoCentavos, 120000);
      expect(r.ticket.numeroAutorizacion, '004512');
      expect(r.ticket.tarjetaTipo, TipoDeTarjeta.credito);
      expect(r.ticket.tarjetaMarca, 'Visa');
      expect(r.ticket.fecha, hoyDelTicket);
      expect(r.ticket.auditoria.createdBy, 'col-1');
      expect(r.cobroId, 'cobro-1');
      expect(r.foto, isNotEmpty);
    });

    testWidgets('el débito y la marca se pueden cambiar; «Otra» abre su campo', (tester) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_tipo_0')));
      await tocarTicket(tester, find.byKey(const Key('ticket_marca_Otra')));
      await _escribir(tester, find.descendant(
        of: find.byKey(const Key('ticket_marca_otra')),
        matching: find.byType(TextField),
      ), 'Cabal');
      await tocarTicket(tester, _enviar);

      final t = a.repo.recibidos.single.ticket;
      expect(t.tarjetaTipo, TipoDeTarjeta.debito);
      expect(t.tarjetaMarca, 'Cabal');
    });

    testWidgets('la marca es opcional: se puede quitar', (tester) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_marca_Visa')));
      await tocarTicket(tester, _enviar);

      expect(a.repo.recibidos.single.ticket.tarjetaMarca, isNull);
    });

    testWidgets('un cobro sin datos de tarjeta arranca en débito, sin marca y sin autorización', (
      tester,
    ) async {
      final a = await montarTicket(
        tester,
        cobro: cobroConTarjeta(tipo: null, marca: null, aprobacion: null),
      );
      await irALosDatos(tester);
      expect(elBotonPrincipal(tester).onPressed, isNull);

      await _escribir(tester, campoAutorizacion, '9981');
      await tocarTicket(tester, _enviar);

      final t = a.repo.recibidos.single.ticket;
      expect(t.tarjetaTipo, TipoDeTarjeta.debito);
      expect(t.tarjetaMarca, isNull);
      expect(t.numeroAutorizacion, '9981');
    });

    testWidgets('una marca que no es de la lista llega como «Otra» con su texto', (tester) async {
      await montarTicket(tester, cobro: cobroConTarjeta(marca: 'Creditel'));
      await irALosDatos(tester);

      final campo = find.descendant(
        of: find.byKey(const Key('ticket_marca_otra')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(campo).controller!.text, 'Creditel');
    });

    testWidgets('la fecha se puede cambiar a ayer y se guarda al mediodía de ese día', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await tocarTicket(tester, find.byKey(const Key('cobro_fecha')));
      expect(find.text('¿De qué día es el ticket?'), findsOneWidget);
      expect(find.text('No puede ser de mañana.'), findsOneWidget);
      await tocarTicket(tester, find.byKey(const Key('cobro_dia_1')));
      await tocarTicket(tester, find.byKey(const Key('cobro_hoja_listo')));
      expect(find.text('Ayer, 22/10'), findsOneWidget);
      await tocarTicket(tester, _enviar);

      expect(a.repo.recibidos.single.ticket.fecha, DateTime.utc(2026, 10, 22, 15));
    });

    testWidgets('si el servidor rechaza la fecha, el campo lo dice y se puede corregir', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      a.repo.fallas.add(const FailureTicketFechaInvalida());
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(find.text('La fecha del ticket no puede ser de mañana.'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });

    testWidgets('si la autorización llega rechazada, el campo lo dice', (tester) async {
      final a = await montarTicket(tester);
      a.repo.fallas.add(const FailureTicketSinAutorizacion());
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(find.text('Falta el número de autorización.'), findsWidgets);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });

    testWidgets('una autorización larga se corta en 40 caracteres', (tester) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);

      await _escribir(tester, campoAutorizacion, 'A' * 60);
      await tocarTicket(tester, _enviar);

      expect(a.repo.recibidos.single.ticket.numeroAutorizacion, 'A' * 40);
    });

    testWidgets('si la foto no entra en el tope del servidor vuelve a la cámara', (tester) async {
      final a = await montarTicket(tester);
      a.repo.fallas.add(const FailureTicketFotoInvalida());
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(find.text('Encuadrá el ticket entero dentro del marco'), findsOneWidget);
      expect(find.byKey(const Key('ticket_aviso_captura')), findsOneWidget);
    });
  });

  group('Guardar: casos límite', () {
    testWidgets('doble toque en «Enviar ticket» guarda un solo ticket', (tester) async {
      final a = await montarTicket(tester);
      a.repo.compuerta = Completer<void>();
      await irALosDatos(tester);

      await tester.tap(_enviar);
      await tester.pump();
      await tester.tap(_enviar, warnIfMissed: false);
      await tester.pump();

      expect(a.repo.recibidos, hasLength(1));
      expect(find.text('Enviando…'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNull);
      // Mientras guarda, la foto y la fecha no responden.
      expect(tester.widget<TextField>(campoMontoTicket).enabled, isFalse);

      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(a.repo.recibidos, hasLength(1));
    });

    testWidgets('si falla a mitad, el botón vuelve a «Reintentar» y el reintento repite el id', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      a.repo.fallas.add(const FailureTicketNoGuardado(causa: 'x'));
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(
        find.text('No pudimos guardar el ticket en tu teléfono. No se cargó nada: probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);

      await tocarTicket(tester, _enviar);

      expect(a.repo.recibidos.map((r) => r.ticket.id), ['tk-1', 'tk-1']);
      expect(a.idsGenerados, ['tk-1']);
      expect(find.text('Subiendo el ticket'), findsOneWidget);
    });

    testWidgets('una excepción al guardar no deja el botón trabado', (tester) async {
      final a = await montarTicket(tester);
      a.repo.lanzar = StateError('disco lleno');
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ticket_error')), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
    });

    testWidgets('si el cobro ya tiene su ticket lo dice y no deja nada a medias', (tester) async {
      final a = await montarTicket(tester);
      a.repo.fallas.add(const FailureTicketCobroInvalido());
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(find.text('Este cobro ya tiene su ticket, o ya no está. Volvé atrás.'), findsOneWidget);
    });

    testWidgets('volver de los datos a la vista previa y seguir conserva lo escrito', (
      tester,
    ) async {
      await montarTicket(tester);
      await irALosDatos(tester);
      await _escribir(tester, campoAutorizacion, '777');

      await tocarTicket(tester, atrasTicket);
      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
      await tocarTicket(tester, find.byKey(const Key('ticket_se_lee_bien')));

      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, '777');
    });

    testWidgets('tocar la foto de los datos vuelve a la vista previa', (tester) async {
      await montarTicket(tester);
      await irALosDatos(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_foto_cambiar')));

      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
    });

    testWidgets('abrir el flujo otra vez empieza de cero con otro ticket', (tester) async {
      final a = await montarTicket(tester);
      await irALosDatos(tester);
      await _escribir(tester, campoAutorizacion, '777');
      await tocarTicket(tester, atrasTicket);
      await tocarTicket(tester, atrasTicket);
      await tocarTicket(tester, atrasTicket);
      expect(paginaTicket, findsNothing);

      await abrirTicket(tester);
      await irALosDatos(tester);

      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, '004512');
      expect(a.idsGenerados, ['tk-1', 'tk-2']);
      expect(a.resultados, [ResultadoDelFlujoDeTicket.cancelado]);
    });
  });

  group('29C-03 · Subiendo', () {
    testWidgets('guardado el ticket, mientras sube muestra «Subiendo el ticket»', (tester) async {
      await montarTicket(tester);

      await enviarElTicket(tester);

      expect(find.text('Subiendo el ticket'), findsOneWidget);
      expect(find.text('Subiendo…'), findsOneWidget);
      expect(find.byKey(const Key('ticket_foto')), findsOneWidget);
      // Sin «‹» ni «✕»: no hay nada que cancelar, el ticket ya está guardado.
      expect(atrasTicket, findsNothing);
      expect(elBotonPrincipal(tester).onPressed, isNull);
    });

    testWidgets('al terminar de subir pasa solo a «Ticket subido»', (tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);

      _subido(a);
      await asentarAgendar(tester);

      expect(find.text('Ticket subido'), findsOneWidget);
      expect(find.text('Subiendo el ticket'), findsNothing);
    });
  });

  group('29C-04 · Subido', () {
    testWidgets('dice que el coordinador lo revisa y deja borrar la copia del teléfono', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);

      _subido(a);
      await asentarAgendar(tester);

      expect(find.text('Ticket subido'), findsOneWidget);
      expect(find.text('Tu coordinador lo va a revisar'), findsOneWidget);
      expect(find.text('Te avisamos cuando lo valide. Queda guardado 4 meses.'), findsOneWidget);
      expect(find.text('Copia en este teléfono'), findsOneWidget);
      expect(find.text('Borrar'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('con el dato del servidor «lo revisa Administración» lo dice', (tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);

      _subido(a, campania: null);
      await asentarAgendar(tester);

      expect(find.text('Lo revisa Administración'), findsOneWidget);
      expect(find.text('Tu coordinador lo va a revisar'), findsNothing);
    });

    testWidgets('sin el dato del servidor no dice quién lo revisa (R1)', (tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);

      _subido(a, campania: null, llego: false);
      await asentarAgendar(tester);

      expect(find.text('Ticket subido'), findsOneWidget);
      expect(find.text('Lo revisa Administración'), findsNothing);
      expect(find.text('Tu coordinador lo va a revisar'), findsNothing);
      expect(find.text('Te avisamos cuando lo valide. Queda guardado 4 meses.'), findsOneWidget);
    });

    testWidgets('«Listo» cierra el flujo con el ticket cargado', (tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);
      _subido(a);
      await asentarAgendar(tester);

      await tocarTicket(tester, _listo);

      expect(paginaTicket, findsNothing);
      expect(a.resultados, [ResultadoDelFlujoDeTicket.cargado]);
    });

    testWidgets('doble toque en «Listo» cierra una sola vez', (tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);
      _subido(a);
      await asentarAgendar(tester);

      await tester.tap(_listo);
      await tester.tap(_listo, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cargado]);
      expect(find.text('abrir ticket'), findsOneWidget);
    });
  });

  group('29C-08 · Borrar la copia', () {
    Future<ArnesTicket> subido(WidgetTester tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);
      _subido(a);
      await asentarAgendar(tester);
      return a;
    }

    testWidgets('«Borrar» abre la hoja con lo que pasa con el ticket en el servidor', (
      tester,
    ) async {
      await subido(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));

      expect(find.text('¿Borrar la copia de este teléfono?'), findsOneWidget);
      expect(
        find.text('El ticket sigue en el servidor por 4 meses y tu coordinador lo puede revisar.'),
        findsOneWidget,
      );
      expect(find.text('Borrar copia'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('«Cancelar» no borra nada', (tester) async {
      final a = await subido(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));

      await tocarTicket(tester, find.byKey(const Key('ticket_cancelar_borrar')));

      expect(a.repo.borrados, 0);
      expect(find.text('Copia en este teléfono'), findsOneWidget);
    });

    testWidgets('«Borrar copia» borra la copia, la tarjeta desaparece y lo dice', (tester) async {
      final a = await subido(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));

      await tocarTicket(tester, find.byKey(const Key('ticket_confirmar_borrar')));

      expect(a.repo.borrados, 1);
      expect(find.text('Copia en este teléfono'), findsNothing);
      expect(find.text('Copia borrada de este teléfono.'), findsOneWidget);
      expect(find.text('Ticket subido'), findsOneWidget);
    });

    testWidgets('doble toque en «Borrar copia» borra una sola vez', (tester) async {
      final a = await subido(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));

      await tester.tap(find.byKey(const Key('ticket_confirmar_borrar')));
      await tester.tap(find.byKey(const Key('ticket_confirmar_borrar')), warnIfMissed: false);
      await asentarAgendar(tester);

      expect(a.repo.borrados, 1);
    });

    testWidgets('si falla al borrar avisa, la copia sigue y se puede intentar de nuevo', (
      tester,
    ) async {
      final a = await subido(tester);
      a.repo.fallaAlBorrar = const FailureTicketNoGuardado(causa: 'x');
      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));
      await tocarTicket(tester, find.byKey(const Key('ticket_confirmar_borrar')));

      expect(find.text('No pudimos borrar la copia. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Copia en este teléfono'), findsOneWidget);

      a.repo.fallaAlBorrar = null;
      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));
      await tocarTicket(tester, find.byKey(const Key('ticket_confirmar_borrar')));

      expect(a.repo.borrados, 1);
      expect(find.text('Copia borrada de este teléfono.'), findsOneWidget);
    });
  });

  group('29C-05 · Sin conexión: en cola', () {
    testWidgets('sin red el ticket queda en cola y lo dice', (tester) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);

      a.conexion.cambiarA(TipoConexion.sinConexion);
      await asentarAgendar(tester);

      expect(find.text('Ticket guardado'), findsOneWidget);
      expect(
        find.text('Sin conexión. El ticket queda en cola y se sube solo cuando vuelva la red.'),
        findsOneWidget,
      );
      expect(find.text(r'Ticket del 23/10 · $ 1.200'), findsOneWidget);
      expect(find.text('Esperando conexión'), findsOneWidget);
      expect(find.text('En cola'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('guardar sin red lleva directo a la cola', (tester) async {
      final a = await montarTicket(tester);
      a.conexion.tipo = TipoConexion.sinConexion;
      await irALosDatos(tester);

      await tocarTicket(tester, _enviar);

      expect(find.text('Ticket guardado'), findsOneWidget);
      expect(a.repo.recibidos, hasLength(1));
    });

    testWidgets('al volver la red y subir, la cola se convierte en «Ticket subido»', (
      tester,
    ) async {
      final a = await montarTicket(tester);
      await enviarElTicket(tester);
      a.conexion.cambiarA(TipoConexion.sinConexion);
      await asentarAgendar(tester);

      a.conexion.cambiarA(TipoConexion.wifi);
      _subido(a);
      await asentarAgendar(tester);

      expect(find.text('Ticket subido'), findsOneWidget);
    });

    testWidgets('«Listo» de la cola cierra el flujo con el ticket cargado', (tester) async {
      final a = await montarTicket(tester);
      a.conexion.tipo = TipoConexion.sinConexion;
      await enviarElTicket(tester);

      await tocarTicket(tester, _listo);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cargado]);
    });
  });

  group('29C-06 · Error al subir', () {
    Future<ArnesTicket> conError(
      WidgetTester tester, {
      List<ResultadoDeSubidaDeFoto>? servidor,
    }) async {
      final a = await montarTicket(
        tester,
        servidor: servidor == null ? null : ServidorDeFotosGuionado(servidor),
      );
      await enviarElTicket(tester);
      a.repo.cambiar(ultimoError: 'servidor_500', intentos: 1);
      await asentarAgendar(tester);
      return a;
    }

    testWidgets('dice que quedó guardado y se reintenta solo, con «Reintentar ahora»', (
      tester,
    ) async {
      await conError(tester);

      expect(find.text('No se pudo subir'), findsOneWidget);
      expect(
        find.text(
          'No pudimos subir el ticket. Lo guardamos en el teléfono y lo reintentamos solo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar ahora'), findsOneWidget);
      expect(find.byKey(const Key('ticket_foto')), findsOneWidget);
    });

    testWidgets('«Reintentar ahora» sube la foto y pasa a «Ticket subido»', (tester) async {
      final a = await conError(tester, servidor: [const FotoSubida('col-1/tk-1.jpg')]);

      await tocarTicket(tester, find.byKey(const Key('venta_aviso_accion')));

      expect(a.servidor.pedidos, hasLength(1));
      expect(a.servidor.pedidos.single.ticketId, 'tk-1');
      expect(find.text('Ticket subido'), findsOneWidget);
    });

    testWidgets('si el reintento falla, vuelve a mostrar el error y el botón se habilita', (
      tester,
    ) async {
      final a = await conError(
        tester,
        servidor: [const SubidaFallida(codigo: 'servidor_500', reintentable: true)],
      );

      await tocarTicket(tester, find.byKey(const Key('venta_aviso_accion')));

      expect(a.servidor.pedidos, hasLength(1));
      expect(find.text('Reintentar ahora'), findsOneWidget);
      final accion = tester.widget<TextButton>(find.byKey(const Key('venta_aviso_accion')));
      expect(accion.onPressed, isNotNull);

      await tocarTicket(tester, find.byKey(const Key('venta_aviso_accion')));
      expect(a.servidor.pedidos, hasLength(2));
    });

    testWidgets('dos toques seguidos en «Reintentar ahora» piden una sola subida', (tester) async {
      final a = await conError(tester, servidor: [const FotoSubida('col-1/tk-1.jpg')]);
      a.servidor.espera = Completer<void>().future;

      await tester.tap(find.byKey(const Key('venta_aviso_accion')));
      await tester.pump();
      expect(find.text('Reintentando…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('venta_aviso_accion')), warnIfMissed: false);
      await asentarAgendar(tester, 2);

      expect(a.servidor.pedidos, hasLength(1));
      expect(
        tester.widget<TextButton>(find.byKey(const Key('venta_aviso_accion'))).onPressed,
        isNull,
      );
    });

    testWidgets('si el servidor no acepta la foto lo dice y no ofrece reintentar', (tester) async {
      final a = await conError(
        tester,
        servidor: [const SubidaFallida(codigo: 'foto_muy_pesada', reintentable: false)],
      );

      await tocarTicket(tester, find.byKey(const Key('venta_aviso_accion')));

      expect(
        find.text('El servidor no aceptó esta foto y no se va a reintentar. Avisale a tu coordinador.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar ahora'), findsNothing);
      expect(a.servidor.pedidos, hasLength(1));
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('«Listo» deja el ticket guardado y cierra el flujo', (tester) async {
      final a = await conError(tester);

      await tocarTicket(tester, _listo);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cargado]);
    });
  });

  group('Letra grande y datos límite', () {
    testWidgets('textScaler 2.0 a 320×568 en cada paso, sin desbordes', (tester) async {
      final a = await montarTicket(
        tester,
        escala: 2,
        tamano: const Size(320, 568),
        cobro: cobroConTarjeta(marca: 'Una marca con un nombre larguísimo de ta'),
      );
      expect(tester.takeException(), isNull);

      await sacarLaFoto(tester);
      expect(tester.takeException(), isNull);
      await tocarTicket(tester, find.byKey(const Key('ticket_se_lee_bien')));
      expect(tester.takeException(), isNull);
      await _escribir(tester, campoAutorizacion, 'X' * 40);
      expect(tester.takeException(), isNull);
      await tocarTicket(tester, _enviar);
      expect(tester.takeException(), isNull);

      a.repo.cambiar(ultimoError: 'red', intentos: 1);
      await asentarAgendar(tester);
      expect(find.text('No se pudo subir'), findsOneWidget);
      expect(tester.takeException(), isNull);

      _subido(a);
      await asentarAgendar(tester);
      expect(find.text('Ticket subido'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('textScaler 2.0: la cámara, el permiso y la cola entran sin desbordar', (
      tester,
    ) async {
      final a = await montarTicket(
        tester,
        escala: 2,
        tamano: const Size(320, 568),
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );
      await sacarLaFoto(tester);
      expect(find.text('Necesitamos la cámara'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tocarTicket(tester, atrasTicket);
      a.conexion.tipo = TipoConexion.sinConexion;
      await abrirTicket(tester);
      await asentarAgendar(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un monto enorme no se acepta y no rompe', (tester) async {
      await montarTicket(tester);
      await irALosDatos(tester);

      await _escribir(tester, campoMontoTicket, '99999999999');

      expect(elBotonPrincipal(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('Accesibilidad', () {
    testWidgets('cada paso tiene su encabezado y el botón principal un rótulo', (tester) async {
      await montarTicket(tester);
      final h = tester.ensureSemantics();

      expect(find.bySemanticsLabel('Encuadrá el ticket entero dentro del marco'), findsOneWidget);
      await sacarLaFoto(tester);
      expect(
        tester.getSemantics(find.text('¿Se lee bien el ticket?')),
        matchesSemantics(
          label: '¿Se lee bien el ticket?\nMaría Fernández · Mataojo 2044 · 3B',
          isHeader: true,
        ),
      );
      expect(
        find.bySemanticsLabel('Vista previa del ticket, con el texto a tamaño real'),
        findsOneWidget,
      );
      h.dispose();
    });
  });
}
