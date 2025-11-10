import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as path;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/settings/reading_settings_dialog.dart';
import 'package:otzaria/settings/library_settings_dialog.dart';
import 'package:otzaria/settings/calendar_settings_dialog.dart';
import 'package:otzaria/settings/gematria_settings_dialog.dart';
import 'package:otzaria/settings/backup_service.dart';
import 'package:otzaria/widgets/shortcut_dropdown_tile.dart';
import 'package:otzaria/services/database_import_service.dart';
import 'package:otzaria/services/auto_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:async';

class MySettingsScreen extends StatefulWidget {
  const MySettingsScreen({
    super.key,
  });

  @override
  State<MySettingsScreen> createState() => _MySettingsScreenState();
}

class _MySettingsScreenState extends State<MySettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _showImportProgressDialog(
    BuildContext context,
    String folderPath,
    String dbPath,
    String libraryPath, {
    bool createBackup = true,
  }) {
    String statusText = 'מתחיל...';
    int? currentBook;
    int? totalBooks;
    bool isStarted = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Start import only once
            if (!isStarted) {
              isStarted = true;
              DatabaseImportService.importBooksFromFolder(
                folderPath,
                dbPath,
                (status, {current, total}) {
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      statusText = status;
                      currentBook = current;
                      totalBooks = total;
                    });

                    // Refresh library when complete
                    if (status == 'הושלם בהצלחה!') {
                      // Reload library immediately with full refresh
                      if (context.mounted) {
                        context.read<LibraryBloc>().add(RefreshLibrary());
                      }
                    }
                  }
                },
                createBackup: createBackup,
              ).catchError((error) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    statusText = 'שגיאה: $error';
                  });
                  Future.delayed(
                    const Duration(seconds: 3),
                    () {
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
                  );
                }
              });
            }

            final progress = (currentBook != null && totalBooks != null && totalBooks! > 0)
                ? currentBook! / totalBooks!
                : 0.0;
            
            return AlertDialog(
              title: const Text('מייבא ספרים'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (currentBook != null && totalBooks != null) ...[
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$currentBook / $totalBooks',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ] else
                      const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              actions: [
                if (statusText.contains('הושלם בהצלחה'))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      // Show success message after dialog closes
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('הייבוא הושלם והספרייה נטענה מחדש'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: const Text('סגור'),
                  )
                else if (!statusText.contains('שגיאה'))
                  TextButton(
                    onPressed: () {
                      DatabaseImportService.cancelImport();
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('הפעולה בוטלה'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                    child: const Text('ביטול'),
                  )
                else
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('סגור'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 160,
      height: 140,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColumns(int maxColumns, List<Widget> children) {
    const double rowSpacing = 16.0;
    const double columnSpacing = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int columns = (width / 300).floor();
        columns = math.min(math.max(columns, 1), maxColumns);

        if (columns <= 1) {
          return Column(children: children);
        }

        List<Widget> rows = [];
        for (int i = 0; i < children.length; i += columns) {
          List<Widget> rowChildren = [];

          for (int j = 0; j < columns; j++) {
            if (i + j < children.length) {
              rowChildren.add(Expanded(child: children[i + j]));

              if (j < columns - 1 && i + j + 1 < children.length) {
                rowChildren.add(const VerticalDivider(
                  width: columnSpacing,
                  thickness: 1,
                ));
              }
            }
          }

          // עוטפים את ה-Row ב-IntrinsicHeight כדי להבטיח גובה אחיד לקו המפריד
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch, // גורם לילדים להימתח
                children: rowChildren,
              ),
            ),
          );
        }

        return Wrap(
          runSpacing: rowSpacing,
          children: rows,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const Map<String, String> shortcuctsList = {
      'ctrl+a': 'CTRL + A',
      'ctrl+b': "CTRL + B",
      'ctrl+c': "CTRL + C",
      'ctrl+d': "CTRL + D",
      'ctrl+e': "CTRL + E",
      'ctrl+f': "CTRL + F",
      'ctrl+g': "CTRL + G",
      'ctrl+h': "CTRL + H",
      'ctrl+i': "CTRL + I",
      'ctrl+j': "CTRL + J",
      'ctrl+k': "CTRL + K",
      'ctrl+l': "CTRL + L",
      'ctrl+m': "CTRL + M",
      'ctrl+n': "CTRL + N",
      'ctrl+o': "CTRL + O",
      'ctrl+p': "CTRL + P",
      'ctrl+q': "CTRL + Q",
      'ctrl+r': "CTRL + R",
      'ctrl+s': "CTRL + S",
      'ctrl+t': "CTRL + T",
      'ctrl+u': "CTRL + U",
      'ctrl+v': "CTRL + V",
      'ctrl+w': "CTRL + W",
      'ctrl+x': "CTRL + X",
      'ctrl+y': "CTRL + Y",
      'ctrl+z': "CTRL + Z",
      'ctrl+0': "CTRL + 0",
      'ctrl+1': "CTRL + 1",
      'ctrl+2': "CTRL + 2",
      'ctrl+3': "CTRL + 3",
      'ctrl+4': "CTRL + 4",
      'ctrl+5': "CTRL + 5",
      'ctrl+6': "CTRL + 6",
      'ctrl+7': "CTRL + 7",
      'ctrl+8': "CTRL + 8",
      'ctrl+9': "CTRL + 9",
      'ctrl+comma': "CTRL + ,",
      'ctrl+shift+b': "CTRL + SHIFT + B",
    };

    return Scaffold(
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          return Theme(
            data: Theme.of(context).copyWith(
              appBarTheme: AppBarTheme(
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                centerTitle: true,
                titleTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            child: Center(
              child: SettingsScreen(
                title: 'הגדרות',
                children: [
                SettingsGroup(
                  titleAlignment: Alignment.centerRight,
                  title: 'הגדרות עיצוב',
                  titleTextStyle: const TextStyle(fontSize: 25),
                  children: <Widget>[
                    _buildColumns(3, [
                      if (!(Platform.isAndroid || Platform.isIOS))
                        BlocBuilder<SettingsBloc, SettingsState>(
                          builder: (context, settingsState) {
                            return SimpleSettingsTile(
                              title: 'מסך מלא',
                              subtitle: 'החלף מצב מסך מלא',
                              leading: Icon(settingsState.isFullscreen
                                  ? FluentIcons.full_screen_minimize_24_regular
                                  : FluentIcons
                                      .full_screen_maximize_24_regular),
                              onTap: () async {
                                final newFullscreenState =
                                    !settingsState.isFullscreen;
                                context.read<SettingsBloc>().add(
                                    UpdateIsFullscreen(newFullscreenState));
                                await windowManager
                                    .setFullScreen(newFullscreenState);
                              },
                            );
                          },
                        ),
                      SwitchSettingsTile(
                        settingKey: 'key-dark-mode',
                        title: 'מצב כהה',
                        enabledLabel: 'מופעל',
                        disabledLabel: 'לא מופעל',
                        leading:
                            const Icon(FluentIcons.weather_moon_24_regular),
                        onChange: (value) {
                          context
                              .read<SettingsBloc>()
                              .add(UpdateDarkMode(value));
                        },
                        activeColor: Theme.of(context).cardColor,
                      ),
                      ColorPickerSettingsTile(
                        title: 'צבע בסיס',
                        leading: const Icon(FluentIcons.color_24_regular),
                        settingKey: 'key-swatch-color',
                        onChange: (color) {
                          context
                              .read<SettingsBloc>()
                              .add(UpdateSeedColor(color));
                        },
                      ),
                    ]),
                  ],
                ),
                const SizedBox(height: 24),
                Platform.isAndroid
                    ? const SizedBox.shrink()
                    : SettingsGroup(
                        titleAlignment: Alignment.centerRight,
                        title: "קיצורי מקשים",
                        titleTextStyle: const TextStyle(fontSize: 25),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0, right: 8.0),
                            child: Text(
                              'ניווט כללי',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          _buildColumns(3, [
                            ShortcutDropDownTile(
                              selected: 'ctrl+l',
                              settingKey: 'key-shortcut-open-library-browser',
                              title: 'ספרייה',
                              allShortcuts: shortcuctsList,
                              leading:
                                  const Icon(FluentIcons.library_24_regular),
                            ),
                            ShortcutDropDownTile(
                              selected: 'ctrl+o',
                              settingKey: 'key-shortcut-open-find-ref',
                              title: 'איתור',
                              allShortcuts: shortcuctsList,
                              leading:
                                  const Icon(FluentIcons.book_open_24_regular),
                            ),
                            ShortcutDropDownTile(
                              selected: 'ctrl+r',
                              settingKey: 'key-shortcut-open-reading-screen',
                              title: 'עיון',
                              leading: const Icon(FluentIcons.book_24_regular),
                              allShortcuts: shortcuctsList,
                            ),
                            ShortcutDropDownTile(
                              selected: 'ctrl+q',
                              settingKey: 'key-shortcut-open-new-search',
                              title: 'חלון חיפוש חדש',
                              leading:
                                  const Icon(FluentIcons.search_24_regular),
                              allShortcuts: shortcuctsList,
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-open-settings',
                              title: 'הגדרות',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+comma',
                              leading:
                                  const Icon(FluentIcons.settings_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-open-more',
                              title: 'כלים',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+m',
                              leading: const Icon(FluentIcons.apps_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-open-bookmarks',
                              title: 'סימניות',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+shift+b',
                              leading:
                                  const Icon(FluentIcons.bookmark_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-open-history',
                              title: 'היסטוריה',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+h',
                              leading:
                                  const Icon(FluentIcons.history_24_regular),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0, right: 8.0),
                            child: Text(
                              'תצוגת ספר',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          _buildColumns(3, [
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-search-in-book',
                              title: 'חיפוש בספר',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+f',
                              leading:
                                  const Icon(FluentIcons.search_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-edit-section',
                              title: 'עריכת קטע',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+e',
                              leading: const Icon(
                                  FluentIcons.document_edit_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-print',
                              title: 'הדפסה',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+p',
                              leading: const Icon(FluentIcons.print_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-add-bookmark',
                              title: 'הוספת סימניה',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+b',
                              leading:
                                  const Icon(FluentIcons.bookmark_24_regular),
                            ),
                            ShortcutDropDownTile(
                              settingKey: 'key-shortcut-add-note',
                              title: 'הוספת הערה',
                              allShortcuts: shortcuctsList,
                              selected: 'ctrl+n',
                              leading: const Icon(FluentIcons.note_24_regular),
                            ),
                            ShortcutDropDownTile(
                              selected: 'ctrl+w',
                              settingKey: 'key-shortcut-close-tab',
                              title: 'סגור ספר נוכחי',
                              allShortcuts: shortcuctsList,
                              leading: const Icon(
                                  FluentIcons.dismiss_circle_24_regular),
                            ),
                            ShortcutDropDownTile(
                              selected: 'ctrl+x',
                              settingKey: 'key-shortcut-close-all-tabs',
                              title: 'סגור כל הספרים',
                              allShortcuts: shortcuctsList,
                              leading:
                                  const Icon(FluentIcons.dismiss_24_regular),
                            ),
                          ]),
                        ],
                      ),
                const SizedBox(height: 24),
                SettingsGroup(
                  title: 'הגדרות ממשק',
                  titleAlignment: Alignment.centerRight,
                  titleTextStyle: const TextStyle(fontSize: 25),
                  children: [
                    SwitchSettingsTile(
                      settingKey: 'key-replace-holy-names',
                      title: 'הסתרת שמות הקודש',
                      enabledLabel: 'השמות הקדושים יוחלפו מפאת קדושתם',
                      disabledLabel: 'השמות הקדושים יוצגו ככתיבתם',
                      leading: const Icon(FluentIcons.eye_off_24_regular),
                      defaultValue: state.replaceHolyNames,
                      onChange: (value) {
                        context
                            .read<SettingsBloc>()
                            .add(UpdateReplaceHolyNames(value));
                      },
                      activeColor: Theme.of(context).cardColor,
                    ),
                    // קוביות הגדרות
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Wrap(
                        spacing: 12.0,
                        runSpacing: 12.0,
                        alignment: WrapAlignment.end,
                        children: [
                          _buildSettingsCard(
                            context: context,
                            title: 'הגדרות מסך ספרייה',
                            icon: FluentIcons.library_24_regular,
                            onTap: () => showLibrarySettingsDialog(context),
                          ),
                          _buildSettingsCard(
                            context: context,
                            title: 'הגדרות תצוגת הספרים',
                            icon: FluentIcons.book_24_regular,
                            onTap: () => showReadingSettingsDialog(context),
                          ),
                          _buildSettingsCard(
                            context: context,
                            title: 'הגדרות לוח שנה',
                            icon: Icons.calendar_month_outlined,
                            onTap: () => showCalendarSettingsDialog(context),
                          ),
                          // הגדרות זכור ושמור - מוסתר כרגע
                          // ignore: dead_code
                          if (false)
                            // ignore: dead_code
                            _buildSettingsCard(
                              context: context,
                              title: 'הגדרות זכור ושמור',
                              icon: FluentIcons.book_24_regular,
                              onTap: () {
                                // יוסף בעתיד
                              },
                            ),
                          _buildSettingsCard(
                            context: context,
                            title: 'הגדרות גימטריות',
                            icon: FluentIcons.calculator_24_regular,
                            onTap: () => showGematriaSettingsDialog(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsGroup(
                  title: 'גיבוי',
                  titleAlignment: Alignment.centerRight,
                  titleTextStyle: const TextStyle(fontSize: 25),
                  children: [
                    SettingsGroup(
                      title: 'גבה את:',
                      titleAlignment: Alignment.centerRight,
                      children: [
                        _buildColumns(3, [
                          SwitchSettingsTile(
                            settingKey: 'key-backup-settings',
                            title: 'הגדרות',
                            subtitle: 'כולל את כלל הגדרות התוכנה',
                            leading:
                                const Icon(FluentIcons.settings_24_regular),
                            defaultValue: true,
                            activeColor: Theme.of(context).cardColor,
                          ),
                          SwitchSettingsTile(
                            settingKey: 'key-backup-bookmarks',
                            title: 'סימניות',
                            subtitle: 'כל הסימניות שנשמרו',
                            leading:
                                const Icon(FluentIcons.bookmark_24_regular),
                            defaultValue: true,
                            activeColor: Theme.of(context).cardColor,
                          ),
                          SwitchSettingsTile(
                            settingKey: 'key-backup-history',
                            title: 'היסטוריה',
                            subtitle: 'היסטוריית הלימוד',
                            leading: const Icon(FluentIcons.history_24_regular),
                            defaultValue: true,
                            activeColor: Theme.of(context).cardColor,
                          ),
                          SwitchSettingsTile(
                            settingKey: 'key-backup-notes',
                            title: 'הערות אישיות',
                            subtitle: 'כל ההערות האישיות שלך',
                            leading: const Icon(FluentIcons.note_24_regular),
                            defaultValue: true,
                            activeColor: Theme.of(context).cardColor,
                          ),
                          SwitchSettingsTile(
                            settingKey: 'key-backup-workspaces',
                            title: 'שולחנות עבודה',
                            subtitle: 'כל שולחנות העבודה',
                            leading: const Icon(FluentIcons.grid_24_regular),
                            defaultValue: true,
                            activeColor: Theme.of(context).cardColor,
                          ),
                          SwitchSettingsTile(
                            settingKey: 'key-backup-shamor-zachor',
                            title: 'זכור ושמור',
                            subtitle: 'ספרים ומעקב לימוד',
                            leading: const Icon(FluentIcons.book_24_regular),
                            defaultValue: true,
                            activeColor: Theme.of(context).cardColor,
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropDownSettingsTile<String>(
                      settingKey: 'key-auto-backup-frequency',
                      title: 'גיבוי אוטומטי',
                      leading:
                          const Icon(FluentIcons.calendar_clock_24_regular),
                      selected: 'none',
                      values: const {
                        'none': 'ללא',
                        'weekly': 'כל שבוע',
                        'monthly': 'כל חודש',
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SimpleSettingsTile(
                            title: 'צור גיבוי עכשיו',
                            subtitle: 'שמור גיבוי של הנתונים שנבחרו',
                            leading:
                                const Icon(FluentIcons.arrow_upload_24_regular),
                            onTap: () async {
                              final includeSettings = Settings.getValue<bool>(
                                      'key-backup-settings') ??
                                  true;
                              final includeBookmarks = Settings.getValue<bool>(
                                      'key-backup-bookmarks') ??
                                  true;
                              final includeHistory = Settings.getValue<bool>(
                                      'key-backup-history') ??
                                  true;
                              final includeNotes =
                                  Settings.getValue<bool>('key-backup-notes') ??
                                      true;
                              final includeWorkspaces = Settings.getValue<bool>(
                                      'key-backup-workspaces') ??
                                  true;
                              final includeShamorZachor =
                                  Settings.getValue<bool>(
                                          'key-backup-shamor-zachor') ??
                                      true;

                              try {
                                final backupPath =
                                    await BackupService.createBackup(
                                  includeSettings: includeSettings,
                                  includeBookmarks: includeBookmarks,
                                  includeHistory: includeHistory,
                                  includeNotes: includeNotes,
                                  includeWorkspaces: includeWorkspaces,
                                  includeShamorZachor: includeShamorZachor,
                                );

                                // Verify file was created
                                final file = File(backupPath);
                                final fileExists = await file.exists();
                                final fileSize =
                                    fileExists ? await file.length() : 0;

                                if (!context.mounted) return;

                                if (fileExists) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('הגיבוי נשמר בהצלחה!\n'
                                          'נתיב: $backupPath\n'
                                          'גודל: ${(fileSize / 1024).toStringAsFixed(1)} KB'),
                                      duration: const Duration(seconds: 5),
                                      action: SnackBarAction(
                                        label: 'פתח תיקייה',
                                        onPressed: () async {
                                          final dir =
                                              Directory(file.parent.path);
                                          if (Platform.isWindows) {
                                            await Process.run(
                                                'explorer', [dir.path]);
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'שגיאה: הקובץ לא נוצר בנתיב:\n$backupPath'),
                                      backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                              } catch (e, stackTrace) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'שגיאה ביצירת הגיבוי:\n$e\n\nStack trace:\n${stackTrace.toString().substring(0, 200)}'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 10),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SimpleSettingsTile(
                            title: 'שחזר מגיבוי',
                            subtitle: 'בחר קובץ גיבוי לשחזור',
                            leading: const Icon(
                                FluentIcons.arrow_download_24_regular),
                            onTap: () async {
                              String? filePath = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['json'],
                                    dialogTitle: 'בחר קובץ גיבוי',
                                  )
                                  .then((result) => result?.files.single.path);

                              if (filePath == null) return;

                              if (!context.mounted) return;
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('שחזור מגיבוי?'),
                                  content: const Text(
                                    'פעולה זו תחליף את הנתונים הקיימים בנתונים מהגיבוי. האם להמשיך?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('ביטול'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('אישור',
                                          style: TextStyle(color: Colors.blue)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed != true) return;

                              try {
                                await BackupService.restoreFromBackup(filePath);

                                if (!context.mounted) return;
                                await showDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => AlertDialog(
                                    title: const Text('השחזור הושלם'),
                                    content: const Text(
                                      'הנתונים שוחזרו בהצלחה. יש להפעיל מחדש את התוכנה.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => exit(0),
                                        child: const Text('סגור את התוכנה'),
                                      ),
                                    ],
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('שגיאה בשחזור הגיבוי: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsGroup(
                  title: 'כללי',
                  titleAlignment: Alignment.centerRight,
                  titleTextStyle: const TextStyle(fontSize: 25),
                  children: [
                    SwitchSettingsTile(
                      title: 'סינכרון הספרייה באופן אוטומטי',
                      leading: Icon(FluentIcons.arrow_sync_24_regular),
                      settingKey: 'key-auto-sync',
                      defaultValue: true,
                      enabledLabel:
                          'מאגר הספרים המובנה יתעדכן אוטומטית מאתר אוצריא',
                      disabledLabel: 'מאגר הספרים לא יתעדכן אוטומטית.',
                      activeColor: Theme.of(context).cardColor,
                    ),
                    SwitchSettingsTile(
                      settingKey: 'key-use-fast-search',
                      title: 'חיפוש מהיר באמצעות אינדקס',
                      enabledLabel: 'חיפוש מהיר יותר, נדרש ליצור אינדקס',
                      disabledLabel: 'חיפוש איטי יותר, לא נדרש אינדקס',
                      leading: const Icon(FluentIcons.search_24_regular),
                      defaultValue: state.useFastSearch,
                      onChange: (value) {
                        context
                            .read<SettingsBloc>()
                            .add(UpdateUseFastSearch(value));
                      },
                      activeColor: Theme.of(context).cardColor,
                    ),
                    _buildColumns(2, [
                      BlocBuilder<IndexingBloc, IndexingState>(
                        builder: (context, indexingState) {
                          return SimpleSettingsTile(
                            title: "אינדקס חיפוש",
                            subtitle: indexingState is IndexingInProgress
                                ? "בתהליך עדכון:${indexingState.booksProcessed}/${indexingState.totalBooks}"
                                : "האינדקס מעודכן",
                            leading: const Icon(FluentIcons.table_24_regular),
                            onTap: () async {
                              if (indexingState is IndexingInProgress) {
                                final result = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                          content: const Text(
                                              'האם לעצור את תהליך יצירת האינדקס?'),
                                          actions: <Widget>[
                                            TextButton(
                                              child: const Text('ביטול'),
                                              onPressed: () {
                                                Navigator.pop(context, false);
                                              },
                                            ),
                                            TextButton(
                                              child: const Text('אישור'),
                                              onPressed: () {
                                                Navigator.pop(context, true);
                                              },
                                            ),
                                          ],
                                        ));
                                if (!context.mounted) return;
                                if (result == true) {
                                  context
                                      .read<IndexingBloc>()
                                      .add(CancelIndexing());
                                  setState(() {});
                                }
                              } else {
                                final result = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                          content: const Text(
                                              'האם לאפס את האינדקס?'),
                                          actions: <Widget>[
                                            TextButton(
                                              child: const Text('ביטול'),
                                              onPressed: () {
                                                Navigator.pop(context, false);
                                              },
                                            ),
                                            TextButton(
                                              child: const Text('אישור'),
                                              onPressed: () {
                                                Navigator.pop(context, true);
                                              },
                                            ),
                                          ],
                                        ));
                                if (!context.mounted) return;
                                if (result == true) {
                                  //reset the index
                                  context
                                      .read<IndexingBloc>()
                                      .add(ClearIndex());
                                  final library =
                                      context.read<LibraryBloc>().state.library;
                                  if (library != null) {
                                    context
                                        .read<IndexingBloc>()
                                        .add(StartIndexing(library));
                                  }
                                }
                              }
                            },
                          );
                        },
                      ),
                      SwitchSettingsTile(
                        title: 'עדכון אינדקס',
                        leading: const Icon(FluentIcons.arrow_sync_24_regular),
                        settingKey: 'key-auto-index-update',
                        defaultValue: state.autoUpdateIndex,
                        enabledLabel: 'אינדקס החיפוש יתעדכן אוטומטית',
                        disabledLabel: 'אינדקס החיפוש לא יתעדכן אוטומטית',
                        onChange: (value) async {
                          context
                              .read<SettingsBloc>()
                              .add(UpdateAutoUpdateIndex(value));
                          if (value) {
                            final library =
                                await DataRepository.instance.library;
                            if (!context.mounted) return;
                            context
                                .read<IndexingBloc>()
                                .add(StartIndexing(library));
                          }
                        },
                        activeColor: Theme.of(context).cardColor,
                      ),
                    ]),
                    if (!(Platform.isAndroid || Platform.isIOS))
                      _buildColumns(2, [
                        SimpleSettingsTile(
                          title: 'מיקום הספרייה',
                          subtitle:
                              Settings.getValue<String>('key-library-path') ??
                                  'לא קיים',
                          leading: const Icon(FluentIcons.folder_24_regular),
                          onTap: () async {
                            String? path =
                                await FilePicker.platform.getDirectoryPath();
                            if (path != null) {
                              if (!context.mounted) return;
                              context
                                  .read<LibraryBloc>()
                                  .add(UpdateLibraryPath(path));
                            }
                          },
                        ),
                        Tooltip(
                          message: 'במידה וקיימים ברשותכם ספרים ממאגר זה',
                          child: SimpleSettingsTile(
                            title: 'מיקום ספרי היברובוקס',
                            subtitle: Settings.getValue<String>(
                                    'key-hebrew-books-path') ??
                                'לא קיים',
                            leading: const Icon(FluentIcons.folder_24_regular),
                            onTap: () async {
                              String? path =
                                  await FilePicker.platform.getDirectoryPath();
                              if (path != null) {
                                if (!context.mounted) return;
                                context
                                    .read<LibraryBloc>()
                                    .add(UpdateHebrewBooksPath(path));
                              }
                            },
                          ),
                        ),
                      ]),
                    if (!(Platform.isAndroid || Platform.isIOS))
                      _buildColumns(2, [
                        SwitchSettingsTile(
                          settingKey: 'key-auto-import-new-folders',
                          title: 'ייבוא אוטומטי של תיקיות חדשות',
                          enabledLabel: 'תיקיות חדשות בספרייה יתווספו אוטומטית למאגר',
                          disabledLabel: 'תיקיות חדשות לא יתווספו אוטומטית',
                          leading: const Icon(FluentIcons.folder_sync_24_regular),
                          defaultValue: false,
                          activeColor: Theme.of(context).cardColor,
                        ),
                        SimpleSettingsTile(
                          title: 'סרוק תיקיות חדשות עכשיו',
                          subtitle: 'חפש ויבא תיקיות חדשות בספרייה',
                          leading: const Icon(FluentIcons.scan_24_regular),
                          onTap: () async {
                            final libraryPath = Settings.getValue<String>('key-library-path');
                            if (libraryPath == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('נא להגדיר תחילה את מיקום הספרייה'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            if (!context.mounted) return;
                            
                            // Show scanning dialog
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (dialogContext) {
                                String statusText = 'סורק תיקיות...';
                                
                                return StatefulBuilder(
                                  builder: (context, setDialogState) {
                                    AutoImportService.scanAndImportNewFolders(
                                      forceRun: true, // Manual scan - bypass auto-import setting
                                      onProgress: (status) {
                                        if (dialogContext.mounted) {
                                          setDialogState(() {
                                            statusText = status;
                                          });
                                        }
                                      },
                                    ).then((_) {
                                      Future.delayed(const Duration(seconds: 1), () {
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                          
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('הסריקה הושלמה. רענן את הספרייה כדי לראות את השינויים.'),
                                                backgroundColor: Colors.green,
                                                duration: Duration(seconds: 5),
                                              ),
                                            );
                                          }
                                        }
                                      });
                                    }).catchError((error) {
                                      if (dialogContext.mounted) {
                                        setDialogState(() {
                                          statusText = 'שגיאה: $error';
                                        });
                                        Future.delayed(const Duration(seconds: 2), () {
                                          if (dialogContext.mounted) {
                                            Navigator.pop(dialogContext);
                                          }
                                        });
                                      }
                                    });

                                    return AlertDialog(
                                      title: const Text('סורק תיקיות חדשות'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(),
                                          const SizedBox(height: 16),
                                          Text(statusText, textAlign: TextAlign.center),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ]),
                    if (!(Platform.isAndroid || Platform.isIOS))
                      SimpleSettingsTile(
                        title: 'הוסף ספרים למאגר',
                        subtitle: 'ייבא ספרים מתיקייה למאגר הנתונים',
                        leading: const Icon(FluentIcons.arrow_upload_24_regular),
                        onTap: () async {
                          print('🚀 Starting import process...');
                          
                          // Select folder
                          String? folderPath =
                              await FilePicker.platform.getDirectoryPath();
                          if (folderPath == null) {
                            print('❌ User cancelled folder selection');
                            return;
                          }

                          print('📁 User selected folder: $folderPath');

                          if (!context.mounted) return;

                          // Get seforim.db path from library settings
                          final libraryPath = Settings.getValue<String>('key-library-path');
                          print('📚 Library path from settings: $libraryPath');
                          
                          if (libraryPath == null) {
                            print('❌ Library path not configured');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('נא להגדיר תחילה את מיקום הספרייה בהגדרות'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          final dbPath = path.join(libraryPath, 'seforim.db');
                          final dbFileCheck = File(dbPath);
                          
                          print('📂 Selected folder to import: $folderPath');
                          print('📂 Library path (from settings): $libraryPath');
                          print('💾 Looking for seforim.db at: $dbPath');
                          
                          if (!await dbFileCheck.exists()) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'קובץ מאגר הנתונים לא נמצא!\n\n'
                                  'מחפש ב: $dbPath\n\n'
                                  'ודא שמיקום הספרייה מוגדר נכון בהגדרות.',
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                            return;
                          }
                          
                          print('✅ seforim.db found!');

                          // Show warning about database lock
                          if (!context.mounted) return;
                          
                          // Check disk space for backup
                          final dbFile = File(dbPath);
                          final dbSize = await dbFile.length();
                          final dbSizeMB = (dbSize / 1024 / 1024).toStringAsFixed(2);
                          print('📊 Database size: $dbSizeMB MB');
                          
                          final confirmed = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (context) {
                              bool createBackup = false;  // Changed default to false
                              return StatefulBuilder(
                                builder: (context, setState) => AlertDialog(
                                  title: const Text('📚 ייבוא ספרים'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'מייבא ספרים מ:',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(folderPath, style: const TextStyle(fontSize: 12)),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'אל מאגר הנתונים:',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(dbPath, style: const TextStyle(fontSize: 12)),
                                      const SizedBox(height: 16),
                                      Text(
                                        'גודל מאגר: $dbSizeMB MB',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 16),
                                      CheckboxListTile(
                                        title: const Text('צור גיבוי לפני הייבוא'),
                                        subtitle: Text(
                                          'דורש $dbSizeMB MB נוספים בדיסק',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        value: createBackup,
                                        onChanged: (value) {
                                          setState(() {
                                            createBackup = value ?? false;
                                          });
                                        },
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      const SizedBox(height: 8),
                                      const Row(
                                        children: [
                                          Icon(FluentIcons.info_24_regular, size: 16, color: Colors.orange),
                                          SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'אם אין מספיק מקום בדיסק, בטל את הגיבוי.',
                                              style: TextStyle(fontSize: 11, color: Colors.orange),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, null),
                                      child: const Text('ביטול'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, {
                                        'confirmed': true,
                                        'createBackup': createBackup,
                                      }),
                                      child: const Text('המשך'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );

                          if (confirmed == null || confirmed['confirmed'] != true) {
                            print('❌ User cancelled import');
                            return;
                          }
                          
                          final createBackup = confirmed['createBackup'] as bool? ?? false;
                          print('✅ User confirmed import (backup: $createBackup)');
                          
                          // Show progress dialog
                          if (!context.mounted) return;
                          
                          // Start import in background
                          _showImportProgressDialog(
                            context,
                            folderPath,
                            dbPath,
                            libraryPath,
                            createBackup: createBackup,
                          );
                        },
                      ),
                    if (!(Platform.isAndroid || Platform.isIOS))
                      SimpleSettingsTile(
                        title: 'הסר תיקיות מהמאגר',
                        subtitle: 'מחק תיקיות וכל הספרים שלהן מהמאגר',
                        leading: const Icon(FluentIcons.delete_24_regular),
                        onTap: () async {
                          final libraryPath = Settings.getValue<String>('key-library-path');
                          if (libraryPath == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('נא להגדיר תחילה את מיקום הספרייה בהגדרות'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          final dbPath = path.join(libraryPath, 'seforim.db');
                          final dbFile = File(dbPath);
                          
                          if (!await dbFile.exists()) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('קובץ מאגר הנתונים לא נמצא'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          if (!context.mounted) return;

                          // Get list of user-imported categories
                          final importedCategoryNames = DatabaseImportService.getImportedCategories();

                          // Get top-level categories (level 0 or parentId IS NULL) from database
                          final db = await databaseFactory.openDatabase(dbPath);
                          
                          // Build SQL query based on whether we have imported categories
                          final String sqlQuery;
                          final List<Object?> sqlParams;
                          
                          if (importedCategoryNames.isNotEmpty) {
                            sqlQuery = '''
                              SELECT c.title, COUNT(b.id) as book_count,
                                     CASE WHEN c.title IN (${importedCategoryNames.map((_) => '?').join(',')}) THEN 1 ELSE 0 END as is_imported
                              FROM category c
                              LEFT JOIN book b ON c.id = b.categoryId
                              WHERE c.parentId IS NULL OR c.parentId = 0
                              GROUP BY c.id, c.title
                              ORDER BY is_imported DESC, c.title
                            ''';
                            sqlParams = importedCategoryNames;
                          } else {
                            sqlQuery = '''
                              SELECT c.title, COUNT(b.id) as book_count, 0 as is_imported
                              FROM category c
                              LEFT JOIN book b ON c.id = b.categoryId
                              WHERE c.parentId IS NULL OR c.parentId = 0
                              GROUP BY c.id, c.title
                              ORDER BY c.title
                            ''';
                            sqlParams = [];
                          }
                          
                          final categoriesResult = await db.rawQuery(sqlQuery, sqlParams);
                          await db.close();

                          final categories = categoriesResult
                              .map((row) => {
                                'title': row['title'] as String,
                                'bookCount': row['book_count'] as int,
                                'isImported': (row['is_imported'] as int) == 1,
                              })
                              .toList();

                          if (categories.isEmpty) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('אין תיקיות ראשיות במאגר'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          if (!context.mounted) return;

                          // Show category selection dialog with multi-select
                          final selectedCategories = await showDialog<List<String>>(
                            context: context,
                            builder: (dialogContext) {
                              final Set<String> selected = {};
                              
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  return AlertDialog(
                                  title: const Text('בחר תיקיות למחיקה'),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Text(
                                            'תיקיות ראשיות בלבד\n✓ = יובאה על ידך',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        const Divider(),
                                        Flexible(
                                          child: ListView.builder(
                                            shrinkWrap: true,
                                            itemCount: categories.length,
                                            itemBuilder: (context, index) {
                                              final category = categories[index];
                                              final title = category['title'] as String;
                                              final bookCount = category['bookCount'] as int;
                                              final isImported = category['isImported'] as bool;
                                              final isSelected = selected.contains(title);
                                              
                                              return CheckboxListTile(
                                                value: isSelected,
                                                onChanged: (value) {
                                                  setState(() {
                                                    if (value == true) {
                                                      selected.add(title);
                                                    } else {
                                                      selected.remove(title);
                                                    }
                                                  });
                                                },
                                                secondary: Icon(
                                                  isImported ? Icons.folder_special : Icons.folder_outlined,
                                                  color: isImported ? Colors.green : null,
                                                ),
                                                title: Text(title),
                                                subtitle: isImported && bookCount > 0
                                                    ? Text('$bookCount ספרים')
                                                    : null,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext),
                                      child: const Text('ביטול'),
                                    ),
                                    TextButton(
                                      onPressed: selected.isEmpty
                                          ? null
                                          : () => Navigator.pop(dialogContext, selected.toList()),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.delete, size: 18),
                                          const SizedBox(width: 4),
                                          Text('מחק (${selected.length})'),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                                },
                              );
                            },
                          );

                          if (selectedCategories == null || selectedCategories.isEmpty) return;
                          if (!context.mounted) return;

                          // Confirm deletion
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(FluentIcons.warning_24_regular, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text('אישור מחיקה'),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'האם אתה בטוח שברצונך למחוק ${selectedCategories.length} תיקיות '
                                    'ואת כל הספרים שבהן?\n',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  ...selectedCategories.map((cat) => Padding(
                                    padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.folder, size: 16),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(cat)),
                                      ],
                                    ),
                                  )),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'פעולה זו אינה הפיכה!',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('ביטול'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('מחק הכל'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;
                          if (!context.mounted) return;

                          // Save context and bloc before dialog opens
                          final savedContext = context;
                          final libraryBloc = context.read<LibraryBloc>();

                          // Show progress dialog
                          String statusText = 'מתחיל...';
                          int currentIndex = 0;
                          bool isStarted = false;
                          
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (dialogContext) {
                              return StatefulBuilder(
                                builder: (context, setDialogState) {
                                  // Start deletion only once
                                  if (!isStarted) {
                                    isStarted = true;
                                    
                                    // Delete categories one by one
                                    Future<void> deleteNext() async {
                                      if (currentIndex >= selectedCategories.length) {
                                        // All done
                                        print('🎉 All ${selectedCategories.length} categories deleted');
                                        
                                        // Close dialog first
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }
                                        
                                        // Wait a bit for dialog to close
                                        await Future.delayed(const Duration(milliseconds: 300));
                                        
                                        // Reload library using saved bloc
                                        print('🔄 Refreshing library...');
                                        libraryBloc.add(RefreshLibrary());
                                        print('✅ RefreshLibrary event sent');
                                        
                                        if (savedContext.mounted) {
                                          ScaffoldMessenger.of(savedContext).showSnackBar(
                                            SnackBar(
                                              content: Text('${selectedCategories.length} תיקיות נמחקו והספרייה נטענה מחדש'),
                                              backgroundColor: Colors.green,
                                              duration: const Duration(seconds: 3),
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      
                                      final categoryToDelete = selectedCategories[currentIndex];
                                      
                                      try {
                                        await DatabaseImportService.removeCategoryFromDatabase(
                                          dbPath,
                                          categoryToDelete,
                                          (status) {
                                            if (dialogContext.mounted) {
                                              setDialogState(() {
                                                statusText = '${currentIndex + 1}/${selectedCategories.length}: $categoryToDelete\n$status';
                                              });
                                            }
                                          },
                                        );
                                        
                                        currentIndex++;
                                        await deleteNext();
                                      } catch (error) {
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('שגיאה במחיקת "$categoryToDelete": $error'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                    
                                    // Start deletion process
                                    deleteNext().then((_) {
                                      // Deletion completed
                                      print('✅ All deletions completed');
                                    });
                                  }

                                  return AlertDialog(
                                    title: const Text('מוחק תיקיות'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 16),
                                        Text(statusText, textAlign: TextAlign.center),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    SwitchSettingsTile(
                      settingKey: 'key-dev-channel',
                      title: 'עדכון לגרסאות מפתחים',
                      enabledLabel:
                          'קבלת עדכונים על גרסאות בדיקה, ייתכנו באגים וחוסר יציבות',
                      disabledLabel: 'קבלת עדכונים על גרסאות יציבות בלבד',
                      leading: const Icon(FluentIcons.bug_24_regular),
                      activeColor: Theme.of(context).cardColor,
                    ),
                    SimpleSettingsTile(
                      title: 'איפוס הגדרות',
                      subtitle:
                          'פעולה זו תמחק את כל ההגדרות ותחזיר את התוכנה למצב ההתחלתי',
                      leading:
                          const Icon(FluentIcons.arrow_reset_24_regular),
                      onTap: () async {
                        // דיאלוג לאישור המשתמש
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('איפוס הגדרות?'),
                            content: const Text(
                                'כל ההגדרות האישיות שלך ימחקו. פעולה זו אינה הפיכה. האם להמשיך?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('ביטול')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('אישור',
                                      style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );

                        if (confirmed == true && context.mounted) {
                          Settings.clearCache();

                          // הודעה למשתמש שנדרשת הפעלה מחדש
                          await showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => AlertDialog(
                                      title: const Text('ההגדרות אופסו'),
                                      content: const Text(
                                          'יש לסגור ולהפעיל מחדש את התוכנה כדי שהשינויים יכנסו לתוקף.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () => exit(0),
                                            child: const Text('סגור את התוכנה'))
                                      ]));
                        }
                      },
                    ),
                  ],
                )
              ],
            ),
            ),
          );
        },
      ),
    );
  }
}

/// Slider סימטרי עם תצוגה חיה לרוחב השוליים
class MarginSliderPreview extends StatefulWidget {
  final double initial;
  final double min;
  final double max;
  final int step;
  final ValueChanged<double> onChanged;

  const MarginSliderPreview({
    super.key,
    required this.initial,
    this.min = 0,
    this.max = 500,
    this.step = 2,
    required this.onChanged,
  });

  @override
  State<MarginSliderPreview> createState() => _MarginSliderPreviewState();
}

class _MarginSliderPreviewState extends State<MarginSliderPreview> {
  late double _margin;
  bool _showPreview = false;
  Timer? _disappearTimer;

  // משתנים לעיצוב כדי שיהיה קל לשנות
  final double thumbSize = 20.0; // גודל הידית
  final double trackHeight = 4.0; // גובה הפס
  final double widgetHeight = 50.0; // גובה כל הווידג'ט

  @override
  void initState() {
    super.initState();
    _margin = widget.initial.clamp(widget.min, widget.max / 2);
  }

  @override
  void dispose() {
    _disappearTimer?.cancel();
    super.dispose();
  }

  void _handleDragStart() {
    _disappearTimer?.cancel();
    setState(() => _showPreview = true);
  }

  void _handleDragEnd() {
    _disappearTimer?.cancel();
    _disappearTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showPreview = false);
    });
  }

  // פונקציה לבניית הידית כדי למנוע כפילות קוד
  Widget _buildThumb({required bool isLeft}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            double newMargin = isLeft
                ? _margin + details.delta.dx
                : _margin - details.delta.dx;

            // מגבילים את המרחב לפי רוחב הווידג'ט והגדרות המשתמש
            final maxWidth =
                (context.findRenderObject() as RenderBox).size.width;
            _margin = newMargin
                .clamp(widget.min, maxWidth / 2)
                .clamp(widget.min, widget.max);
          });
          widget.onChanged(_margin);
        },
        onPanStart: (_) => _handleDragStart(),
        onPanEnd: (_) => _handleDragEnd(),
        child: Container(
          width: thumbSize * 2, // אזור לחיצה גדול יותר מהנראות
          height: thumbSize * 2,
          color: Colors.transparent, // אזור הלחיצה שקוף
          alignment: Alignment.center,
          child: Container(
            // --- שינוי 1: עיצוב הידית מחדש ---
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary, // צבע ראשי
              shape: BoxShape.circle,
              boxShadow: kElevationToShadow[1], // הצללה סטנדרטית של פלאטר
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        final previewTextWidth =
            (fullWidth - 2 * _margin).clamp(0.0, fullWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widgetHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTapDown: (details) {
                    final RenderBox renderBox =
                        context.findRenderObject() as RenderBox;
                    final localPosition =
                        renderBox.globalToLocal(details.globalPosition);
                    final tapX = localPosition.dx;

                    double newMargin;

                    double distanceFromCenter = (tapX - fullWidth / 2).abs();
                    newMargin = (fullWidth / 2) - distanceFromCenter;

                    newMargin = newMargin
                        .clamp(widget.min, widget.max)
                        .clamp(widget.min, fullWidth / 2);

                    setState(() {
                      _margin = newMargin;
                    });

                    widget.onChanged(_margin);
                    _handleDragStart();
                    _handleDragEnd();
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: thumbSize * 2,
                        color: Colors.transparent,
                      ),

                      // קו הרקע
                      Container(
                        height: trackHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(trackHeight / 2),
                        ),
                      ),

                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: _margin),
                        child: Container(
                          height: trackHeight,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius:
                                BorderRadius.circular(trackHeight / 2),
                          ),
                        ),
                      ),

                      if (_showPreview)
                        Positioned(
                          left: _margin - 10,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _margin.toStringAsFixed(0),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 12),
                            ),
                          ),
                        ),

                      if (_showPreview)
                        Positioned(
                          right: _margin - 10,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _margin.toStringAsFixed(0),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 12),
                            ),
                          ),
                        ),

                      // הכפתור השמאלי
                      Positioned(
                        left: _margin - (thumbSize),
                        child: _buildThumb(isLeft: true),
                      ),

                      // הכפתור הימני
                      Positioned(
                        right: _margin - (thumbSize),
                        child: _buildThumb(isLeft: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showPreview ? 1.0 : 0.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _showPreview ? 60 : 0,
                curve: Curves.easeInOut,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.5),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: SizedBox(
                  width: previewTextWidth,
                  child: Text(
                    'מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן עד סוף האשמורה הראשונה דברי רבי אליעזר וחכמים אומרים עד חצות רבן גמליאל אומר עד שיעלה עמוד השחר מעשה ובאו בניו מבית המשתה אמרו לו לא קרינו את שמע אמר להם אם לא עלה עמוד השחר חייבין אתם לקרות ולא זו בלבד אמרו אלא כל מה שאמרו חכמים עד חצות מצותן עד שיעלה עמוד השחר',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
