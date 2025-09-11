import 'dart:nativewrappers/_internal/vm/lib/developer.dart';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:manga_muli_language_viewer/screens/discover_page.dart';
import 'package:manga_muli_language_viewer/screens/reader_page.dart';
import 'package:provider/provider.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_dio/stash_dio.dart';
import 'package:stash_memory/stash_memory.dart';

/// This method initializes macos_window_utils and styles the window.
Future<void> _configureMacosWindowUtils() async {
  const config = MacosWindowUtilsConfig();
  await config.apply();
}

Future<void> main() async {
  // Creates a store
  final store = await newMemoryCacheStore();
  // Creates a cache
  final cache = await store.cache(
      eventListenerMode: EventListenerMode.synchronous)
    ..on<CacheEntryCreatedEvent>()
        .listen((event) => log('Key "${event.entry.key}" added to the cache'));

  // Configures a a dio client
  final dio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.dev'))
    ..interceptors.addAll([
      cache.interceptor('*'),
      LogInterceptor(
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
      )
    ]);

  await _configureMacosWindowUtils();
  MultiProvider(
    providers: [
      Provider<Dio>(create: (context) => dio),
      Provider<Cache>(create: (context) => cache),
    ],
    child: const App(),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'manga_muli_language_viewer',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const MainView(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainView extends StatefulWidget {
  const MainView({super.key});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  int _pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: const [
        PlatformMenu(
          label: 'MangaMuliLanguageViewer',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
      ],
      child: MacosWindow(
        sidebar: Sidebar(
          minWidth: 200,
          builder: (context, scrollController) => SidebarItems(
            currentIndex: _pageIndex,
            onChanged: (index) {
              setState(() => _pageIndex = index);
            },
            items: const [
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.search),
                label: Text('Discover'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.book),
                label: Text('Reader'),
              ),
            ],
          ),
        ),
        child: IndexedStack(
          index: _pageIndex,
          children: const [
            DiscoverPage(),
            ReaderPage(),
          ],
        ),
      ),
    );
  }
}
