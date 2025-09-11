class Manga {
  final String id;
  final String title;
  final String? description;
  final List<String> tags;
  final String? coverImageUrl;
  final String status;
  final int? year;
  final String? author;

  Manga({
    required this.id,
    required this.title,
    this.description,
    required this.tags,
    this.coverImageUrl,
    required this.status,
    this.year,
    this.author,
  });

  factory Manga.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>;
    final title = attributes['title'] as Map<String, dynamic>;

    // Get title in English or first available language
    String mangaTitle = '';
    if (title.containsKey('en')) {
      mangaTitle = title['en'];
    } else if (title.isNotEmpty) {
      mangaTitle = title.values.first;
    }

    // Extract tags
    final tagsList = attributes['tags'] as List<dynamic>? ?? [];
    final tags = tagsList
        .map((tag) => tag['attributes']['name']['en'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return Manga(
      id: json['id'],
      title: mangaTitle,
      description: attributes['description']?['en'],
      tags: tags,
      status: attributes['status'] ?? 'unknown',
      year: attributes['year'],
      author: null, // Will be populated separately if needed
    );
  }
}

class MangaResponse {
  final List<Manga> data;
  final int total;
  final int limit;
  final int offset;

  MangaResponse({
    required this.data,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory MangaResponse.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>;
    final mangas = dataList.map((item) => Manga.fromJson(item)).toList();

    return MangaResponse(
      data: mangas,
      total: json['total'] ?? 0,
      limit: json['limit'] ?? 0,
      offset: json['offset'] ?? 0,
    );
  }
}
