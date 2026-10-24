import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/common/charset_type.dart';
import '../models/common/language.dart';
import '../service/local_storage_service.dart';

Locale resolveAppLocale() {
  return switch (LocalStorageService.instance.language.value) {
    Language.traditionalChinese => const Locale("zh", "TW"),
    Language.simplifiedChinese => const Locale("zh", "CN"),
    Language.followSystem => Get.deviceLocale == const Locale("zh", "TW") ? const Locale("zh", "TW") : const Locale("zh", "CN"),
  };
}

CharsetType charsetForLocale(Locale locale) => locale == const Locale("zh", "TW") ? CharsetType.big5Hkscs : CharsetType.gbk;
