// Los adaptadores de la foto del ticket (#443, decisión de Cristian del 03/11 en #169): la cámara con
// image_picker y el compresor con flutter_image_compress, con la parte nativa reemplazada.
import 'package:colportores_mobile/features/tickets/data/services/capturador_image_picker.dart';
import 'package:colportores_mobile/features/tickets/data/services/compresor_flutter_image_compress.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../helpers/logger_mudo.dart';

/// `ImagePicker` guionado: devuelve [archivo] o lanza [error], y anota el origen y si pidió metadatos.
final class _Picker extends ImagePicker {
  _Picker({this.archivo, this.error});

  final XFile? archivo;
  final Object? error;
  final pedidos = <({ImageSource origen, bool metadatos})>[];

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    pedidos.add((origen: source, metadatos: requestFullMetadata));
    final e = error;
    if (e != null) throw e;
    return archivo;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));

  group('CapturadorImagePicker', () {
    CapturadorImagePicker capturador(_Picker picker) =>
        CapturadorImagePicker(picker: picker, logger: loggerMudo());

    test(
      'la cámara devuelve los bytes de la foto, sin pedir los metadatos (ni la ubicación)',
      () async {
        final picker = _Picker(archivo: XFile.fromData(bytes, name: 'ticket.jpg'));

        final r = await capturador(picker).sacarFoto();

        expect(r, isA<FotoCapturada>());
        expect((r as FotoCapturada).bytes, bytes);
        expect(picker.pedidos.single, (origen: ImageSource.camera, metadatos: false));
      },
    );

    test('la galería usa el mismo camino', () async {
      final picker = _Picker(archivo: XFile.fromData(bytes, name: 'ticket.jpg'));
      final r = await capturador(picker).elegirDeLaGaleria();
      expect(r, isA<FotoCapturada>());
      expect(picker.pedidos.single.origen, ImageSource.gallery);
    });

    test('cerrar sin elegir es cancelar', () async {
      expect(await capturador(_Picker()).sacarFoto(), isA<CapturaCancelada>());
    });

    test('un archivo vacío es una falla', () async {
      final picker = _Picker(archivo: XFile.fromData(Uint8List(0), name: 'vacio.jpg'));
      expect(await capturador(picker).sacarFoto(), isA<CapturaFallida>());
    });

    test('el permiso negado de la cámara o de las fotos es «sin permiso»', () async {
      for (final codigo in ['camera_access_denied', 'photo_access_denied']) {
        final picker = _Picker(error: PlatformException(code: codigo));
        expect(await capturador(picker).sacarFoto(), isA<CapturaSinPermiso>(), reason: codigo);
      }
    });

    test('otra falla de la plataforma o una excepción cualquiera es «falló», sin lanzar', () async {
      expect(
        await capturador(
          _Picker(error: PlatformException(code: 'no_available_camera')),
        ).sacarFoto(),
        isA<CapturaFallida>(),
      );
      expect(
        await capturador(_Picker(error: StateError('x'))).elegirDeLaGaleria(),
        isA<CapturaFallida>(),
      );
    });

    test('abrir los ajustes no hace nada y no lanza', () async {
      await capturador(_Picker()).abrirLosAjustes();
    });
  });

  group('CompresorFlutterImageCompress', () {
    test('medidasObjetivo deja el lado mayor en el máximo y conserva la proporción', () {
      expect(CompresorFlutterImageCompress.medidasObjetivo(4000, 3000, 1600), (
        ancho: 1600,
        alto: 1200,
      ));
      expect(CompresorFlutterImageCompress.medidasObjetivo(3000, 4000, 1600), (
        ancho: 1200,
        alto: 1600,
      ));
    });

    test('medidasObjetivo nunca agranda una foto chica ni deja un lado en cero', () {
      expect(CompresorFlutterImageCompress.medidasObjetivo(800, 600, 1600), (
        ancho: 800,
        alto: 600,
      ));
      expect(CompresorFlutterImageCompress.medidasObjetivo(1600, 1600, 1600), (
        ancho: 1600,
        alto: 1600,
      ));
      expect(CompresorFlutterImageCompress.medidasObjetivo(10000, 1, 1000), (ancho: 1000, alto: 1));
    });

    test(
      'pide al nativo el mínimo que deja el lado mayor en el máximo, con la calidad dada',
      () async {
        final pedidos = <({int ancho, int alto, int calidad})>[];
        final compresor = CompresorFlutterImageCompress(
          medir: (_) async => (ancho: 4000, alto: 3000),
          recodificar: (b, {required anchoMinimo, required altoMinimo, required calidad}) async {
            pedidos.add((ancho: anchoMinimo, alto: altoMinimo, calidad: calidad));
            return Uint8List.fromList([1, 2, 3]);
          },
        );

        final salida = await compresor.comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 70);

        expect(salida, [1, 2, 3]);
        expect(pedidos.single, (ancho: 1600, alto: 1200, calidad: 70));
      },
    );

    test('la calidad fuera de 1 a 100 se acota', () async {
      final calidades = <int>[];
      final compresor = CompresorFlutterImageCompress(
        medir: (_) async => (ancho: 10, alto: 10),
        recodificar: (b, {required anchoMinimo, required altoMinimo, required calidad}) async {
          calidades.add(calidad);
          return Uint8List.fromList([1]);
        },
      );
      await compresor.comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 0);
      await compresor.comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 300);
      expect(calidades, [1, 100]);
    });

    test('lo que no es una imagen, una salida vacía o una excepción devuelven null', () async {
      Future<Uint8List?> recodificaVacio(
        Uint8List b, {
        required int anchoMinimo,
        required int altoMinimo,
        required int calidad,
      }) async => Uint8List(0);

      expect(
        await CompresorFlutterImageCompress(
          medir: (_) async => null,
          recodificar: recodificaVacio,
        ).comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 70),
        isNull,
      );
      expect(
        await CompresorFlutterImageCompress(
          medir: (_) async => (ancho: 0, alto: 10),
          recodificar: recodificaVacio,
        ).comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 70),
        isNull,
      );
      expect(
        await CompresorFlutterImageCompress(
          medir: (_) async => (ancho: 10, alto: 10),
          recodificar: recodificaVacio,
        ).comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 70),
        isNull,
      );
      expect(
        await CompresorFlutterImageCompress(
          medir: (_) async => throw StateError('códec'),
          recodificar: recodificaVacio,
        ).comprimirComoJpeg(bytes, ladoMaximo: 1600, calidad: 70),
        isNull,
      );
    });

    test('el medidor real lee las medidas de un PNG sin decodificarlo entero', () async {
      // PNG de 2×3 píxeles.
      final png = Uint8List.fromList(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03, //
        0x08, 0x02, 0x00, 0x00, 0x00, 0x36, 0x88, 0x49, 0xD6, 0x00, 0x00, 0x00, //
        0x10, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
        0x44, 0x0C, 0x28, 0x14, 0x00, 0x44, 0xD0, 0x05, 0xFB, 0xA4, 0xCF, 0xDE, //
        0x80, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, //
        0x82, //
      ]);
      ({int ancho, int alto, int calidad})? pedido;
      final compresor = CompresorFlutterImageCompress(
        recodificar: (b, {required anchoMinimo, required altoMinimo, required calidad}) async {
          pedido = (ancho: anchoMinimo, alto: altoMinimo, calidad: calidad);
          return Uint8List.fromList([9]);
        },
      );

      final salida = await compresor.comprimirComoJpeg(png, ladoMaximo: 1600, calidad: 80);

      expect(salida, [9]);
      expect(pedido, (ancho: 2, alto: 3, calidad: 80));
    });
  });
}
