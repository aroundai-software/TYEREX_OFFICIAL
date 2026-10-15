import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final image = img.decodePng(File('assets/images/app_logo.png').readAsBytesSync());
  if (image != null) {
    // Resize image to typical ICO sizes if needed, or just 256x256
    final resized = img.copyResize(image, width: 256, height: 256);
    
    // Check if encodeIco exists
    final icoData = img.encodeIco(resized);
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(icoData);
    print('ICO generated successfully!');
  } else {
    print('Failed to decode PNG');
  }
}
