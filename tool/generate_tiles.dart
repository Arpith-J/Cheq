import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int size = 128;

class RGB {
  final int r, g, b;
  const RGB(this.r, this.g, this.b);
  RGB lerp(RGB other, double t) => RGB(
        (r + (other.r - r) * t).round().clamp(0, 255),
        (g + (other.g - g) * t).round().clamp(0, 255),
        (b + (other.b - b) * t).round().clamp(0, 255),
      );
}

class Noise {
  final math.Random _rnd;
  late final List<int> _perm;
  late final List<double> _vals;

  Noise(int seed) : _rnd = math.Random(seed) {
    _perm = List<int>.generate(256, (i) => i);
    for (int i = 255; i > 0; i--) {
      final j = _rnd.nextInt(i + 1);
      final t = _perm[i];
      _perm[i] = _perm[j];
      _perm[j] = t;
    }
    _vals = List<double>.generate(256, (_) => _rnd.nextDouble());
  }

  double sample(double x, double y, int wrap) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;
    final u = xf * xf * (3 - 2 * xf);
    final v = yf * yf * (3 - 2 * yf);
    int px(int i) => _perm[((i % wrap) + wrap) % wrap];
    final a = _vals[(px(xi) + yi) % wrap];
    final b = _vals[(px(xi + 1) + yi) % wrap];
    final c = _vals[(px(xi) + yi + 1) % wrap];
    final d = _vals[(px(xi + 1) + yi + 1) % wrap];
    final top = a + u * (b - a);
    final bot = c + u * (d - c);
    return top + v * (bot - top);
  }
}

void main() {
  final dir = Directory('assets/images');
  dir.createSync(recursive: true);

  _writePng('${dir.path}/grass_tile.png', _grass());
  _writePng('${dir.path}/dirt_tile.png', _dirt());
  _writePng('${dir.path}/snow_tile.png', _snow());
  stdout.writeln('Generated 3 tile textures.');
}

Uint8List _basePixel(Noise n, RGB base, RGB deep, RGB light,
    double xScale, double yScale, int wrap, double xOff, double yOff) {
  final px = Uint8List(size * size * 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final n1 = n.sample(x / xScale + xOff, y / yScale + yOff, wrap);
      final n2 = n.sample(x / (xScale * 4) + xOff * 2, y / (yScale * 4) + yOff * 2, wrap);
      final t = n1 * 0.65 + n2 * 0.35;
      final pick = t < 0.42 ? deep : (t > 0.66 ? light : base);
      final blend = 0.55 + 0.45 * (n1 - 0.5).abs() * 2;
      final c = base.lerp(pick, 1 - blend);
      final i = (y * size + x) * 4;
      px[i] = c.r;
      px[i + 1] = c.g;
      px[i + 2] = c.b;
      px[i + 3] = 255;
    }
  }
  return px;
}

Uint8List _grass() {
  final n = Noise(11);
  final px = _basePixel(
      n, const RGB(128, 165, 86), const RGB(96, 138, 62), const RGB(158, 194, 110), 32, 32, 64, 0, 0);
  final rnd = math.Random(11);
  for (int i = 0; i < 600; i++) {
    final x = rnd.nextInt(size);
    final y = rnd.nextInt(size);
    final len = 3 + rnd.nextInt(4);
    final dx = rnd.nextInt(3) - 1;
    final dy = 1 + rnd.nextInt(3);
    final lighter = rnd.nextBool();
    final c = lighter ? const RGB(172, 205, 122) : const RGB(88, 128, 54);
    _drawLine(px, x, y, x + dx * len, y + dy * len, c);
  }
  return px;
}

Uint8List _dirt() {
  final n = Noise(22);
  final px = _basePixel(
      n, const RGB(146, 104, 66), const RGB(108, 72, 44), const RGB(178, 136, 92), 28, 28, 64, 40, 40);
  final rnd = math.Random(22);
  for (int i = 0; i < 90; i++) {
    final x = rnd.nextInt(size);
    final y = rnd.nextInt(size);
    final rad = 1 + rnd.nextInt(3);
    final grey = 90 + rnd.nextInt(60);
    _drawCircle(px, x, y, rad, RGB(grey, grey, grey - 10));
  }
  for (int i = 0; i < 900; i++) {
    final x = rnd.nextInt(size);
    final y = rnd.nextInt(size);
    final v = 40 + rnd.nextInt(140) - 90;
    _set(px, x, y, RGB((146 + v).clamp(0, 255), (104 + v).clamp(0, 255), (66 + v).clamp(0, 255)));
  }
  return px;
}

