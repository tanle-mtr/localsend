import 'dart:io';

import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/live_photo/photo_brand.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/live_photo/live_photo_converter.dart';
import 'package:localsend_app/util/live_photo/live_photo_detector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 动态照片转换的运行时状态（仅用于 UI 提示，不参与持久化）。
class LivePhotoState {
  /// 正在进行的转换任务数。
  final int convertingCount;

  /// 最近一次转换产出的临时文件路径，便于会话结束后清理。
  final List<String> tempPaths;

  /// 最近一次转换中无法转换、只能按静态图发送的动态照片数量（用于 UI 提示，#2703）。
  final int unconvertedCount;

  const LivePhotoState({this.convertingCount = 0, this.tempPaths = const [], this.unconvertedCount = 0});

  LivePhotoState copyWith({int? convertingCount, List<String>? tempPaths, int? unconvertedCount}) {
    return LivePhotoState(
      convertingCount: convertingCount ?? this.convertingCount,
      tempPaths: tempPaths ?? this.tempPaths,
      unconvertedCount: unconvertedCount ?? this.unconvertedCount,
    );
  }
}

/// 负责"跨品牌动态照片自动适配"：在发送前，把本机动态照片转换成目标设备品牌相册能识别的格式。
///
/// 使用方式：在 [sendProvider] 发起会话前调用 [convertForTarget]，用返回的文件列表替换原列表即可。
final livePhotoProvider = NotifierProvider<LivePhotoNotifier, LivePhotoState>((ref) {
  return LivePhotoNotifier();
});

class LivePhotoNotifier extends Notifier<LivePhotoState> {
  @override
  LivePhotoState init() => const LivePhotoState();

  /// 把 [files] 中需要转换的动态照片，转换为 [targetBrand] 的格式。
  /// 不修改入参；若未开启自动转换、或两端品牌相同，则原样返回。
  Future<List<CrossFile>> convertForTarget(List<CrossFile> files, PhotoBrand targetBrand) async {
    state = state.copyWith(unconvertedCount: 0);
    final settings = ref.read(settingsProvider);
    if (!settings.autoConvertLivePhoto) return files;

    final sourceBrand = brandFromDeviceModel(ref.read(deviceInfoProvider).deviceModel);
    if (!sourceBrand.isPhone || !targetBrand.isPhone || sourceBrand == targetBrand) {
      return files;
    }

    state = state.copyWith(convertingCount: state.convertingCount + 1);
    final newTempPaths = <String>[];
    var unconverted = 0;
    try {
      final outDir = await _tempDir();
      final result = <CrossFile>[];
      for (final file in files) {
        if (file.path == null) {
          result.add(file);
          continue;
        }
        final detection = await detectLivePhoto(
          path: file.path!,
          fileName: file.name,
          fallbackBrand: sourceBrand,
        );
        if (!detection.isLivePhoto) {
          result.add(file);
          continue;
        }

        final converted = await convertLivePhoto(
          sourcePath: file.path!,
          sourceBrand: sourceBrand,
          targetBrand: targetBrand,
          detection: detection,
          outputDir: outDir,
        );
        if (converted.isEmpty) {
          unconverted++;
          result.add(file);
          continue;
        }

        // 主文件（静帧）替换原条目；其余产物（如 iOS 的伴生视频）追加为额外文件。
        final main = converted.first;
        newTempPaths.add(main.path);
        result.add(
          file.copyWith(
            name: _withBaseName(file.name, main.fileName),
            path: main.path,
            size: await File(main.path).length(),
          ),
        );
        for (final extra in converted.skip(1)) {
          newTempPaths.add(extra.path);
          result.add(
            CrossFile(
              name: _withBaseName(file.name, extra.fileName),
              fileType: file.fileType,
              size: await File(extra.path).length(),
              thumbnail: null,
              asset: null,
              path: extra.path,
              bytes: null,
              lastModified: null,
              lastAccessed: null,
            ),
          );
        }
      }
      state = state.copyWith(tempPaths: [...state.tempPaths, ...newTempPaths], unconvertedCount: unconverted);
      return result;
    } catch (e) {
      // 转换失败不应阻断发送：回退为原始文件。
      return files;
    } finally {
      state = state.copyWith(convertingCount: (state.convertingCount - 1).clamp(0, 1 << 30));
    }
  }

  /// 清理某次发送产生的临时文件（在会话结束后调用）。
  Future<void> clearTemp() async {
    for (final path in state.tempPaths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    state = state.copyWith(tempPaths: const []);
  }

  Future<String> _tempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'localsend_live_photo'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// 保留原始文件名的主名，套用转换产物的扩展名。
  String _withBaseName(String originalName, String convertedName) {
    final base = p.basenameWithoutExtension(originalName);
    final ext = p.extension(convertedName);
    return '$base$ext';
  }
}
