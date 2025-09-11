import 'package:dio/dio.dart';
import '../models/manga.dart';

class MangaDexService {
  static const String baseUrl = 'https://api.mangadex.org';
  static const String coversUrl = 'https://uploads.mangadex.org/covers';

  final Dio _dio;

  MangaDexService(this._dio);

  Future<MangaResponse> searchManga({
    required String query,
    int limit = 24,
    int offset = 0,
    List<String> contentRatings = const ['safe', 'suggestive'],
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
}
