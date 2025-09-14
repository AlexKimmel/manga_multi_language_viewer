import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../models/manga.dart';
import '../models/chapter.dart';
import '../services/mangadx_service.dart';
import '../providers/settings_provider.dart';
import 'dual_chapter_reader.dart';

class MangaInfoPage extends StatefulWidget {
  final Manga manga;

  const MangaInfoPage({
    super.key,
    required this.manga,
  });

  @override
  State<MangaInfoPage> createState() => _MangaInfoPageState();
}

class _MangaInfoPageState extends State<MangaInfoPage> {
  late MangaDexService _mangaDexService;

  Manga? _detailedManga;
  List<Chapter> _chapters = [];
  // When two languages are selected, we create pairs of chapters present in both languages
  List<_ChapterPair> _chapterPairs = [];
  List<String> _availableLanguages = [];
  bool _isLoadingChapters = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _mangaDexService = MangaDexService(context.read<Dio>());
    _loadMangaInfo();
  }

  Future<void> _loadMangaInfo() async {
    await Future.wait([
      _loadMangaDetails(),
      _loadAvailableLanguages(),
    ]);

    // Load chapters after we know the available languages
    await _loadChapters();
  }

  Future<void> _loadMangaDetails() async {
    try {
      final details = await _mangaDexService.getMangaDetails(widget.manga.id);
      if (mounted) {
        setState(() {
          _detailedManga = details;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load manga details: $e';
        });
      }
    }
  }

  Future<void> _loadAvailableLanguages() async {
    try {
      final languages =
          await _mangaDexService.getMangaAvailableLanguages(widget.manga.id);
      if (mounted) {
        setState(() {
          _availableLanguages = languages;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _loadChapters() async {
    try {
      setState(() {
        _isLoadingChapters = true;
        _chapters = [];
        _chapterPairs = [];
      });
      final settings = context.read<SettingsProvider>();
      final primary = settings.primaryLanguage;
      final secondary = settings.secondaryLanguage;

      // If the same language is selected twice, just fetch once
      if (primary == secondary) {
        final single = await _mangaDexService.getMangaChapters(
          mangaId: widget.manga.id,
          translatedLanguages: [primary],
          limit: 500,
        );
        if (mounted) {
          setState(() {
            _chapters = single.data;
            _isLoadingChapters = false;
          });
        }
        return;
      }

      // Fetch both languages completely (paged) and intersect by normalized chapter number
      final results = await Future.wait<List<Chapter>>([
        _fetchAllChaptersForLanguage(primary),
        _fetchAllChaptersForLanguage(secondary),
      ]);

      final primaryChapters = results[0];
      final secondaryChapters = results[1];

      final Map<String, Chapter> primaryByKey = {};
      for (final c in primaryChapters) {
        final key = _normalizedChapterKey(c);
        if (key != null && !primaryByKey.containsKey(key)) {
          primaryByKey[key] = c;
        }
      }

      final Map<String, Chapter> secondaryByKey = {};
      for (final c in secondaryChapters) {
        final key = _normalizedChapterKey(c);
        if (key != null && !secondaryByKey.containsKey(key)) {
          secondaryByKey[key] = c;
        }
      }

      final keys = primaryByKey.keys
          .toSet()
          .intersection(secondaryByKey.keys.toSet())
          .toList()
        ..sort((a, b) => _chapterSortValue(a).compareTo(_chapterSortValue(b)));

      // Build paired list: a single entry per chapter key containing both languages
      final pairs = <_ChapterPair>[];
      for (final k in keys) {
        pairs.add(_ChapterPair(
          key: k,
          primary: primaryByKey[k]!,
          secondary: secondaryByKey[k]!,
        ));
      }

      if (mounted) {
        setState(() {
          _chapterPairs = pairs;
          _isLoadingChapters = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load chapters: $e';
          _isLoadingChapters = false;
        });
      }
    }
  }

  // Fetch all chapters for a language with pagination (up to ~1000 for safety)
  Future<List<Chapter>> _fetchAllChaptersForLanguage(String lang) async {
    const pageSize = 100; // MangaDex caps per page at 100
    int offset = 0;
    final List<Chapter> all = [];
    for (int i = 0; i < 10; i++) {
      // hard cap 10 pages -> 1000 items
      final resp = await _mangaDexService.getMangaChapters(
        mangaId: widget.manga.id,
        translatedLanguages: [lang],
        limit: pageSize,
        offset: offset,
        order: const {'chapter': 'asc'},
      );
      all.addAll(resp.data);
      if (resp.data.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  // Normalize to canonical key: take numeric prefix if present (e.g., '5a' -> '5', '10.0' -> '10'), else use raw lowercased.
  String? _normalizedChapterKey(Chapter c) {
    final raw = c.chapterNumber?.trim();
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'^[0-9]+(?:\.[0-9]+)?').firstMatch(raw);
    if (match != null) {
      final numStr = match.group(0)!;
      final n = double.tryParse(numStr);
      if (n != null) {
        final fixed = n.toStringAsFixed(6);
        return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
      }
      return numStr;
    }
    return raw.toLowerCase();
  }

  num _chapterSortValue(String key) {
    final match = RegExp(r'^[0-9]+(?:\.[0-9]+)?').firstMatch(key);
    if (match != null) {
      final n = double.tryParse(match.group(0)!);
      if (n != null) return n;
    }
    return double.infinity;
  }

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      toolBar: ToolBar(
        title: Text(_detailedManga?.title ?? widget.manga.title,
            style: const TextStyle(overflow: TextOverflow.ellipsis)),
        leading: MacosTooltip(
          message: 'Back',
          useMousePosition: false,
          child: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            if (_errorMessage != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const MacosIcon(
                      CupertinoIcons.exclamationmark_triangle,
                      size: 64,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error',
                      style: MacosTheme.of(context).typography.headline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: MacosTheme.of(context).typography.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          _isLoadingChapters = true;
                        });
                        _loadMangaInfo();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            return CustomScrollView(
              controller: scrollController,
              slivers: [
                // Header with cover image and basic info
                SliverToBoxAdapter(
                  child: _buildHeader(),
                ),

                // Language Settings
                SliverToBoxAdapter(
                  child: _buildLanguageSettings(),
                ),

                // Description
                SliverToBoxAdapter(
                  child: _buildDescription(),
                ),

                // Tags
                SliverToBoxAdapter(
                  child: _buildTags(),
                ),

                // Chapters List
                SliverToBoxAdapter(
                  child: _buildChaptersSection(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final manga = _detailedManga ?? widget.manga;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover Image
          Container(
            width: 180,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: MacosTheme.brightnessOf(context).resolve(
                    // ignore: deprecated_member_use
                    Colors.black.withOpacity(0.1),
                    // ignore: deprecated_member_use
                    Colors.black.withOpacity(0.3),
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: manga.coverImageUrl != null
                  ? Image.network(
                      manga.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildCoverPlaceholder();
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: ProgressCircle(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            radius: 24,
                          ),
                        );
                      },
                    )
                  : _buildCoverPlaceholder(),
            ),
          ),

          const SizedBox(width: 24),

          // Manga Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manga.title,
                  style: MacosTheme.of(context).typography.largeTitle.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                if (manga.author != null) ...[
                  Text(
                    'By ${manga.author}',
                    style: MacosTheme.of(context).typography.headline.copyWith(
                          color: MacosTheme.brightnessOf(context).resolve(
                            const Color(0xFF8E8E93),
                            const Color(0xFF636366),
                          ),
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    _buildInfoChip('Status', manga.status),
                    const SizedBox(width: 12),
                    if (manga.year != null)
                      _buildInfoChip('Year', manga.year.toString()),
                  ],
                ),
                const SizedBox(height: 16),
                if (_availableLanguages.isNotEmpty) ...[
                  Text(
                    'Available Languages',
                    style: MacosTheme.of(context).typography.headline,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _availableLanguages.take(6).map((lang) {
                      final langInfo = SupportedLanguages.getLanguageInfo(lang);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: MacosTheme.brightnessOf(context).resolve(
                            const Color(0xFFF2F2F7),
                            const Color(0xFF2C2C2E),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          langInfo?.name ?? lang.toUpperCase(),
                          style: MacosTheme.of(context).typography.caption1,
                        ),
                      );
                    }).toList(),
                  ),
                  if (_availableLanguages.length > 6) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+${_availableLanguages.length - 6} more languages',
                      style:
                          MacosTheme.of(context).typography.caption1.copyWith(
                                color: MacosTheme.brightnessOf(context).resolve(
                                  const Color(0xFF8E8E93),
                                  const Color(0xFF636366),
                                ),
                              ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: MacosTheme.brightnessOf(context).resolve(
        const Color(0xFFF2F2F7),
        const Color(0xFF2C2C2E),
      ),
      child: Center(
        child: MacosIcon(
          CupertinoIcons.book,
          size: 64,
          color: MacosTheme.brightnessOf(context).resolve(
            const Color(0xFF8E8E93),
            const Color(0xFF636366),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CupertinoColors.systemBlue.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: MacosTheme.of(context).typography.caption1.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemBlue,
                ),
          ),
          Text(
            value,
            style: MacosTheme.of(context).typography.caption1.copyWith(
                  color: CupertinoColors.systemBlue,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSettings() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MacosTheme.brightnessOf(context).resolve(
              const Color(0xFFFAFAFA),
              const Color(0xFF1C1C1E),
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MacosTheme.brightnessOf(context).resolve(
                const Color(0xFFE5E5E7),
                const Color(0xFF38383A),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Language Preferences',
                style: MacosTheme.of(context).typography.headline,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Primary Language',
                          style: MacosTheme.of(context).typography.body,
                        ),
                        const SizedBox(height: 4),
                        MacosPopupButton<String>(
                          value: settings.primaryLanguage,
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              settings.setPrimaryLanguage(newValue);
                              _loadChapters(); // Reload chapters with new language
                            }
                          },
                          items: _buildLanguageMenuItems(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secondary Language',
                          style: MacosTheme.of(context).typography.body,
                        ),
                        const SizedBox(height: 4),
                        MacosPopupButton<String>(
                          value: settings.secondaryLanguage,
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              settings.setSecondaryLanguage(newValue);
                              _loadChapters(); // Reload chapters with new language
                            }
                          },
                          items: _buildLanguageMenuItems(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<MacosPopupMenuItem<String>> _buildLanguageMenuItems() {
    return SupportedLanguages.languages.map((lang) {
      return MacosPopupMenuItem<String>(
        value: lang.code,
        child: Row(
          children: [
            Text(lang.name),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildDescription() {
    final manga = _detailedManga ?? widget.manga;

    if (manga.description == null || manga.description!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: MacosTheme.of(context).typography.headline,
          ),
          const SizedBox(height: 8),
          Text(
            manga.description!,
            style: MacosTheme.of(context).typography.body,
          ),
        ],
      ),
    );
  }

  Widget _buildTags() {
    final manga = _detailedManga ?? widget.manga;

    if (manga.tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tags',
            style: MacosTheme.of(context).typography.headline,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: manga.tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MacosTheme.brightnessOf(context).resolve(
                    const Color(0xFFF2F2F7),
                    const Color(0xFF2C2C2E),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: MacosTheme.brightnessOf(context).resolve(
                      const Color(0xFFD1D1D6),
                      const Color(0xFF38383A),
                    ),
                  ),
                ),
                child: Text(
                  tag,
                  style: MacosTheme.of(context).typography.caption1,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersSection() {
    return Container(
      margin: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Chapters',
                style: MacosTheme.of(context).typography.headline,
              ),
              const Spacer(),
              if (_isLoadingChapters)
                const ProgressCircle(radius: 12)
              else
                Text(
                  _chapterPairs.isNotEmpty
                      ? '${_chapterPairs.length} chapters'
                      : '${_chapters.length} chapters',
                  style: MacosTheme.of(context).typography.caption1,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingChapters)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: ProgressCircle(radius: 20),
              ),
            )
          else if (_chapterPairs.isEmpty && _chapters.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const MacosIcon(
                      CupertinoIcons.book,
                      size: 48,
                      color: Color(0xFF8E8E93),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No chapters available',
                      style: MacosTheme.of(context).typography.body,
                    ),
                    Text(
                      'Try selecting different languages',
                      style:
                          MacosTheme.of(context).typography.caption1.copyWith(
                                color: const Color(0xFF8E8E93),
                              ),
                    ),
                  ],
                ),
              ),
            )
          else if (_chapterPairs.isNotEmpty)
            _buildPairedChaptersList()
          else
            _buildChaptersList(),
        ],
      ),
    );
  }

  Widget _buildPairedChaptersList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _chapterPairs.length > 50 ? 50 : _chapterPairs.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: MacosTheme.brightnessOf(context).resolve(
          const Color(0xFFE5E5E7),
          const Color(0xFF38383A),
        ),
      ),
      itemBuilder: (context, index) {
        final pair = _chapterPairs[index];
        final primaryInfo =
            SupportedLanguages.getLanguageInfo(pair.primary.language);
        final secondaryInfo =
            SupportedLanguages.getLanguageInfo(pair.secondary.language);
        final label =
            pair.primary.chapterNumber ?? pair.secondary.chapterNumber ?? '-';
        final title = pair.primary.title.isNotEmpty
            ? pair.primary.title
            : pair.secondary.title;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DualChapterReader(
                    primary: pair.primary,
                    secondary: pair.secondary,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text('Ch. $label',
                      style: MacosTheme.of(context).typography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          )),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MacosTheme.of(context).typography.body,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Language badges
                  _langBadge(primaryInfo?.flag ?? '🌐',
                      primaryInfo?.name ?? pair.primary.language.toUpperCase()),
                  const SizedBox(width: 6),
                  _langBadge(
                      secondaryInfo?.flag ?? '🌐',
                      secondaryInfo?.name ??
                          pair.secondary.language.toUpperCase()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _langBadge(String flag, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MacosTheme.brightnessOf(context).resolve(
          const Color(0xFFF2F2F7),
          const Color(0xFF2C2C2E),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$flag $name',
          style: MacosTheme.of(context).typography.caption1),
    );
  }

  Widget _buildChaptersList() {
    // Group chapters by language for better organization
    final Map<String, List<Chapter>> chaptersByLanguage = {};
    for (final chapter in _chapters) {
      chaptersByLanguage.putIfAbsent(chapter.language, () => []).add(chapter);
    }

    return Column(
      children: chaptersByLanguage.entries.map((entry) {
        final language = entry.key;
        final chapters = entry.value;
        final langInfo = SupportedLanguages.getLanguageInfo(language);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: MacosTheme.brightnessOf(context).resolve(
              const Color(0xFFFAFAFA),
              const Color(0xFF1C1C1E),
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MacosTheme.brightnessOf(context).resolve(
                const Color(0xFFE5E5E7),
                const Color(0xFF38383A),
              ),
            ),
          ),
          child: Column(
            children: [
              // Language header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacosTheme.brightnessOf(context).resolve(
                    const Color(0xFFF2F2F7),
                    const Color(0xFF2C2C2E),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      langInfo?.flag ?? '🌐',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      langInfo?.name ?? language.toUpperCase(),
                      style: MacosTheme.of(context).typography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${chapters.length} chapters',
                      style: MacosTheme.of(context).typography.caption1,
                    ),
                  ],
                ),
              ),

              // Chapters list (show first 10)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: chapters.length > 10 ? 10 : chapters.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: MacosTheme.brightnessOf(context).resolve(
                    const Color(0xFFE5E5E7),
                    const Color(0xFF38383A),
                  ),
                ),
                itemBuilder: (context, index) {
                  final chapter = chapters[index];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            if (chapter.chapterNumber != null)
                              SizedBox(
                                width: 60,
                                child: Text(
                                  'Ch. ${chapter.chapterNumber}',
                                  style: MacosTheme.of(context)
                                      .typography
                                      .caption1
                                      .copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoColors.systemBlue,
                                      ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                chapter.title.isNotEmpty
                                    ? chapter.title
                                    : 'Chapter ${chapter.chapterNumber ?? 'Unknown'}',
                                style: MacosTheme.of(context).typography.body,
                              ),
                            ),
                            if (chapter.pages > 0)
                              Text(
                                '${chapter.pages} pages',
                                style: MacosTheme.of(context)
                                    .typography
                                    .caption1
                                    .copyWith(
                                      color: const Color(0xFF8E8E93),
                                    ),
                              ),
                            const SizedBox(width: 8),
                            const MacosIcon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: Color(0xFF8E8E93),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Show more button if there are more chapters
              if (chapters.length > 10)
                Container(
                  padding: const EdgeInsets.all(12),
                  child: PushButton(
                    controlSize: ControlSize.small,
                    child: Text('Show ${chapters.length - 10} more chapters'),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ChapterPair {
  final String key;
  final Chapter primary;
  final Chapter secondary;
  _ChapterPair(
      {required this.key, required this.primary, required this.secondary});
}
