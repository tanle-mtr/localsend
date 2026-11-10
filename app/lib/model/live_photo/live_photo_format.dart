import 'package:localsend_app/model/live_photo/photo_brand.dart';

/// 描述某个品牌"动态照片"的容器结构，供转换器重组文件时使用。
///
/// 设计目标：跨品牌传输时，发送端把源品牌的动态照片转换成"目标品牌能原生识别"的格式，
/// 让接收方相册直接显示为动态图，而不是一张静止图 + 一个看不懂的视频。
class LivePhotoFormat {
  final PhotoBrand brand;

  /// 容器形态：单文件内嵌（安卓系）还是 静帧+视频 两文件（iOS）。
  final LivePhotoContainer container;

  /// 静态帧常用的封装扩展名（不含点），如 jpg / heic。
  final String stillExt;

  /// 伴生视频的封装扩展名（不含点），iOS 为 mov，安卓内嵌时不需要。
  final String? videoExt;

  /// 内嵌视频在 JPEG/HEIC 文件中的存放方式。
  final EmbeddedVideoLayout embeddedLayout;

  const LivePhotoFormat({
    required this.brand,
    required this.container,
    required this.stillExt,
    this.videoExt,
    this.embeddedLayout = EmbeddedVideoLayout.trailer,
  });

  /// iOS Live Photo：一张静帧（jpg/heic）+ 一段 mov 视频，二者通过
  /// 相同的 ContentIdentifier（写在静帧 XMP 与视频的 `mvhd`/`moov` 中）配对。
  static const LivePhotoFormat ios = LivePhotoFormat(
    brand: PhotoBrand.ios,
    container: LivePhotoContainer.pair,
    stillExt: 'jpg',
    videoExt: 'mov',
  );

  /// 安卓系"微视频（Micro Video）"通用格式：在 JPEG/HEIC 的 EOI 之后追加一段视频，
  /// 并用 XMP 标记 `Camera:MotionPhoto=1`、`MicroVideo=1`、`MicroVideoOffset=<视频在文件中的偏移>`、
  /// `MicroVideoPresentationTimestampUs`。Google Photos、三星、小米、OPPO、vivo 等相册均能识别。
  static const LivePhotoFormat androidMicroVideo = LivePhotoFormat(
    brand: PhotoBrand.samsung,
    container: LivePhotoContainer.embedded,
    stillExt: 'jpg',
    embeddedLayout: EmbeddedVideoLayout.trailer,
  );

  static LivePhotoFormat forBrand(PhotoBrand brand) {
    switch (brand) {
      case PhotoBrand.ios:
        return ios;
      case PhotoBrand.unknown:
        return androidMicroVideo;
      default:
        return androidMicroVideo;
    }
  }
}

/// 动态照片的容器形态。
enum LivePhotoContainer {
  /// 单文件内嵌：静帧图片里直接塞了视频（安卓厂商主流做法）。
  embedded,

  /// 两文件配对：静帧 + 伴生视频（iOS Live Photo）。
  pair,
}

/// 内嵌视频在静帧文件中的位置。
enum EmbeddedVideoLayout {
  /// 视频追加在图片数据（EOI 标记）之后。
  trailer,
}
