/// 动态图（Live Photo / Motion Photo）相关的"设备品牌"识别。
///
/// 不同手机厂商把"动态照片"存成完全不同的容器格式：
/// - iOS：Live Photo = 一张静帧（JPG/HEIC）+ 一段伴生视频（MOV，含 ContentIdentifier）。
/// - 安卓各厂商：大多把"静帧 + 短视频"塞进同一个 JPEG/HEIC 里（视频 trailer + XMP 微视频偏移），
///   例如三星 Motion Photo、Google Motion Photo、小米/红米、OPPO/一加、vivo、华为 动态照片。
///
/// 本文件只负责"从设备型号 / 文件名判断品牌"，是纯 Dart、可在单测中验证的核心逻辑。

library;

/// 已知的手机品牌（仅含支持动态照片的厂商）。
enum PhotoBrand {
  ios,
  samsung,
  google,
  xiaomi,
  oppo, // 含 OnePlus / realme
  vivo,
  huawei, // 含 Honor
  unknown;

  /// 该品牌是否使用"单文件内嵌视频"的动态照片容器。
  /// iOS 使用"静帧 + 伴生视频"两文件方案，其余安卓厂商均为单文件内嵌。
  bool get isEmbeddedMotion => switch (this) {
        PhotoBrand.ios => false,
        PhotoBrand.unknown => false,
        _ => true,
      };

  /// 是否为已知手机品牌（unknown 不算）。
  bool get isPhone => this != PhotoBrand.unknown;

  /// 该品牌动态照片对外展示的本地化名称（用于 UI 与日志）。
  String get displayName => switch (this) {
        PhotoBrand.ios => 'iOS Live Photo',
        PhotoBrand.samsung => 'Samsung Motion Photo',
        PhotoBrand.google => 'Google Motion Photo',
        PhotoBrand.xiaomi => 'Xiaomi Motion Photo',
        PhotoBrand.oppo => 'OPPO / OnePlus Motion',
        PhotoBrand.vivo => 'vivo Dynamic Photo',
        PhotoBrand.huawei => 'Huawei Moving Picture',
        PhotoBrand.unknown => 'Unknown',
      };
}

/// 根据 `device_info_plus` 提供的设备型号字符串推断品牌。
///
/// 各厂商型号规律（取常见前缀/关键字，大小写不敏感）：
/// - iOS：iPhone / iPad / iPod。
/// - 三星：SM- / Galaxy / Samsung。
/// - Google：Pixel / Nexus / walleye / sailfish / marlin / blueline / coral 等。
/// - 小米系：Xiaomi / Redmi / POCO / Mi （注意 "Mi " 易误命中，用更长关键字）。
/// - OPPO 系：OPPO / OnePlus / realme / CPH / RMX / PGx。
/// - vivo：vivo / V2xxx（型号多为 V 开头数字，但单独数字不可靠，故以 vivo 前缀为主）。
/// - 华为系：HUAWEI / HONOR / ANA / ELE / ALP / ELS / VOG / HW-。
PhotoBrand brandFromDeviceModel(String? model) {
  final m = model?.trim();
  if (m == null || m.isEmpty) return PhotoBrand.unknown;
  final lower = m.toLowerCase();

  if (lower.startsWith('iphone') ||
      lower.startsWith('ipad') ||
      lower.startsWith('ipod') ||
      lower.startsWith('mac')) {
    return PhotoBrand.ios;
  }

  if (lower.startsWith('sm-') ||
      lower.startsWith('galaxy') ||
      lower.contains('samsung')) {
    return PhotoBrand.samsung;
  }

  if (lower.startsWith('pixel') ||
      lower.startsWith('nexus') ||
      lower.startsWith('walleye') ||
      lower.startsWith('sailfish') ||
      lower.startsWith('marlin') ||
      lower.startsWith('blueline') ||
      lower.startsWith('coral') ||
      lower.startsWith('sunfish')) {
    return PhotoBrand.google;
  }

  if (lower.startsWith('xiaomi') ||
      lower.startsWith('redmi') ||
      lower.startsWith('poco') ||
      lower.startsWith('mi ')) {
    return PhotoBrand.xiaomi;
  }

  if (lower.startsWith('oppo') ||
      lower.startsWith('oneplus') ||
      lower.startsWith('realme') ||
      lower.startsWith('cph') ||
      lower.startsWith('rmx') ||
      lower.startsWith('pg')) {
    return PhotoBrand.oppo;
  }

  if (lower.startsWith('vivo')) {
    return PhotoBrand.vivo;
  }

  if (lower.startsWith('huawei') ||
      lower.startsWith('honor') ||
      lower.startsWith('hw-') ||
      lower.startsWith('ana-') ||
      lower.startsWith('ele-') ||
      lower.startsWith('alp-') ||
      lower.startsWith('els-') ||
      lower.startsWith('vog-')) {
    return PhotoBrand.huawei;
  }

  return PhotoBrand.unknown;
}

/// 根据文件名（含扩展名）做粗粒度品牌猜测，用于"收到文件但无设备型号"的兜底。
///
/// 目前的动态照片扩展名几乎都是图片格式（.jpg/.jpeg/.heic/.png），
/// 单凭扩展名无法区分品牌，因此这里只做"是否为图片容器"的判定，
/// 真实品牌仍以 [brandFromDeviceModel] 的结果为准。
bool fileNameLooksLikePhotoContainer(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif') ||
      lower.endsWith('.png');
}
