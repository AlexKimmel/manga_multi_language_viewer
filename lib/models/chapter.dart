class Chapter {
  final String id;
  final String title;
  final String? chapterNumber;
  final String? volumeNumber;
  final String language;
  final int pages;
  final DateTime? publishedAt;
  final String? translatedLanguage;
  final String? scanlationGroup;

  Chapter({
    required this.id,
    required this.title,
    this.chapterNumber,
    this.volumeNumber,
    required this.language,
    required this.pages,
    this.publishedAt,
    this.translatedLanguage,
    this.scanlationGroup,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>;

    return Chapter(
      id: json['id'],
      title: attributes['title'] ?? '',
      chapterNumber: attributes['chapter'],
      volumeNumber: attributes['volume'],
      language: attributes['translatedLanguage'] ?? 'en',
      pages: attributes['pages'] ?? 0,
      publishedAt: attributes['publishAt'] != null
          ? DateTime.tryParse(attributes['publishAt'])
          : null,
      translatedLanguage: attributes['translatedLanguage'],
      scanlationGroup: null, // Can be populated from relationships if needed
    );
  }
}

class ChapterResponse {
  final List<Chapter> data;
  final int total;
  final int limit;
  final int offset;

  ChapterResponse({
    required this.data,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory ChapterResponse.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>;
    final chapters = dataList.map((item) => Chapter.fromJson(item)).toList();

    return ChapterResponse(
      data: chapters,
      total: json['total'] ?? 0,
      limit: json['limit'] ?? 0,
      offset: json['offset'] ?? 0,
    );
  }
}

class LanguageInfo {
  final String code;
  final String name;
  final String flag;

  const LanguageInfo({
    required this.code,
    required this.name,
    required this.flag,
  });
}

// Common languages for manga
class SupportedLanguages {
  static const List<LanguageInfo> languages = [
    LanguageInfo(code: 'en', name: 'English', flag: '🇺🇸'),
    LanguageInfo(code: 'ja', name: 'Japanese', flag: '🇯🇵'),
    LanguageInfo(code: 'ko', name: 'Korean', flag: '🇰🇷'),
    LanguageInfo(code: 'zh', name: 'Chinese (Simplified)', flag: '🇨🇳'),
    LanguageInfo(code: 'zh-hk', name: 'Chinese (Traditional)', flag: '🇭🇰'),
    LanguageInfo(code: 'es', name: 'Spanish', flag: '🇪🇸'),
    LanguageInfo(code: 'fr', name: 'French', flag: '🇫🇷'),
    LanguageInfo(code: 'de', name: 'German', flag: '🇩🇪'),
    LanguageInfo(code: 'pt', name: 'Portuguese', flag: '🇵🇹'),
    LanguageInfo(code: 'pt-br', name: 'Portuguese (Brazil)', flag: '🇧🇷'),
    LanguageInfo(code: 'ru', name: 'Russian', flag: '🇷🇺'),
    LanguageInfo(code: 'it', name: 'Italian', flag: '🇮🇹'),
    LanguageInfo(code: 'th', name: 'Thai', flag: '🇹🇭'),
    LanguageInfo(code: 'vi', name: 'Vietnamese', flag: '🇻🇳'),
    LanguageInfo(code: 'id', name: 'Indonesian', flag: '🇮🇩'),
    LanguageInfo(code: 'ar', name: 'Arabic', flag: '🇸🇦'),
  ];

  static LanguageInfo? getLanguageInfo(String code) {
    try {
      return languages.firstWhere((lang) => lang.code == code);
    } catch (e) {
      return null;
    }
  }

  static String getLanguageName(String code) {
    final info = getLanguageInfo(code);
    return info?.name ?? code.toUpperCase();
  }

  static String getLanguageFlag(String code) {
    final info = getLanguageInfo(code);
    return info?.flag ?? '🌐';
  }
}
