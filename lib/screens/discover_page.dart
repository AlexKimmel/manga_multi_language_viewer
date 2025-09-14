import 'dart:developer';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:manga_muli_language_viewer/models/chapter.dart';
import 'package:manga_muli_language_viewer/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../services/mangadx_service.dart';
import '../widget/discover/manga_card.dart';
import 'package:manga_muli_language_viewer/screens/manga_info_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  late MangaDexService _mangaDexService;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<Manga> _mangas = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _currentSearchTerm;
  int _currentOffset = 0;
  DateTime? _lastLoadMoreTime;
  static const int _pageSize =
      32; // Increased from 20 to 32 for better performance
  // Prevent scheduling multiple post-frame checks per build.
  bool _postFrameScheduled = false;

  @override
  void initState() {
    super.initState();
    _mangaDexService = MangaDexService(context.read<Dio>());
    _loadPopularManga();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;

    final scrollController = _scrollController;
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    final maxScrollExtent = position.maxScrollExtent;
    final currentPixels = position.pixels;

    // More aggressive loading triggers for better UX
    const triggerDistance = 600.0; // Increased from 400 to be more proactive
    const triggerPercentage = 0.8;

    final isNearBottom = currentPixels >= (maxScrollExtent - triggerDistance);
    final isPastThreshold = maxScrollExtent > 0 &&
        (currentPixels / maxScrollExtent) >= triggerPercentage;

    // Add throttling to prevent too frequent API calls
    final now = DateTime.now();
    final timeSinceLastLoad = _lastLoadMoreTime != null
        ? now.difference(_lastLoadMoreTime!)
        : const Duration(seconds: 10);

    if ((isNearBottom || isPastThreshold) &&
        _hasMore &&
        !_isLoadingMore &&
        timeSinceLastLoad.inSeconds >= 1) {
      // Throttle to max 1 call per second
      _lastLoadMoreTime = now;
      _loadMoreManga();
    }
  }

  // Schedules a post-frame check to prefetch if the content doesn't fill the viewport.
  void _scheduleAutoPrefetchCheck() {
    if (_postFrameScheduled || !mounted) return;
    _postFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      _autoPrefetchIfNotScrollable();
    });
  }

  // If the grid isn't scrollable (e.g., after window resize) and more data exists,
  // fetch the next page to avoid a soft lock where no scroll can happen.
  void _autoPrefetchIfNotScrollable() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final notScrollable = position.maxScrollExtent <= 0;
    if (notScrollable && _hasMore && !_isLoading && !_isLoadingMore) {
      _loadMoreManga();
    }
  }

  Future<void> _loadPopularManga() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _mangas.clear();
      _currentOffset = 0;
      _hasMore = true;
      _currentSearchTerm = null;
    });

    try {
      final response = await _mangaDexService.getPopularManga(
        limit: _pageSize,
        offset: 0,
        loadCoversImmediately: false, // Load covers asynchronously
        availableTranslatedLanguages:
            context.read<SettingsProvider>().preferredLanguages,
      );

      // If a search started while the popular request was in-flight, don't overwrite search results.
      if (!mounted || _currentSearchTerm != null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      setState(() {
        _mangas = _filterBySelectedLanguages(response.data);
        _currentOffset = _pageSize;
        _hasMore = response.data.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        _showErrorDialog('Failed to load manga: ${e.toString()}');
      }
    }
  }

  Future<void> _searchManga(String searchTerm) async {
    // Don't block search if another load is in progress; latest request wins.
    setState(() {
      _isLoading = true;
      _mangas.clear();
      _currentOffset = 0;
      _hasMore = true;
      _currentSearchTerm = searchTerm.trim().isEmpty ? null : searchTerm.trim();
    });

    try {
      final response = await _mangaDexService.searchManga(
        query: searchTerm.trim(),
        limit: _pageSize,
        offset: 0,
        loadCoversImmediately: false, // Load covers asynchronously
        contentRatings: context.read<SettingsProvider>().searchSettings,
        availableTranslatedLanguages:
            context.read<SettingsProvider>().preferredLanguages,
      );

      setState(() {
        _mangas = _filterBySelectedLanguages(response.data);
        _currentOffset = _pageSize;
        _hasMore = response.data.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        _showErrorDialog('Failed to search manga: ${e.toString()}');
      }
    }
  }

  Future<void> _loadMoreManga() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final query =
          _currentSearchTerm?.isEmpty ?? true ? '' : _currentSearchTerm!;
      final response = await _mangaDexService.searchManga(
        query: query,
        limit: _pageSize,
        offset: _currentOffset,
        loadCoversImmediately: false, // Load covers asynchronously
        contentRatings: context.read<SettingsProvider>().searchSettings,
        availableTranslatedLanguages:
            context.read<SettingsProvider>().preferredLanguages,
      );

      if (mounted) {
        setState(() {
          final filtered = _filterBySelectedLanguages(response.data);
          _mangas.addAll(filtered);
          _currentOffset +=
              response.data.length; // Use actual length instead of _pageSize
          _hasMore = response.data.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        // Don't show error dialog for load more failures to avoid interrupting UX
        log('Failed to load more manga: $e');
      }
    }
  }

  List<Manga> _filterBySelectedLanguages(List<Manga> list) {
    final settings = context.read<SettingsProvider>();
    final primary = settings.primaryLanguage;
    final secondary = settings.secondaryLanguage;

    // If both are same, require that language only
    if (primary == secondary) {
      return list
          .where((m) => m.availableTranslatedLanguages.contains(primary))
          .toList();
    }

    // Require both languages to be available
    return list
        .where((m) =>
            m.availableTranslatedLanguages.contains(primary) &&
            m.availableTranslatedLanguages.contains(secondary))
        .toList();
  }

  void _showErrorDialog(String message) {
    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        title: const Text('Error'),
        message: Text(message),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // After each build (including window resizes), ensure enough items are loaded
        // to make the view scrollable, otherwise prefetch more.
        _scheduleAutoPrefetchCheck();
        return MacosScaffold(
          toolBar: ToolBar(
            enableBlur: true,
            allowWallpaperTintingOverrides: true,
            leading: MacosTooltip(
              message: 'Toggle Sidebar',
              useMousePosition: false,
              child: MacosIconButton(
                icon: MacosIcon(
                  CupertinoIcons.sidebar_left,
                  color: MacosTheme.brightnessOf(context).resolve(
                    const Color.fromRGBO(0, 0, 0, 0.5),
                    const Color.fromRGBO(255, 255, 255, 0.5),
                  ),
                  size: 20.0,
                ),
                boxConstraints: const BoxConstraints(
                  minHeight: 20,
                  minWidth: 20,
                  maxWidth: 48,
                  maxHeight: 38,
                ),
                onPressed: () => MacosWindowScope.of(context).toggleSidebar(),
              ),
            ),
            actions: [
              ToolBarPullDownButton(
                label: 'Search Settings',
                icon: CupertinoIcons.settings,
                items: [
                  MacosPulldownMenuItem(
                    title: Row(
                      children: [
                        MacosCheckbox(
                            value: context
                                .read<SettingsProvider>()
                                .searchSettings
                                .contains('safe'),
                            onChanged: (value) {}),
                        const SizedBox(
                          width: 4,
                        ),
                        const Text('safe'),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        context
                            .read<SettingsProvider>()
                            .updateSearchsettings('safe');
                      });
                    },
                  ),
                  MacosPulldownMenuItem(
                    title: Row(
                      children: [
                        MacosCheckbox(
                            value: context
                                .read<SettingsProvider>()
                                .searchSettings
                                .contains('suggestive'),
                            onChanged: (value) {}),
                        const SizedBox(
                          width: 4,
                        ),
                        const Text('suggestive'),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        context
                            .read<SettingsProvider>()
                            .updateSearchsettings('suggestive');
                      });
                    },
                  ),
                  MacosPulldownMenuItem(
                    title: Row(
                      children: [
                        MacosCheckbox(
                            value: context
                                .read<SettingsProvider>()
                                .searchSettings
                                .contains('erotica'),
                            onChanged: (value) {}),
                        const SizedBox(
                          width: 4,
                        ),
                        const Text('erotica'),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        context
                            .read<SettingsProvider>()
                            .updateSearchsettings('erotica');
                      });
                    },
                  ),
                ],
              )
            ],
            title: const Text('Discover'),
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                final settings = context.watch<SettingsProvider>();
                return Column(
                  children: [
                    Row(
                      children: [
                        // Search Bar
                        Expanded(
                          flex: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: MacosTextField(
                              prefix: const Icon(CupertinoIcons.search),
                              controller: _searchController,
                              onChanged: (value) {
                                // Debounce to avoid firing a request on every keystroke
                                _searchDebounce?.cancel();
                                _searchDebounce = Timer(
                                    const Duration(milliseconds: 400), () {
                                  final term = value.trim();
                                  if (term.isEmpty) {
                                    _loadPopularManga();
                                  } else {
                                    _searchManga(term);
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        // primary langauge

                        // secondary language
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: MacosPopupButton<String>(
                                value: settings.primaryLanguage,
                                items: _buildLanguageMenuItems(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    settings.setPrimaryLanguage(newValue);
                                    final term = _searchController.text;
                                    if (term.isNotEmpty) {
                                      _searchManga(term);
                                    } else {
                                      _loadPopularManga();
                                    }
                                  }
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: MacosPopupButton<String>(
                                value: settings.secondaryLanguage,
                                items: _buildLanguageMenuItems(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    settings.setSecondaryLanguage(newValue);
                                    final term = _searchController.text;
                                    if (term.isNotEmpty) {
                                      _searchManga(term);
                                    } else {
                                      _loadPopularManga();
                                    }
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Content
                    Expanded(
                      child: _buildContent(),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  List<MacosPopupMenuItem<String>> _buildLanguageMenuItems() {
    return SupportedLanguages.languages.map((lang) {
      return MacosPopupMenuItem<String>(
        value: lang.code,
        child: Text(lang.name),
      );
    }).toList();
  }

  Widget _buildContent() {
    if (_isLoading && _mangas.isEmpty) {
      return const Center(
        child: ProgressCircle(radius: 20),
      );
    }

    if (_mangas.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MacosIcon(
              CupertinoIcons.search,
              size: 64,
              color: MacosTheme.brightnessOf(context).resolve(
                const Color(0xFF8E8E93),
                const Color(0xFF636366),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _currentSearchTerm != null
                  ? 'No manga found for "$_currentSearchTerm"'
                  : 'No manga available',
              style: MacosTheme.of(context).typography.headline,
            ),
            const SizedBox(height: 8),
            Text(
              _currentSearchTerm != null
                  ? 'Try searching with different keywords'
                  : 'Check your internet connection',
              style: MacosTheme.of(context).typography.body,
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170, // Slightly reduced to fit more items
              childAspectRatio: 0.65, // Adjusted for better proportions
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index < _mangas.length) {
                  return MangaCard(
                    manga: _mangas[index],
                    mangaDexService: _mangaDexService,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              MangaInfoPage(manga: _mangas[index]),
                        ),
                      );
                    },
                  );
                }
                return null;
              },
              childCount: _mangas.length,
            ),
          ),
        ),

        // Loading indicator at bottom
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: ProgressCircle(radius: 16),
              ),
            ),
          ),

        // Show "Load More" button as fallback if near end but not auto-loading
        if (_hasMore && !_isLoadingMore && !_isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: PushButton(
                  controlSize: ControlSize.large,
                  onPressed: _loadMoreManga,
                  child: const Text('Load More'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
