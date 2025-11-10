import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/focus/focus_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/find_ref/find_ref_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';

class KeyboardShortcuts extends StatefulWidget {
  final Widget child;

  const KeyboardShortcuts({super.key, required this.child});

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  final Map<String, LogicalKeySet> shortcuts = {
    'ctrl+a': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyA,
    ),
    'ctrl+b': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyB,
    ),
    'ctrl+c': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyC,
    ),
    'ctrl+d': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyD,
    ),
    'ctrl+e': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyE,
    ),
    'ctrl+f': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyF,
    ),
    'ctrl+g': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyG,
    ),
    'ctrl+h': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyH,
    ),
    'ctrl+i': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyI,
    ),
    'ctrl+j': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyJ,
    ),
    'ctrl+k': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyK,
    ),
    'ctrl+l': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyL,
    ),
    'ctrl+m': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyM,
    ),
    'ctrl+n': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyN,
    ),
    'ctrl+o': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyO,
    ),
    'ctrl+p': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyP,
    ),
    'ctrl+q': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyQ,
    ),
    'ctrl+r': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyR,
    ),
    'ctrl+s': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyS,
    ),
    'ctrl+t': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyT,
    ),
    'ctrl+u': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyU,
    ),
    'ctrl+v': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyV,
    ),
    'ctrl+w': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyW,
    ),
    'ctrl+x': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyX,
    ),
    'ctrl+y': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyY,
    ),
    'ctrl+z': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyZ,
    ),
    'ctrl+0': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit0,
    ),
    'ctrl+1': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit1,
    ),
    'ctrl+2': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit2,
    ),
    'ctrl+3': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit3,
    ),
    'ctrl+4': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit4,
    ),
    'ctrl+5': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit5,
    ),
    'ctrl+6': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit6,
    ),
    'ctrl+7': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit7,
    ),
    'ctrl+8': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit8,
    ),
    'ctrl+9': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.digit9,
    ),
    'ctrl+tab': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.tab,
    ),
    'ctrl+shift+tab': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.shift,
    ),
    'ctrl+comma': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.comma,
    ),
    'ctrl+shift+b': LogicalKeySet(
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyB,
    ),
  };

  LogicalKeySet? _parseShortcut(String shortcut) {
    if (shortcuts.containsKey(shortcut)) {
      return shortcuts[shortcut];
    }

    // ניתוח קיצור מותאם אישית
    final parts = shortcut.toLowerCase().split('+');
    final keys = <LogicalKeyboardKey>[];

    for (final part in parts) {
      final trimmed = part.trim();

      // Modifiers
      if (trimmed == 'ctrl' || trimmed == 'control') {
        keys.add(LogicalKeyboardKey.control);
      } else if (trimmed == 'shift') {
        keys.add(LogicalKeyboardKey.shift);
      } else if (trimmed == 'alt') {
        keys.add(LogicalKeyboardKey.alt);
      } else if (trimmed == 'meta' || trimmed == 'win') {
        keys.add(LogicalKeyboardKey.meta);
      }
      // Letters
      else if (trimmed.length == 1 &&
          trimmed.codeUnitAt(0) >= 97 &&
          trimmed.codeUnitAt(0) <= 122) {
        final key = LogicalKeyboardKey.findKeyByKeyId(
            LogicalKeyboardKey.keyA.keyId + (trimmed.codeUnitAt(0) - 97));
        if (key != null) keys.add(key);
      }
      // Numbers
      else if (trimmed.length == 1 &&
          trimmed.codeUnitAt(0) >= 48 &&
          trimmed.codeUnitAt(0) <= 57) {
        final digit = int.parse(trimmed);
        // שימוש במקשי מספרים המוגדרים מראש
        switch (digit) {
          case 0:
            keys.add(LogicalKeyboardKey.digit0);
            break;
          case 1:
            keys.add(LogicalKeyboardKey.digit1);
            break;
          case 2:
            keys.add(LogicalKeyboardKey.digit2);
            break;
          case 3:
            keys.add(LogicalKeyboardKey.digit3);
            break;
          case 4:
            keys.add(LogicalKeyboardKey.digit4);
            break;
          case 5:
            keys.add(LogicalKeyboardKey.digit5);
            break;
          case 6:
            keys.add(LogicalKeyboardKey.digit6);
            break;
          case 7:
            keys.add(LogicalKeyboardKey.digit7);
            break;
          case 8:
            keys.add(LogicalKeyboardKey.digit8);
            break;
          case 9:
            keys.add(LogicalKeyboardKey.digit9);
            break;
        }
      }
      // Special keys
      else if (trimmed == 'comma') {
        keys.add(LogicalKeyboardKey.comma);
      } else if (trimmed == 'period') {
        keys.add(LogicalKeyboardKey.period);
      } else if (trimmed == 'slash') {
        keys.add(LogicalKeyboardKey.slash);
      } else if (trimmed == 'backslash') {
        keys.add(LogicalKeyboardKey.backslash);
      } else if (trimmed == 'semicolon') {
        keys.add(LogicalKeyboardKey.semicolon);
      } else if (trimmed == 'quote') {
        keys.add(LogicalKeyboardKey.quote);
      } else if (trimmed == 'bracketleft') {
        keys.add(LogicalKeyboardKey.bracketLeft);
      } else if (trimmed == 'bracketright') {
        keys.add(LogicalKeyboardKey.bracketRight);
      } else if (trimmed == 'minus') {
        keys.add(LogicalKeyboardKey.minus);
      } else if (trimmed == 'equal') {
        keys.add(LogicalKeyboardKey.equal);
      } else if (trimmed == 'space') {
        keys.add(LogicalKeyboardKey.space);
      } else if (trimmed == 'tab') {
        keys.add(LogicalKeyboardKey.tab);
      } else if (trimmed == 'enter') {
        keys.add(LogicalKeyboardKey.enter);
      } else if (trimmed == 'backspace') {
        keys.add(LogicalKeyboardKey.backspace);
      } else if (trimmed == 'delete') {
        keys.add(LogicalKeyboardKey.delete);
      } else if (trimmed == 'escape') {
        keys.add(LogicalKeyboardKey.escape);
      } else if (trimmed == 'arrowup') {
        keys.add(LogicalKeyboardKey.arrowUp);
      } else if (trimmed == 'arrowdown') {
        keys.add(LogicalKeyboardKey.arrowDown);
      } else if (trimmed == 'arrowleft') {
        keys.add(LogicalKeyboardKey.arrowLeft);
      } else if (trimmed == 'arrowright') {
        keys.add(LogicalKeyboardKey.arrowRight);
      } else if (trimmed == 'home') {
        keys.add(LogicalKeyboardKey.home);
      } else if (trimmed == 'end') {
        keys.add(LogicalKeyboardKey.end);
      } else if (trimmed == 'pageup') {
        keys.add(LogicalKeyboardKey.pageUp);
      } else if (trimmed == 'pagedown') {
        keys.add(LogicalKeyboardKey.pageDown);
      }
      // F keys
      else if (trimmed.startsWith('f') && trimmed.length <= 3) {
        final num = int.tryParse(trimmed.substring(1));
        if (num != null && num >= 1 && num <= 12) {
          // שימוש במקשי F המוגדרים מראש
          switch (num) {
            case 1:
              keys.add(LogicalKeyboardKey.f1);
              break;
            case 2:
              keys.add(LogicalKeyboardKey.f2);
              break;
            case 3:
              keys.add(LogicalKeyboardKey.f3);
              break;
            case 4:
              keys.add(LogicalKeyboardKey.f4);
              break;
            case 5:
              keys.add(LogicalKeyboardKey.f5);
              break;
            case 6:
              keys.add(LogicalKeyboardKey.f6);
              break;
            case 7:
              keys.add(LogicalKeyboardKey.f7);
              break;
            case 8:
              keys.add(LogicalKeyboardKey.f8);
              break;
            case 9:
              keys.add(LogicalKeyboardKey.f9);
              break;
            case 10:
              keys.add(LogicalKeyboardKey.f10);
              break;
            case 11:
              keys.add(LogicalKeyboardKey.f11);
              break;
            case 12:
              keys.add(LogicalKeyboardKey.f12);
              break;
          }
        }
      }
    }

    return keys.isEmpty ? null : LogicalKeySet.fromSet(keys.toSet());
  }

  Map<ShortcutActivator, VoidCallback> _buildShortcutBindings(
      BuildContext context, Map<String, String> shortcutSettings) {
    // קריאת ערכי הקיצורים מההגדרות בכל פעם שהפונקציה נקראת
    // ניווט כללי
    final libraryShortcut =
        shortcutSettings['key-shortcut-open-library-browser'] ?? 'ctrl+l';
    final findRefShortcut =
        shortcutSettings['key-shortcut-open-find-ref'] ?? 'ctrl+o';
    final closeTabShortcut =
        shortcutSettings['key-shortcut-close-tab'] ?? 'ctrl+w';
    final closeAllTabsShortcut =
        shortcutSettings['key-shortcut-close-all-tabs'] ?? 'ctrl+x';
    final readingScreenShortcut =
        shortcutSettings['key-shortcut-open-reading-screen'] ?? 'ctrl+r';
    final newSearchShortcut =
        shortcutSettings['key-shortcut-open-new-search'] ?? 'ctrl+q';
    final settingsShortcut =
        shortcutSettings['key-shortcut-open-settings'] ?? 'ctrl+comma';
    final moreShortcut = shortcutSettings['key-shortcut-open-more'] ?? 'ctrl+m';
    final bookmarksShortcut =
        shortcutSettings['key-shortcut-open-bookmarks'] ?? 'ctrl+shift+b';
    final historyShortcut =
        shortcutSettings['key-shortcut-open-history'] ?? 'ctrl+h';
    final workspaceShortcut =
        shortcutSettings['key-shortcut-switch-workspace'] ?? 'ctrl+k';

    final bindings = <ShortcutActivator, VoidCallback>{};

    // Helper function to add binding
    void addBinding(String shortcut, VoidCallback callback) {
      final keySet = _parseShortcut(shortcut);
      if (keySet != null) {
        bindings[keySet] = callback;
      }
    }

    addBinding(libraryShortcut, () {
      context.read<NavigationBloc>().add(
            const NavigateToScreen(Screen.library),
          );
      //set focus
      context.read<FocusRepository>().requestLibrarySearchFocus(
            selectAll: true,
          );
    });

    addBinding(findRefShortcut, () {
      showDialog(context: context, builder: (context) => FindRefDialog());
    });

    addBinding(closeTabShortcut, () {
      final tabsBloc = context.read<TabsBloc>();
      final historyBloc = context.read<HistoryBloc>();
      if (tabsBloc.state.tabs.isNotEmpty) {
        final currentTab = tabsBloc.state.tabs[tabsBloc.state.currentTabIndex];
        historyBloc.add(AddHistory(currentTab));
      }
      tabsBloc.add(const CloseCurrentTab());
    });

    addBinding(closeAllTabsShortcut, () {
      final tabsBloc = context.read<TabsBloc>();
      final historyBloc = context.read<HistoryBloc>();
      for (final tab in tabsBloc.state.tabs) {
        if (tab is! SearchingTab) {
          historyBloc.add(AddHistory(tab));
        }
      }
      tabsBloc.add(CloseAllTabs());
    });

    addBinding(readingScreenShortcut, () {
      context.read<NavigationBloc>().add(
            const NavigateToScreen(Screen.reading),
          );
    });

    addBinding(newSearchShortcut, () {
      final useFastSearch = context.read<SettingsBloc>().state.useFastSearch;
      if (!useFastSearch) {
        _openLegacySearchTab(context);
        return;
      }

      showDialog(
        context: context,
        builder: (context) => const SearchDialog(existingTab: null),
      );
    });

    addBinding('ctrl+shift+tab', () {
      context.read<TabsBloc>().add(NavigateToPreviousTab());
    });

    addBinding('ctrl+tab', () {
      context.read<TabsBloc>().add(NavigateToNextTab());
    });

    addBinding(settingsShortcut, () {
      context.read<NavigationBloc>().add(
            const NavigateToScreen(Screen.settings),
          );
    });

    addBinding(moreShortcut, () {
      context.read<NavigationBloc>().add(
            const NavigateToScreen(Screen.more),
          );
    });

    addBinding(bookmarksShortcut, () {
      // Open bookmarks dialog using the same dialog as the button
      showDialog(
        context: context,
        builder: (context) => const BookmarksDialog(),
      );
    });

    addBinding(historyShortcut, () {
      // Open history dialog using the same dialog as the button
      showDialog(
        context: context,
        builder: (context) => const HistoryDialog(),
      );
    });

    addBinding(workspaceShortcut, () {
      // Open workspace switcher dialog
      showDialog(
        context: context,
        builder: (context) => const WorkspaceSwitcherDialog(),
      );
    });

    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) => previous.shortcuts != current.shortcuts,
      builder: (context, state) {
        return CallbackShortcuts(
          bindings: _buildShortcutBindings(context, state.shortcuts),
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            descendantsAreFocusable: true,
            child: widget.child,
          ),
        );
      },
    );
  }

  void _openLegacySearchTab(BuildContext context) {
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();

    final tabsState = tabsBloc.state;
    final hasSearchTab = tabsState.tabs.any(
      (tab) => tab.runtimeType == SearchingTab,
    );

    if (!hasSearchTab) {
      tabsBloc.add(AddTab(SearchingTab("חיפוש", "")));
    } else {
      final currentScreen = navigationBloc.state.currentScreen;
      final isAlreadySearchTab = currentScreen == Screen.search &&
          tabsState.tabs[tabsState.currentTabIndex].runtimeType == SearchingTab;
      if (!isAlreadySearchTab) {
        final searchTabIndex = tabsState.tabs.indexWhere(
          (tab) => tab.runtimeType == SearchingTab,
        );
        if (searchTabIndex != -1) {
          tabsBloc.add(SetCurrentTab(searchTabIndex));
        }
      }
    }

    navigationBloc.add(const NavigateToScreen(Screen.search));
  }
}
