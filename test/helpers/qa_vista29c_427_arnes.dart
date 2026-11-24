// Arnés de la QA de «Foto del ticket de tarjeta» (vista 29 C, #427, PR #601): lleva la pantalla a
// cada artboard del canvas (29C-01 a 29C-08 y 29A-03) y a los estados que el canvas no dibuja, en los
// dos tamaños y las dos escalas de texto de la QA. Reutiliza los dobles de `ticket_tarjeta_arnes.dart`.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/presentation/flujo_ticket_de_tarjeta.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'cobro_arnes.dart';
import 'ticket_tarjeta_arnes.dart';
import 'tickets_falsos.dart';

typedef Tamano = ({String nombre, double ancho, double alto});

const tamanos = <Tamano>[
  (nombre: '360x640', ancho: 360, alto: 640),
  (nombre: '412x915', ancho: 412, alto: 915),
];

const escalas = <double>[1.0, 2.0];

/// Las fuentes del proyecto (sin ellas `flutter_test` pinta cajas) y los íconos de Material.
Future<void> cargarFuentes427() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await c.load();
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++, dir = dir.parent) {
    final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
      return;
    }
  }
}

/// Un compresor que espera a que el test lo suelte: el paso «Preparando la foto…».
final class CompresorEnEspera implements CompresorDeImagen {
  final compuerta = Completer<void>();

  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) async {
    await compuerta.future;
    return fotoDePrueba(150 * 1024);
  }
}

const pesosMasCalidad = [300 * 1024, 250 * 1024, 150 * 1024];

/// Un compresor de prueba: el peso de cada paso sale de [pesos] (la última se repite) y, si hay
/// [foto], devuelve ese ticket dibujado (rellenado hasta el peso) en vez de bytes sin sentido, para que
/// las capturas muestren un ticket de verdad y no el marco de «no se puede dibujar».
final class CompresorQA implements CompresorDeImagen {
  CompresorQA(this.pesos, {this.foto});

  final List<int> pesos;
  final Uint8List? foto;
  var llamadas = 0;

  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) async {
    final i = llamadas++;
    final peso = pesos[i < pesos.length ? i : pesos.length - 1];
    final base = foto;
    if (base == null) return fotoDePrueba(peso);
    return Uint8List(peso)..setAll(0, base);
  }
}

/// Todos los estados que se recorren: cada artboard del canvas y los que el canvas no dibuja.
enum Estado427 {
  camara('29C-01', 'camara'),
  camaraConAviso('29C-01x', 'camara con aviso de falla'),
  sinPermiso('29C-07', 'sin permiso'),
  preparando('29C-xx', 'preparando la foto'),
  vistaPrevia('29C-02', 'vista previa'),
  vistaPreviaMasCalidad('29C-02x', 'vista previa con mas calidad'),
  datos('38A-01', 'datos del ticket'),
  datosEnBlanco('38A-01x', 'datos sin monto ni autorizacion'),
  datosMontoDistinto('38A-01y', 'datos con monto distinto'),
  datosMarcaOtra('38A-01z', 'datos con marca otra'),
  datosFallaAlGuardar('29C-xy', 'datos con falla al guardar'),
  subiendo('29C-03', 'subiendo'),
  subido('29C-04', 'subido'),
  subidoAdministracion('29C-04x', 'subido lo revisa Administracion'),
  subidoSinCopia('29C-04y', 'subido sin copia'),
  enCola('29C-05', 'en cola'),
  errorAlSubir('29C-06', 'error al subir'),
  rechazada('29C-06x', 'foto rechazada'),
  hojaBorrar('29C-08', 'hoja borrar copia');

  const Estado427(this.artboard, this.rotulo);

  final String artboard;
  final String rotulo;

  String get id => name;
}

