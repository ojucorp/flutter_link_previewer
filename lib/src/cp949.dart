import 'code_map.dart';


class CP949 {
  static List<int> toUnicodes(final List<int> codeUnits) {
    final unicodes = List<int>.filled(codeUnits.length, 0);
    var j = 0;
    for (var i = 0; i < codeUnits.length; j++) {
      // When 1 byte becomes 1 cp949 code
      if (0x00 <= codeUnits[i] && codeUnits[i] <= 0x7F) {
        unicodes[j] = cp949ToUnicodeCodeMap[codeUnits[i]]!;
        i = i + 1;
      } else {
        // When 2 bytes become 1 cp949 code
        final cp949Code = (codeUnits[i] << 8) + codeUnits[i + 1];
        i = i + 2;
        if (0x8141 <= cp949Code && cp949Code <= 0xFDFE) {
          unicodes[j] = cp949ToUnicodeCodeMap[cp949Code]!;
        } else {
          throw const FormatException(
              'Invalid code unit of CP949. It has to be (>=0x00 <=0x7F) || (>=0x8141 <=0xFDFE).');
        }
      }
    }
    return unicodes.sublist(0, j);
  }

  static String decode(final List<int> codeUnits) {
    return String.fromCharCodes(toUnicodes(codeUnits));
  }
}