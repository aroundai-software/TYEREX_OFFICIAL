import 'dart:math';

/// Generates a standard RFC-4122 Version 4 compliant UUID string.
/// Example: `f81d4fae-7dec-11d0-a765-00a0c91e6bf6`
String generateUuidV4() {
  final Random random = Random.secure();
  final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));

  // Set version (4) in the 4 most significant bits of byte 6
  values[6] = (values[6] & 0x0f) | 0x40;

  // Set variant (RFC 4122) in the 2 most significant bits of byte 8
  values[8] = (values[8] & 0x3f) | 0x80;

  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) {
      buffer.write('-');
    }
    buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