Uint8List _snow() {
  final n = Noise(33);
  final px = _basePixel(
      n, const RGB(236, 244, 252), const RGB(198, 216, 236), const RGB(252, 254, 255), 30, 30, 64, 70, 70);
  final rnd = math.Random(33);
  for (int i = 0; i < 700; i++) {
    final x = rnd.nextInt(size);
    final y = rnd.nextInt(size);
    final v = rnd.nextInt(100) - 50;
    _set(px, x, y, RGB((236 + v * 0.6).round().clamp(0, 255),
        (244 + v * 0.7).round().clamp(0, 255), (252 + v).round().clamp(0, 255)));
  }
  for (int i = 0; i < 80; i++) {
    final x = rnd.nextInt(size);
    final y = rnd.nextInt(size);
    _drawCircle(px, x, y, 1 + rnd.nextInt(2), const RGB(255, 255, 255));
  }
  return px;
}

void _set(Uint8List px, int x, int y, RGB c) {
  if (x < 0 || y < 0 || x >= size || y >= size) return;
  final i = (y * size + x) * 4;
  px[i] = c.r;
  px[i + 1] = c.g;
  px[i + 2] = c.b;
}

void _drawLine(Uint8List px, int x0, int y0, int x1, int y1, RGB c) {
  final dx = (x1 - x0).abs();
  final dy = -(y1 - y0).abs();
  final sx = x0 < x1 ? 1 : -1;
  final sy = y0 < y1 ? 1 : -1;
  var err = dx + dy;
  var x = x0, y = y0;
  while (true) {
    _set(px, x, y, c);
    if (x == x1 && y == y1) break;
    final e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y += sy;
    }
  }
}

void _drawCircle(Uint8List px, int cx, int cy, int rad, RGB c) {
  for (int y = -rad; y <= rad; y++) {
    for (int x = -rad; x <= rad; x++) {
      if (x * x + y * y <= rad * rad) {
        _set(px, cx + x, cy + y, c);
      }
    }
  }
}

// ── Minimal PNG encoder (zlib via dart:io) ─────────────────────────────

void _writePng(String path, Uint8List rgba) {
  final stride = size * 4;
  final raw = Uint8List((stride + 1) * size);
  for (int y = 0; y < size; y++) {
    final rowStart = y * (stride + 1);
    raw[rowStart] = 0; // filter: none
    raw.setRange(rowStart + 1, rowStart + 1 + stride, rgba, y * stride);
  }
  final compressed = ZLibCodec(level: 9).encode(raw);

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = BytesBuilder();
  ihdr.add(_u32(size)); // width
  ihdr.add(_u32(size)); // height
  ihdr.addByte(8); // bit depth
  ihdr.addByte(6); // color type: RGBA
  ihdr.addByte(0); // compression
  ihdr.addByte(0); // filter
  ihdr.addByte(0); // interlace
  _chunk(out, 'IHDR', ihdr.toBytes());

  _chunk(out, 'IDAT', compressed);

  _chunk(out, 'IEND', const []);

  File(path).writeAsBytesSync(out.toBytes());
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  out.add(_u32(data.length));
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out.add(typeBytes);
  out.add(data);
  final crc = _crc32(Uint8List.fromList([...typeBytes, ...data]));
  out.add(_u32(crc));
}

Uint8List _u32(int v) {
  return Uint8List.fromList([
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ]);
}

int _crc32(Uint8List data) {
  const table = <int>[
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F,
    0xE963A535, 0x9E6495A3, 0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
    0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91, 0x1DB71064, 0x6AB020F2,
    0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9,
    0xFA0F3D63, 0x8D080DF5, 0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
    0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B, 0x35B5A8FA, 0x42B2986C,
    0xDBBB9D86, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423,
    0xCFBA9599, 0xB8BDA50F, 0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
    0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D, 0x76DC4190, 0x01DB7106,
    0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D,
    0x91646C97, 0xE6635C01, 0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
    0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457, 0x65B0D9C6, 0x12B7E950,
    0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7,
    0xA4D1C46D, 0xD3D6F4FB, 0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
    0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9, 0x5005713C, 0x270241AA,
    0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81,
    0xB7BD5C3B, 0xC0BA6CAD, 0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A,
    0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683, 0xE3630B12, 0x94643B84,
    0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB,
    0x196C3671, 0x6E6B06E7, 0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
    0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5, 0xD6D6A3E8, 0xA1D1937E,
    0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55,
    0x316E8EEF, 0x4669BE79, 0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
    0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F, 0xC5BA3BBE, 0xB2BD0B28,
    0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F,
    0x72076785, 0x05005713, 0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38,
    0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21, 0x86D3D2D4, 0xF1D4E242,
    0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69,
    0x616BFFD3, 0x166CCF45, 0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
    0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB, 0xAED16A4A, 0xD9D65ADC,
    0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693,
    0x54DE5729, 0x23D967BF, 0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
    0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
  ];
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = (crc >> 8) ^ table[(crc ^ byte) & 0xFF];
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
