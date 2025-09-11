import 'package:dio/dio.dart';
import '../models/manga.dart';
import '../models/chapter.dart';

class MangaDexService {
  static const String baseUrl = 'https://api.mangadex.org';
  static const String coversUrl = 'https://uploads.mangadex.org/covers';

  final Dio _dio;

  MangaDexService(this._dio);

  Future<MangaResponse> searchManga({
    required String query,
    int limit = 24,
    int offset = 0,
    List<String> contentRatings = const ['safe'],
    List<String> includes = const ['cover_art'],
    bool loadCoversImmediately = false,
  }) async {
    try {
      // Build query parameters with proper list-valued keys for MangaDex.
      // Dio encodes List values by repeating the key, which is what MangaDx expects (e.g., contentRating[]=safe&contentRating[]=suggestive).
      final Map<String, dynamic> params = {
        if (query.trim().isNotEmpty) 'title': query.trim(),
        'limit': limit,
        'offset': offset,
        'contentRating[]': contentRatings, // <— List
        'includes[]': includes, // <— List (e.g. ['cover_art'])
      };

      // Use absolute URL unless your Dio has BaseOptions(baseUrl: MangaDexService.baseUrl).
      final response = await _dio.get('${MangaDexService.baseUrl}/manga',
          queryParameters: params);

      if (response.statusCode == 200) {
        final mangaResponse = MangaResponse.fromJson(response.data);

        // Optionally enrich with cover URLs (see _getCoverImageUrl below)
        final mangasWithCovers = loadCoversImmediately
            ? await _addCoverImages(mangaResponse.data)
            : mangaResponse.data;

        return MangaResponse(
          data: mangasWithCovers,
          total: mangaResponse.total,
          limit: mangaResponse.limit,
          offset: mangaResponse.offset,
        );
      } else {
        throw Exception(
            'Failed to load manga: ${response.statusCode} ${response.statusMessage}');
      }
    } on DioException catch (e) {
      // Surface server response body if present for easier debugging
      final detail = e.response?.data ?? e.message;
      throw Exception('Network error: $detail');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  Future<List<Manga>> _addCoverImages(List<Manga> mangas) async {
    final List<Manga> mangasWithCovers = [];

    for (final manga in mangas) {
      try {
        final coverUrl = await _getCoverImageUrl(manga.id);
        final updatedManga = Manga(
          id: manga.id,
          title: manga.title,
          description: manga.description,
          tags: manga.tags,
          coverImageUrl: coverUrl,
          status: manga.status,
          year: manga.year,
          author: manga.author,
        );
        mangasWithCovers.add(updatedManga);
      } catch (e) {
        // If cover fetch fails, add manga without cover
        mangasWithCovers.add(manga);
      }
    }

    return mangasWithCovers;
  }

  Future<String?> _getCoverImageUrl(String mangaId) async {
    try {
      final response = await _dio.get(
        '${MangaDexService.baseUrl}/cover',
        queryParameters: {
          'manga[]': [mangaId], // <— must be manga[] and a List
          'limit': 1,
          'order[createdAt]': 'desc', // newest first (optional)
        },
      );

      if (response.statusCode == 200) {
        final data = (response.data['data'] as List<dynamic>? ?? const []);
        if (data.isNotEmpty) {
          final coverData = data.first as Map<String, dynamic>;
          final attrs =
              (coverData['attributes'] as Map<String, dynamic>? ?? const {});
          final fileName = attrs['fileName'] as String?;
          if (fileName != null && fileName.isNotEmpty) {
            // Use the fixed coversUrl constant and ask for a 256px resized variant.
            return '${MangaDexService.coversUrl}/$mangaId/$fileName.256.jpg';
          }
        }
      }
      return null;
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<MangaResponse> getPopularManga({
    int limit = 20,
    int offset = 0,
    bool loadCoversImmediately = false,
  }) async {
    return searchManga(
      query: '',
      limit: limit,
      offset: offset,
      loadCoversImmediately: loadCoversImmediately,
    );
  }

  /// Load cover image for a single manga asynchronously
  Future<Manga> loadMangaCover(Manga manga) async {
    if (manga.coverImageUrl != null) {
      return manga; // Already has cover
    }

    try {
      final coverUrl = await _getCoverImageUrl(manga.id);
      return Manga(
        id: manga.id,
        title: manga.title,
        description: manga.description,
        tags: manga.tags,
        coverImageUrl: coverUrl,
        status: manga.status,
        year: manga.year,
        author: manga.author,
      );
    } catch (e) {
      return manga; // Return original if cover fetch fails
    }
  }

  /// Fetch chapters for a specific manga
  Future<ChapterResponse> getMangaChapters({
    required String mangaId,
    List<String> translatedLanguages = const ['en'],
    int limit = 100,
    int offset = 0,
    Map<String, String> order = const {'chapter': 'asc'},
  }) async {
    try {
      final Map<String, dynamic> params = {
        'manga': mangaId,
        'limit': limit,
        'offset': offset,
        'translatedLanguage[]': translatedLanguages,
        'order[chapter]': order['chapter'] ?? 'asc',
        'order[volume]': order['volume'] ?? 'asc',
        'includes[]': ['scanlation_group'],
      };

      final response = await _dio.get(
        '$baseUrl/chapter',
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        return ChapterResponse.fromJson(response.data);
      } else {
        throw Exception(
            'Failed to load chapters: ${response.statusCode} ${response.statusMessage}');
      }
    } on DioException catch (e) {
      final detail = e.response?.data ?? e.message;
      throw Exception('Network error: $detail');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  /// Get available languages for a manga
  Future<List<String>> getMangaAvailableLanguages(String mangaId) async {
    try {
      final response = await _dio.get(
        '$baseUrl/chapter',
        queryParameters: {
          'manga': mangaId,
          'limit': 0, // We only want the total count and available languages
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as List<dynamic>? ?? [];
        final languages = <String>{};

        for (final chapter in data) {
          final attributes =
              chapter['attributes'] as Map<String, dynamic>? ?? {};
          final translatedLanguage =
              attributes['translatedLanguage'] as String?;
          if (translatedLanguage != null) {
            languages.add(translatedLanguage);
          }
        }

        return languages.toList()..sort();
      } else {
        throw Exception('Failed to load available languages');
      }
    } on DioException catch (e) {
      final detail = e.response?.data ?? e.message;
      throw Exception('Network error: $detail');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  /// Get detailed manga information including all available descriptions
  Future<Manga> getMangaDetails(String mangaId) async {
    try {
      final response = await _dio.get(
        '$baseUrl/manga/$mangaId',
        queryParameters: {
          'includes[]': ['cover_art', 'author', 'artist'],
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final manga = Manga.fromJson(data);

        // Load cover image
        final coverUrl = await _getCoverImageUrl(mangaId);

        return Manga(
          id: manga.id,
          title: manga.title,
          description: manga.description,
          tags: manga.tags,
          coverImageUrl: coverUrl,
          status: manga.status,
          year: manga.year,
          author: manga.author,
        );
      } else {
        throw Exception('Failed to load manga details');
      }
    } on DioException catch (e) {
      final detail = e.response?.data ?? e.message;
      throw Exception('Network error: $detail');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }
}
