import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Najdlhšia strana fotky, ktorá sa posiela do AI. Viac netreba,
/// model aj tak väčšie obrázky zmenšuje a platí sa za veľkosť.
const int maxPhotoSide = 1024;
const int jpegQuality = 80;

final _picker = ImagePicker();

/// Odfotí jedlo ([ImageSource.camera]) alebo ho vyberie z galérie
/// ([ImageSource.gallery]) a rovno ho pripraví na odoslanie.
/// Vráti null, ak používateľ výber zrušil.
Future<Uint8List?> pickMealPhoto(ImageSource source) async {
  final file = await _picker.pickImage(
    source: source,
    // hrubé zmenšenie už pri výbere, aby sa do pamäte nenačítalo 12 MPx
    maxWidth: maxPhotoSide * 2,
    maxHeight: maxPhotoSide * 2,
  );
  if (file == null) return null;
  return prepareMealPhoto(await file.readAsBytes());
}

/// Predspracovanie pred odoslaním: otočí fotku podľa EXIF, zmenší ju
/// na [maxPhotoSide] a uloží ako JPEG. Beží v samostatnom isolate,
/// aby nesekalo UI.
Future<Uint8List> prepareMealPhoto(Uint8List bytes) {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Súbor nie je obrázok.');
    }
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxPhotoSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxPhotoSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxPhotoSide, interpolation: img.Interpolation.average);
    }
    return img.encodeJpg(image, quality: jpegQuality);
  });
}
