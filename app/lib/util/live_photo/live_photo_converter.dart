import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:localsend_app/model/live_photo/photo_brand.dart';
import 'package:localsend_app/util/live_photo/live_photo_detector.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('LivePhotoConverter');

/// 转换后的一个产物（静帧或视频）。
class ConvertedLivePhoto {
  final String path;
  final String fileName;
  final bool isStill;

  const ConvertedLivePhoto({
    required this.path,
    required this.fileName,
    required this.isStill,
  });
}

/// 把一个品牌的动态照片转换成"目标品牌相册能原生识别"的格式。
///
/// 跨品牌规则：
/// - 源=安卓内嵌 → 目标=iOS：抽取静帧 + 视频，分别输出 `<base>.jpg` 与 `<base>.mov`（Live Photo 配对）。
/// - 源=iOS 配对 → 目标=安卓：把静帧 + 视频合成单个 JPEG（视频 trailer + XMP 微视频偏移）。
/// - 源/目标同为安卓：容器本就通用（Micro Video 格式），直接透传，仅刷新 XMP 偏移即可。
/// - 源/目标同为 iOS：透传。
///
/// 抽取静帧/视频优先用 Dart 字节切片（基于检测出的 `MicroVideoOffset`），
/// 仅在需要把视频重封装为目标容器（如 iOS 的 .mov）时才调用 ffmpeg。
Future<List<ConvertedLivePhoto>> convertLivePhoto({
  required String sourcePath,
  required PhotoBrand sourceBrand,
  required PhotoBrand targetBrand,
  required LivePhotoDetection detection,
  required String outputDir,
}) async {
  if (sourceBrand == targetBrand || !detection.isLivePhoto) {
    // 同品牌或并非动态照片：无需转换。
    return [ConvertedLivePhoto(path: sourcePath, fileName: p.basename(sourcePath), isStill: true)];
  }

  // 1) 取出源静帧与源视频字节。
  final (stillBytes, videoBytes) = await _extractStillAndVideo(sourcePath, detection);
  if (stillBytes == null || videoBytes == null) {
    _logger.warning('无法从 $sourcePath 抽取静帧/视频，跳过转换');
    return [ConvertedLivePhoto(path: sourcePath, fileName: p.basename(sourcePath), isStill: true)];
  }

  final base = p.basenameWithoutExtension(sourcePath);
  await Directory(outputDir).create(recursive: true);

  if (targetBrand == PhotoBrand.ios) {
    // iOS Live Photo：静帧 + 伴生视频。
    final stillExt = _stillExtFromBytes(stillBytes);
    final stillOut = p.join(outputDir, '$base.$stillExt');
    final videoOut = p.join(outputDir, '$base.mov');
    await File(stillOut).writeAsBytes(stillBytes);
    final ok = await _remuxToMov(videoBytes, videoOut);
    if (!ok) {
      // ffmpeg 失败则退回写原始视频扩展名，保证至少有文件可传。
      final fallback = p.join(outputDir, '$base.mp4');
      await File(fallback).writeAsBytes(videoBytes);
      return [
        ConvertedLivePhoto(path: stillOut, fileName: p.basename(stillOut), isStill: true),
        ConvertedLivePhoto(path: fallback, fileName: p.basename(fallback), isStill: false),
      ];
    }
    return [
      ConvertedLivePhoto(path: stillOut, fileName: p.basename(stillOut), isStill: true),
      ConvertedLivePhoto(path: videoOut, fileName: p.basename(videoOut), isStill: false),
    ];
  }

  // 目标为安卓：合成单个 JPEG（静帧 + 视频 trailer + XMP 微视频标记）。
  final stillWithXmp = _injectMicroVideoXmp(stillBytes, videoBytes.length);
  final combined = <int>[...stillWithXmp, ...videoBytes];
  final outPath = p.join(outputDir, '$base.jpg');
  await File(outPath).writeAsBytes(combined);
  return [ConvertedLivePhoto(path: outPath, fileName: p.basename(outPath), isStill: true)];
}

/// 从源文件抽取静帧与视频字节。
Future<(Uint8List?, Uint8List?)> _extractStillAndVideo(String sourcePath, LivePhotoDetection detection) async {
  final bytes = await File(sourcePath).readAsBytes();
  if (detection.embedded != null) {
    final offset = detection.embedded!.offset;
    if (offset <= 0 || offset >= bytes.length) return (bytes, null);
    final still = bytes.sublist(0, offset);
    final video = bytes.sublist(offset);
    return (still, video);
  }
  if (detection.companionVideoPath != null) {
    final video = await File(detection.companionVideoPath!).readAsBytes();
    return (bytes, video);
  }
  return (bytes, null);
}

/// 用 ffmpeg 把视频字节重封装为 .mov（iOS Live Photo 需要）。
Future<bool> _remuxToMov(Uint8List videoBytes, String outPath) async {
  final tmp = '$outPath.src.tmp';
  await File(tmp).writeAsBytes(videoBytes);
  try {
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      tmp,
      '-c',
      'copy',
      outPath,
    ]);
    final rc = await session.getReturnCode();
    return rc != null && ReturnCode.isSuccess(rc);
  } catch (e) {
    _logger.warning('ffmpeg 重封装失败', e);
    return false;
  } finally {
    try {
      await File(tmp).delete();
    } catch (_) {}
  }
}

/// 根据 JPEG/HEIC 魔术字推断静帧扩展名。
String _stillExtFromBytes(Uint8List bytes) {
  if (bytes.length > 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70 && // 'ftyp'
      bytes[8] == 0x68 &&
      bytes[9] == 0x65 &&
      bytes[10] == 0x69 &&
      bytes[11] == 0x63) {
    return 'heic';
  }
  return 'jpg';
}

/// 在 JPEG 的 SOI 之后注入一段 XMP（APP1），写入 Micro Video 微视频标记，
/// 使安卓相册能把"静帧 + 视频 trailer"识别为动态照片。
Uint8List _injectMicroVideoXmp(Uint8List still, int videoOffset) {
  if (still.length < 2 || still[0] != 0xFF || still[1] != 0xD8) {
    return still; // 非 JPEG 不注入。
  }
  final xmp = _buildMicroVideoXmp(videoOffset);
  final identifier = 'http://ns.adobe.com/xap/1.0/';
  final payload = <int>[
    ...identifier.codeUnits,
    0x00,
    ...xmp.codeUnits,
  ];
  // APP1 段：FF E1 + 长度(2字节，含长度字段本身) + payload。
  final length = payload.length + 2;
  final segment = <int>[
    0xFF,
    0xE1,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...payload,
  ];
  return Uint8List.fromList([0xFF, 0xD8, ...segment, ...still.sublist(2)]);
}

/// 生成 Micro Video XMP 文本（安卓厂商通用格式）。
String _buildMicroVideoXmp(int videoOffset) {
  return '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
    xmlns:GCamera="http://ns.google.com/photos/1.0/device/"
    Camera:MotionPhoto="1"
    Camera:MotionPhotoVersion="1"
    GCamera:MicroVideo="1"
    GCamera:MicroVideoVersion="1"
    GCamera:MicroVideoOffset="$videoOffset"
    GCamera:MicroVideoPresentationTimestampUs="150000"/>
 </rdf:Description>
</r:xmpmeta>'''
      .trim();
}
