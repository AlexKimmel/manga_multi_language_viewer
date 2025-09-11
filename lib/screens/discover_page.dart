import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return MacosScaffold(
          toolBar: ToolBar(
            leading: MacosTooltip(
              message: 'Toggle Sidebar',
              useMousePosition: false,
              child: Column(
                children: [
                  MacosIconButton(
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
                    onPressed: () =>
                        MacosWindowScope.of(context).toggleSidebar(),
                  ),
                ],
              ),
            ),
            title: const Text('Discover'),
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                return const Center(
                  child: Text('Discover'),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