void _subida(ArnesTicket a, {String? campania = 'camp-1', bool llego = true}) => a.repo.cambiar(
  estado: EstadoDeSubida.subida,
  urlCloud: 'col-1/tk-1.jpg',
  subidoEn: llego ? DateTime.utc(2026, 10, 23, 15, 1) : null,
  campaniaValidadoraId: campania,
  quitarElError: true,
);

/// Lleva el flujo del ticket al [estado], con el [tamano] y la [escala] de texto dados.
Future<ArnesTicket> llevarAlEstado427(
  WidgetTester tester,
  Estado427 estado, {
  Tamano? tamano,
  double escala = 1,
  Uint8List? foto,
}) async {
  final size = tamano == null ? const Size(390, 844) : Size(tamano.ancho, tamano.alto);
  final fotoCapturada = foto ?? fotoDePrueba(4000);
  final compresor = foto == null ? null : CompresorQA(const [150 * 1024], foto: foto);
  switch (estado) {
    case Estado427.camara:
      return montar427(tester, tamano: size, escala: escala, compresor: compresor);
    case Estado427.camaraConAviso:
      final a = await montar427(
        tester,
        tamano: size,
        escala: escala,
        capturador: CapturadorDePrueba(camara: const [CapturaFallida()]),
        compresor: compresor,
      );
      await sacarLaFoto(tester);
      return a;
    case Estado427.sinPermiso:
      final a = await montar427(
        tester,
        tamano: size,
        escala: escala,
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
        compresor: compresor,
      );
      await sacarLaFoto(tester);
      return a;
    case Estado427.preparando:
      final espera = CompresorEnEspera();
      final a = await montar427(
        tester,
        compresor: espera,
        tamano: size,
        escala: escala,
        capturador: CapturadorDePrueba(camara: [FotoCapturada(fotoCapturada)]),
      );
      await tester.tap(find.byKey(const Key('ticket_sacar_foto')));
      await asentarAgendar(tester);
      // La compuerta queda abierta para que el teardown no deje un future colgado.
      addTearDown(() {
        if (!espera.compuerta.isCompleted) espera.compuerta.complete();
      });
      return a;
    case Estado427.vistaPrevia:
      final a = await montar427(
        tester,
        tamano: size,
        escala: escala,
        capturador: CapturadorDePrueba(camara: [FotoCapturada(fotoCapturada)]),
        compresor: compresor,
      );
      await sacarLaFoto(tester);
      return a;
    case Estado427.vistaPreviaMasCalidad:
      final a = await montar427(
        tester,
        tamano: size,
        escala: escala,
        capturador: CapturadorDePrueba(camara: [FotoCapturada(fotoCapturada)]),
        compresor: CompresorQA(pesosMasCalidad, foto: foto),
      );
      await sacarLaFoto(tester);
      return a;
    case Estado427.datos:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await irALosDatos(tester);
      return a;
    case Estado427.datosEnBlanco:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await irALosDatos(tester);
      await escribir427(tester, campoMontoTicket, '');
      await escribir427(tester, campoAutorizacion, '');
      return a;
    case Estado427.datosMontoDistinto:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await irALosDatos(tester);
      await escribir427(tester, campoMontoTicket, '1500');
      return a;
    case Estado427.datosMarcaOtra:
      final a = await montar427(
        tester,
        tamano: size,
        escala: escala,
        cobro: cobroConTarjeta(marca: 'Cabal del Sur'),
        compresor: compresor,
      );
      await irALosDatos(tester);
      return a;
    case Estado427.datosFallaAlGuardar:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      a.repo.fallas.add(const FailureTicketNoGuardado(causa: 'prueba'));
      await irALosDatos(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));
      return a;
    case Estado427.subiendo:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      return a;
    case Estado427.subido:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      _subida(a);
      await asentarAgendar(tester);
      return a;
    case Estado427.subidoAdministracion:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      _subida(a, campania: null);
      await asentarAgendar(tester);
      return a;
    case Estado427.subidoSinCopia:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      _subida(a);
      a.repo.cambiar(sinCopia: true);
      await asentarAgendar(tester);
      return a;
    case Estado427.enCola:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      a.conexion.cambiarA(TipoConexion.sinConexion);
      await asentarAgendar(tester);
      return a;
    case Estado427.errorAlSubir:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      a.repo.cambiar(ultimoError: 'servidor_500', intentos: 1);
      await asentarAgendar(tester);
      return a;
    case Estado427.rechazada:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      a.repo.cambiar(estado: EstadoDeSubida.rechazada, ultimoError: 'foto_400', intentos: 1);
      await asentarAgendar(tester);
      return a;
    case Estado427.hojaBorrar:
      final a = await montar427(tester, tamano: size, escala: escala, compresor: compresor);
      await enviarElTicket(tester);
      _subida(a);
      await asentarAgendar(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_borrar_copia')));
      return a;
  }
}

