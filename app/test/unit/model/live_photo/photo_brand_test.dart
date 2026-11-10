import 'package:localsend_app/model/live_photo/photo_brand.dart';
import 'package:test/test.dart';

void main() {
  group('brandFromDeviceModel', () {
    test('detects iOS from common model prefixes', () {
      expect(brandFromDeviceModel('iPhone14,2'), PhotoBrand.ios);
      expect(brandFromDeviceModel('iPad13,1'), PhotoBrand.ios);
      expect(brandFromDeviceModel('iPod9,1'), PhotoBrand.ios);
    });

    test('detects Samsung', () {
      expect(brandFromDeviceModel('SM-G998B'), PhotoBrand.samsung);
      expect(brandFromDeviceModel('Galaxy S23'), PhotoBrand.samsung);
      expect(brandFromDeviceModel('samsung SM-A536B'), PhotoBrand.samsung);
    });

    test('detects Google', () {
      expect(brandFromDeviceModel('Pixel 7'), PhotoBrand.google);
      expect(brandFromDeviceModel('Pixel 8 Pro'), PhotoBrand.google);
      expect(brandFromDeviceModel('Nexus 5'), PhotoBrand.google);
    });

    test('detects Xiaomi family', () {
      expect(brandFromDeviceModel('Xiaomi 13'), PhotoBrand.xiaomi);
      expect(brandFromDeviceModel('Redmi Note 12'), PhotoBrand.xiaomi);
      expect(brandFromDeviceModel('POCO F5'), PhotoBrand.xiaomi);
      // "Mi " with a space avoids false positives on unrelated words.
      expect(brandFromDeviceModel('Mi 11'), PhotoBrand.xiaomi);
    });

    test('detects OPPO family', () {
      expect(brandFromDeviceModel('OPPO Find X5'), PhotoBrand.oppo);
      expect(brandFromDeviceModel('OnePlus 11'), PhotoBrand.oppo);
      expect(brandFromDeviceModel('realme GT'), PhotoBrand.oppo);
      expect(brandFromDeviceModel('CPH2449'), PhotoBrand.oppo);
    });

    test('detects vivo and Huawei', () {
      expect(brandFromDeviceModel('vivo X90'), PhotoBrand.vivo);
      expect(brandFromDeviceModel('HUAWEI Mate 50'), PhotoBrand.huawei);
      expect(brandFromDeviceModel('HONOR Magic5'), PhotoBrand.huawei);
    });

    test('returns unknown for empty / null / unrecognized', () {
      expect(brandFromDeviceModel(null), PhotoBrand.unknown);
      expect(brandFromDeviceModel(''), PhotoBrand.unknown);
      expect(brandFromDeviceModel('  '), PhotoBrand.unknown);
      expect(brandFromDeviceModel('SomeDesktop PC'), PhotoBrand.unknown);
    });

    test('is case-insensitive', () {
      expect(brandFromDeviceModel('IPHONE14,2'), PhotoBrand.ios);
      expect(brandFromDeviceModel('samsung sm-g998b'), PhotoBrand.samsung);
    });
  });

  group('PhotoBrand helpers', () {
    test('isEmbeddedMotion is true for Android brands, false for iOS', () {
      expect(PhotoBrand.ios.isEmbeddedMotion, isFalse);
      expect(PhotoBrand.unknown.isEmbeddedMotion, isFalse);
      expect(PhotoBrand.samsung.isEmbeddedMotion, isTrue);
      expect(PhotoBrand.google.isEmbeddedMotion, isTrue);
    });

    test('isPhone is false only for unknown', () {
      expect(PhotoBrand.unknown.isPhone, isFalse);
      expect(PhotoBrand.ios.isPhone, isTrue);
      expect(PhotoBrand.huawei.isPhone, isTrue);
    });

    test('displayName is non-empty for every brand', () {
      for (final b in PhotoBrand.values) {
        expect(b.displayName, isNotEmpty);
      }
    });
  });

  group('fileNameLooksLikePhotoContainer', () {
    test('matches common photo extensions', () {
      expect(fileNameLooksLikePhotoContainer('IMG_001.jpg'), isTrue);
      expect(fileNameLooksLikePhotoContainer('photo.JPEG'), isTrue);
      expect(fileNameLooksLikePhotoContainer('live.HEIC'), isTrue);
      expect(fileNameLooksLikePhotoContainer('clip.heif'), isTrue);
      expect(fileNameLooksLikePhotoContainer('pic.png'), isTrue);
    });

    test('rejects non-photo extensions', () {
      expect(fileNameLooksLikePhotoContainer('movie.mp4'), isFalse);
      expect(fileNameLooksLikePhotoContainer('doc.pdf'), isFalse);
    });
  });
}
