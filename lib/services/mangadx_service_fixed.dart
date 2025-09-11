import 'package:dio/dio.dart';
import '../models/manga.dart';

class MangaDexService {
  static const String baseUrl = 'https://api.mangadex.org';
  static const String coversUrl = 'https://uploads.mangadx.org/covers';

  final Dio _dio;

  MangaDexService(this._dio);

  Future<MangaResponse> searchManga({
    String? title,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'limit': limit,
        'offset': offset,
        'includes[]': ['cover_art'],
        'order[rating]': 'desc',
        'contentRating[]': ['safe', 'suggestive'],
      };

      if (title != null && title.isNotEmpty) {
        queryParams['title'] = title;
      }

      final response = await _dio.get('/manga', queryParameters: queryParams);

      if (response.statusCode == 200) {
        final mangaResponse = MangaResponse.fromJson(response.data);

        // Fetch cover images for each manga
        final mangasWithCovers = await _addCoverImages(mangaResponse.data);

        return MangaResponse(
          data: mangasWithCovers,
          total: mangaResponse.total,
          limit: mangaResponse.limit,
          offset: mangaResponse.offset,
        );
      } else {
        throw Exception('Failed to load manga: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
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
      final response = await _dio.get('/cover', queryParameters: {
        'manga[]': mangaId,
        'limit': 1,
      });

      if (response.statusCode == 200) {
        final data = response.data['data'] as List<dynamic>;
        if (data.isNotEmpty) {
          final coverData = data.first;
          final fileName = coverData['attributes']['fileName'];
          return 'https://uploads.mangadx.org/covers/$mangaId/$fileName.256.jpg';
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<MangaResponse> getPopularManga({
    int limit = 20,
    int offset = 0,
  }) async {
    return searchManga(limit: limit, offset: offset);
  }
}
