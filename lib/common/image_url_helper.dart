/// 图片链接兼容处理：只做链接补全与协议修正，不强制替换域名。
class ImageUrlHelper {
  /// 将解析出来的 img src 规范化为可请求的绝对 URL（不强制换域名）
  static String normalize(String src) {
    var s = src.trim();
    if (s.isEmpty) return s;

    // //xxx 这种协议相对链接
    if (s.startsWith('//')) {
      s = 'https:$s';
    }

    // /xxx 这种路径相对链接（通常挂在站点根目录）
    if (s.startsWith('/')) {
      // 图片通常在 pic 域名下，这里用官方域名兜底
      s = 'https://pic.wenku8.com$s';
    }

    // 尝试解析
    Uri uri;
    try {
      uri = Uri.parse(s);
    } catch (_) {
      return s;
    }

    // 有些页面可能会给出 http，这里尽量升级到 https（更少被拦截）
    if (uri.scheme == 'http') {
      uri = uri.replace(scheme: 'https');
      return uri.toString();
    }

    return s;
  }
}
