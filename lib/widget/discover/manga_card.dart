// ignore_for_file: deprecated_member_use

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../models/manga.dart';
import '../../services/mangadx_service.dart';

class MangaCard extends StatelessWidget {
  final Manga manga;
  final VoidCallback? onTap;
  final MangaDexService? mangaDexService;

  const MangaCard({
    super.key,
    required this.manga,
    this.onTap,
    this.mangaDexService,
  });

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: manga.description ?? manga.title,
      child: Container(
        width: 160,
        height: 280, // Fixed height to prevent overflow
        margin: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image
            Expanded(
              flex: 3,
              child: Container(
                width: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: MacosTheme.brightnessOf(context).resolve(
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.3),
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: _buildCoverImage(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Title - Use Expanded to prevent overflow
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MacosTheme.of(context).typography.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
            // Tags - Use flexible space
            if (manga.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 20, // Fixed height for tags
                  child: Wrap(
                    spacing: 4,
                    children: manga.tags.take(2).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MacosTheme.brightnessOf(context).resolve(
                            const Color(0xFFF2F2F7),
                            const Color(0xFF2C2C2E),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag,
                          style: MacosTheme.of(context)
                              .typography
                              .caption1
                              .copyWith(
                                fontSize: 10,
                              ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    return Builder(
      builder: (context) {
        // If manga already has a cover URL, display it directly
        if (manga.coverImageUrl != null) {
          return Image.network(
            manga.coverImageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildPlaceholder(context);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: ProgressCircle(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  radius: 20,
                ),
              );
            },
          );
        }

        // If no cover URL and service is available, use FutureBuilder to load it
        if (mangaDexService != null) {
          return FutureBuilder<Manga>(
            future: mangaDexService!.loadMangaCover(manga),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.coverImageUrl != null) {
                return Image.network(
                  snapshot.data!.coverImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholder(context);
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: ProgressCircle(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        radius: 20,
                      ),
                    );
                  },
                );
              }

              // Show placeholder with small loading indicator while fetching cover URL
              return Stack(
                children: [
                  _buildPlaceholder(context),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const ProgressCircle(radius: 8),
                      ),
                    ),
                ],
              );
            },
          );
        }

        // Fallback to placeholder if no service provided
        return _buildPlaceholder(context);
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: MacosTheme.brightnessOf(context).resolve(
        const Color(0xFFF2F2F7),
        const Color(0xFF2C2C2E),
      ),
      child: Center(
        child: MacosIcon(
          CupertinoIcons.book,
          size: 48,
          color: MacosTheme.brightnessOf(context).resolve(
            const Color(0xFF8E8E93),
            const Color(0xFF636366),
          ),
        ),
      ),
    );
  }
}
