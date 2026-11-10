import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:localsend_app/model/live_photo/photo_brand.dart';

/// 检测"动态照片"的结果。
class LivePhotoDetection {
  /// 是否为动态照片（内嵌或配对形式）。
  final bool isLivePhoto;

  /// 检测到的来源品牌；若无法从文件内容判断，则回退为 [fallbackBrand]。
  final PhotoBrand brand;

  /// 若为内嵌式（安卓），给出视频在文件中的偏移与长度（若有）。
  final EmbeddedVideoInfo? embedded;

  /// 若为配对式（iOS），给出伴生视频路径（若同目录下存在）。
  final String? companionVideoPath;

  const LivePhotoDetection({
    required this.isLivePhoto,
    required this.brand,
    this.embedded,
    this.companionVideoPath,
  });

  LivePhotoDetection.notLive(this.brand)
      : isLivePhoto = false,
        embedded = null,
        companionVideoPath = null;
}

/// 内嵌视频在文件中的区间信息。
class EmbeddedVideoInfo {
  /// 视频数据起点（字节偏移，相对于文件头）。
  final int offset;

  /// 视频字节长度；未知时为 null。
  final int? length;

  const EmbeddedVideoInfo({required this.offset, this.length});
}

/// 扫描 JPEG/HEIC 头部的 XMP，判断是否为"内嵌式动态照片"（安卓 Motion Photo / Micro Video）。
///
/// 判据：文件以 JPEG 魔术字 `FF D8 FF` 开头，且 XMP 中含以下任一标记：
/// - `Camera:MotionPhoto` / `MotionPhoto=1`
/// - `MicroVideo` / `MicroVideoOffset`
/// - `GCamera` / `HwMavi` / `Xiaomi` 等厂商标记
Future<LivePhotoDetection> detectLivePhoto({
  required String path,
  String? fileName,
  PhotoBrand fallbackBrand = PhotoBrand.unknown,
  int headerBytes = 4 * 1024 * 1024,
}) async {
  final file = File(path);
  if (!file.existsSync()) {
    return LivePhotoDetection.notLive(fallbackBrand);
  }

  final Uint8List head;
  try {
    head = Uint8List.fromList(await file.openRead(0, headerBytes).first);
  } catch (_) {
    return LivePhotoDetection.notLive(fallbackBrand);
  }

  // 必须是 JPEG（HEIC 的动态照片检测较复杂，先只处理 JPEG 内嵌场景）。
  if (head.length < 3 || head[0] != 0xFF || head[1] != 0xD8 || head[2] != 0xFF) {
    return LivePhotoDetection.notLive(fallbackBrand);
  }

  final text = latin1.decode(head, allowInvalid: true);
  final isMotion = text.contains('MotionPhoto') ||
      text.contains('MicroVideo') ||
      text.contains('Camera:MotionPhoto') ||
      text.contains('HwMavi') ||
      text.contains('Xiaomi') && text.contains('MicroVideo');

  if (!isMotion) {
    // 退一步：检查是否为 iOS Live Photo 的"静帧 + 伴生视频"配对。
    final pair = _detectIosPair(path);
    if (pair != null) {
      return LivePhotoDetection(
        isLivePhoto: true,
        brand: PhotoBrand.ios,
        companionVideoPath: pair,
      );
    }
    return LivePhotoDetection.notLive(fallbackBrand);
  }

  final brand = _brandFromXmp(text) ?? fallbackBrand;
  final offset = _extractMicroVideoOffset(text);
  return LivePhotoDetection(
    isLivePhoto: true,
    brand: brand,
    embedded: offset != null ? EmbeddedVideoInfo(offset: offset) : null,
  );
}

/// 从 XMP 文本里猜测厂商（仅作展示/日志用，不影响转码逻辑）。
PhotoBrand? _brandFromXmp(String xmp) {
  if (xmp.contains('GCamera') || xmp.contains('google')) return PhotoBrand.google;
  if (xmp.contains('HwMavi') || xmp.contains('huawei') || xmp.contains('honor')) return PhotoBrand.huawei;
  if (xmp.contains('Xiaomi') || xmp.contains('redmi') || xmp.contains('poco')) return PhotoBrand.xiaomi;
  if (xmp.contains('Oppo') || xmp.contains('OnePlus') || xmp.contains('realme')) return PhotoBrand.oppo;
  if (xmp.contains('vivo')) return PhotoBrand.vivo;
  if (xmp.contains('Camera:MotionPhoto') || xmp.contains('Samsung')) return PhotoBrand.samsung;
  return null;
}

/// 解析 XMP 中的 `MicroVideoOffset`（视频段在文件中的字节偏移）。
int? _extractMicroVideoOffset(String xmp) {
  final regex = RegExp(r'MicroVideoOffset[=:]["\s]*(\d+)');
  final match = regex.firstMatch(xmp);
  return match != null ? int.tryParse(match.group(1)!) : null;
}

/// 若 [stillPath] 是 iOS Live Photo 的静帧，尝试在同目录找到同名 .mov 伴生视频。
String? _detectIosPair(String stillPath) {
  final lower = stillPath.toLowerCase();
  if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg') && !lower.endsWith('.heic')) {
    return null;
  }
  final withoutExt = stillPath.substring(0, stillPath.length - fileExt(stillPath).length);
  for (final ext in ['.MOV', '.mov', '.MP4', '.mp4']) {
    final candidate = '$withoutExt$ext';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// 小工具：返回带点的扩展名（含点），无扩展名时返回空串。
String fileExt(String path) {
  final idx = path.lastIndexOf('.');
  if (idx <= 0) return '';
  return path.substring(idx);
}