/// `montarTicket` con un compresor propio: el `ProviderScope` toma [compresor] en vez del de los dobles.
Future<ArnesTicket> montar427(
  WidgetTester tester, {
  required Size tamano,
  double escala = 1,
  CompresorDeImagen? compresor,
  CapturadorDePrueba? capturador,
  Cobranza? cobro,
}) async {
  final arnes = nuevoArnesTicket(capturador: capturador);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cobroAbierto = cobro ?? cobroConTarjeta();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ticketRepositoryProvider.overrideWithValue(arnes.repo),
        capturadorDeFotoProvider.overrideWithValue(arnes.capturador),
        compresorDeImagenProvider.overrideWithValue(compresor ?? arnes.compresor),
        servidorDeFotosDeTicketProvider.overrideWithValue(arnes.servidor),
        monitorConectividadProvider.overrideWithValue(arnes.conexion),
        generadorIdTicketProvider.overrideWithValue(() {
          final id = 'tk-${arnes.idsGenerados.length + 1}';
          arnes.idsGenerados.add(id);
          return id;
        }),
        relojTicketProvider.overrideWithValue(() => arnes.ahora),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await FlujoTicketDeTarjeta.abrir(
                    context,
                    cobro: cobroAbierto,
                    colportorId: 'col-1',
                    subtitulo: 'María Fernández · Mataojo 2044 · 3B',
                  );
                  arnes.resultados.add(r);
                },
                child: const Text('abrir ticket'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await abrirTicket(tester);
  return arnes;
}

/// Escribe en un campo (lo trae a la vista primero: la lista es perezosa con letra grande).
Future<void> escribir427(WidgetTester tester, Finder campo, String texto) async {
  await traerTicketAlAlcance(tester, campo);
  await tester.enterText(campo, texto);
  await asentarAgendar(tester, 3);
}

/// Baja la pantalla hasta el final (lo de abajo de una lista perezosa no está armado hasta entonces).
Future<void> irAlFinal427(WidgetTester tester) async {
  final lista = find.descendant(of: paginaTicket, matching: find.byType(Scrollable));
  if (lista.evaluate().isEmpty) return;
  await tester.drag(lista.first, const Offset(0, -4000));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 29A-03: el cobro con tarjeta registrado, con la foto del ticket por delante.
Future<({ArnesCobro cobro, ArnesTicket ticket})> llevarA29A03(
  WidgetTester tester, {
  Tamano? tamano,
  double escala = 1,
}) async {
  final size = tamano == null ? const Size(390, 844) : Size(tamano.ancho, tamano.alto);
  final ticket = nuevoArnesTicket();
  final cobro = await montarCobro(
    tester,
    escala: escala,
    tamano: size,
    overrides: overridesDeTicket(ticket, conConexion: false),
  );
  await tocarCobro(tester, find.byKey(const Key('cobro_medio_1')));
  await escribirMonto(tester, '1200');
  await tocarCobro(tester, botonRegistrar);
  return (cobro: cobro, ticket: ticket);
}
