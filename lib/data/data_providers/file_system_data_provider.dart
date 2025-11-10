import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/utils/docx_to_otzaria.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/toc_parser.dart';

/// A data provider that manages file system operations for the library.
///
/// This class handles all file system related operations including:
/// - Reading and parsing book content from various file formats (txt, docx, pdf)
/// - Managing the library structure (categories and books)
/// - Handling external book data from CSV files
/// - Managing book links and metadata
/// - Providing table of contents functionality
/// 
/// Now supports reading from SQLite database with fallback to file system.
class FileSystemData {
  /// Future that resolves to a mapping of book titles to their file system paths
  late Future<Map<String, String>> titleToPath;

  late String libraryPath;

  /// Future that resolves to metadata for all books and categories
  late Future<Map<String, Map<String, dynamic>>> metadata;

  /// SQLite data provider for database access (singleton to prevent memory leaks)
  static final SqliteDataProvider _sqliteProvider = SqliteDataProvider();

  /// Creates a new instance of [FileSystemData] and initializes the title to path mapping
  /// and metadata
  FileSystemData() {
    libraryPath = Settings.getValue<String>('key-library-path') ?? '.';
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
  }

  /// Singleton instance of [FileSystemData]
  static FileSystemData instance = FileSystemData();

  /// Retrieves the complete library structure from the file system and database.
  ///
  /// Reads the library from the configured path and combines it with metadata
  /// to create a full [Library] object containing all categories and books.
  /// Also merges books from SQLite database if available.
  Future<Library> getLibrary() async {
    titleToPath = _getTitleToPath();
    metadata = _getMetadata();
    
    // Get library from file system
    final fsLibrary = await _getLibraryFromDirectory(
        '$libraryPath${Platform.pathSeparator}אוצריא', await metadata);
    
    // Try to merge books from SQLite database
    print('🚀 Attempting to merge books from SQLite...');
    try {
      await _mergeBooksFromDatabase(fsLibrary);
      print('✅ Merged books from SQLite database into library');
      debugPrint('✅ Merged books from SQLite database into library');
    } catch (e) {
      print('⚠️ Could not merge books from database: $e');
      debugPrint('⚠️ Could not merge books from database: $e');
    }
    
    return fsLibrary;
  }

  /// Recursively builds the library structure from a directory.
  ///
  /// Creates a hierarchical structure of categories and books by traversing
  /// the file system directory structure.
  Future<Library> _getLibraryFromDirectory(
      String path, Map<String, dynamic> metadata) async {
    /// Recursive helper function to process directories and build category structure
    Future<Category> getAllCategoriesAndBooksFromDirectory(
        Directory dir, Category? parent) async {
      final title = getTitleFromPath(dir.path);
      Category category = Category(
          title: title,
          description: metadata[title]?['heDesc'] ?? '',
          shortDescription: metadata[title]?['heShortDesc'] ?? '',
          order: metadata[title]?['order'] ?? 999,
          subCategories: [],
          books: [],
          parent: parent);

      // Process each entity in the directory
      await for (FileSystemEntity entity in dir.list()) {
        // Check if entity is accessible before processing
        try {
          // Verify we can access the entity
          await entity.stat();

          if (entity is Directory) {
            // Recursively process subdirectories as categories
            category.subCategories.add(
                await getAllCategoriesAndBooksFromDirectory(
                    Directory(entity.path), category));
          } else if (entity is File) {
            // Only process actual files, not directories mistaken as files
            // Extract topics from the file path
            var topics = entity.path
                .split('אוצריא${Platform.pathSeparator}')
                .last
                .split(Platform.pathSeparator)
                .toList();
            topics = topics.sublist(0, topics.length - 1);

            // Handle special case where title contains " על "
            if (getTitleFromPath(entity.path).contains(' על ')) {
              topics.add(getTitleFromPath(entity.path).split(' על ')[1]);
            }

            // Process PDF files
            if (entity.path.toLowerCase().endsWith('.pdf')) {
              final title = getTitleFromPath(entity.path);
              category.books.add(
                PdfBook(
                  title: title,
                  category: category,
                  path: entity.path,
                  author: metadata[title]?['author'],
                  heShortDesc: metadata[title]?['heShortDesc'],
                  pubDate: metadata[title]?['pubDate'],
                  pubPlace: metadata[title]?['pubPlace'],
                  order: metadata[title]?['order'] ?? 999,
                  topics: topics.join(', '),
                ),
              );
            }

            // Process text and docx files
            if (entity.path.toLowerCase().endsWith('.txt') ||
                entity.path.toLowerCase().endsWith('.docx')) {
              final title = getTitleFromPath(entity.path);
              category.books.add(TextBook(
                  title: title,
                  category: category,
                  author: metadata[title]?['author'],
                  heShortDesc: metadata[title]?['heShortDesc'],
                  pubDate: metadata[title]?['pubDate'],
                  pubPlace: metadata[title]?['pubPlace'],
                  order: metadata[title]?['order'] ?? 999,
                  topics: topics.join(', '),
                  extraTitles: metadata[title]?['extraTitles']));
            }
          }
        } catch (e) {
          // Skip entities that can't be accessed (like directories mistaken as files)
          debugPrint('Skipping inaccessible entity: ${entity.path} - $e');
          continue;
        }
      }

      // Update book order based on generation (from CSV) before sorting
      if (category.books.isNotEmpty) {
        await _updateBooksOrderByGeneration(category.books);
      }
      
      // Sort categories and books by their order
      category.subCategories.sort((a, b) => a.order.compareTo(b.order));
      category.books.sort((a, b) => a.order.compareTo(b.order));
      
      return category;
    }

    // Initialize empty library
    Library library = Library(categories: []);

    // Process top-level directories
    await for (FileSystemEntity entity in Directory(path).list()) {
      if (entity is Directory) {
        // Skip "אודות התוכנה" directory
        final dirName = entity.path.split(Platform.pathSeparator).last;
        if (dirName == 'אודות התוכנה') {
          continue;
        }

        library.subCategories.add(await getAllCategoriesAndBooksFromDirectory(
            Directory(entity.path), library));
      }
    }
    library.subCategories.sort((a, b) => a.order.compareTo(b.order));
    return library;
  }

  /// Retrieves the list of books from Otzar HaChochma
  static Future<List<ExternalBook>> getOtzarBooks() {
    return _getOtzarBooks();
  }

  /// Retrieves the list of books from HebrewBooks
  static Future<List<Book>> getHebrewBooks() {
    return _getHebrewBooks();
  }

  /// Loads a CSV file from assets and parses it into a table using Isolate.
  static Future<List<List<dynamic>>> _loadCsvTable(String assetPath,
      {bool shouldParseNumbers = false}) async {
    final csvData = await rootBundle.loadString(assetPath);
    return await Isolate.run(() {
      // Normalize line endings for cross-platform compatibility
      final normalizedCsvData =
          csvData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      return CsvToListConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        eol: '\n',
        shouldParseNumbers: shouldParseNumbers,
      ).convert(normalizedCsvData);
    });
  }

  /// Internal implementation for loading Otzar HaChochma books from CSV
  static Future<List<ExternalBook>> _getOtzarBooks() async {
    try {
      final table = await _loadCsvTable('assets/otzar_books.csv',
          shouldParseNumbers: false);
      return table.skip(1).map((row) {
        return ExternalBook(
          title: row[1],
          id: int.tryParse(row[0]) ?? -1,
          author: row[2],
          pubPlace: row[3],
          pubDate: row[4],
          topics: row[5],
          link: row[7],
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Internal implementation for loading HebrewBooks from CSV
  static Future<List<Book>> _getHebrewBooks() async {
    try {
      final hebrewBooksPath =
          Settings.getValue<String>('key-hebrew-books-path');

      final table = await _loadCsvTable('assets/hebrew_books.csv',
          shouldParseNumbers: true);

      final books = <Book>[];
      for (final row in table.skip(1)) {
        try {
          if (row[0] == null || row[0].toString().isEmpty) continue;

          // Check if the ID is numeric
          final bookId = row[0].toString().trim();
          if (!RegExp(r'^\d+$').hasMatch(bookId)) continue;
          String? localPath;

          if (hebrewBooksPath != null) {
            localPath =
                '$hebrewBooksPath${Platform.pathSeparator}Hebrewbooks_org_$bookId.pdf';
            if (!File(localPath).existsSync()) {
              localPath =
                  '$hebrewBooksPath${Platform.pathSeparator}$bookId.pdf';
              if (!File(localPath).existsSync()) {
                localPath = null;
              }
            }
          }

          if (localPath != null) {
            // If local file exists, add as PdfBook
            books.add(PdfBook(
              title: row[1].toString(),
              path: localPath,
              author: row[2].toString(),
              pubPlace: row[3].toString(),
              pubDate: row[4].toString(),
              topics: row[15].toString().replaceAll(';', ', '),
              heShortDesc: row[13].toString(),
            ));
          } else {
            // If no local file, add as ExternalBook
            books.add(ExternalBook(
              title: row[1].toString(),
              id: int.parse(bookId),
              author: row[2].toString(),
              pubPlace: row[3].toString(),
              pubDate: row[4].toString(),
              topics: row[15].toString().replaceAll(';', ', '),
              heShortDesc: row[13].toString(),
              link: 'https://beta.hebrewbooks.org/$bookId',
            ));
          }
        } catch (e) {
          debugPrint('Error loading book: $e');
        }
      }
      return books;
    } catch (e) {
      debugPrint('Error loading hebrewbooks: $e');
      return [];
    }
  }

  /// Retrieves all links associated with a specific book.
  ///
  /// First tries to read from SQLite database, then falls back to JSON files.
  Future<List<Link>> getAllLinksForBook(String title) async {
    try {
      // Try SQLite first
      final links = await _sqliteProvider.getBookLinks(title);
      if (links.isNotEmpty) {
        debugPrint('Loaded ${links.length} links from SQLite for "$title"');
        return links;
      }
    } catch (e) {
      debugPrint('SQLite links failed for "$title", trying JSON: $e');
    }

    // Fallback to JSON file
    try {
      File file = File(_getLinksPath(title));
      final jsonString = await file.readAsString();
      final jsonList =
          await Isolate.run(() async => jsonDecode(jsonString) as List);
      return jsonList.map((json) => Link.fromJson(json)).toList();
    } on Exception {
      return [];
    }
  }

  /// Retrieves the text content of a book.
  ///
  /// First tries to read from SQLite database, then falls back to file system.
  /// Supports both plain text and DOCX formats.
  Future<String> getBookText(String title) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Try SQLite first
      final text = await _sqliteProvider.getBookText(title);
      stopwatch.stop();
      debugPrint('✅ Loaded "$title" from SQLite in ${stopwatch.elapsedMilliseconds}ms (${text.length} chars)');
      return text;
    } catch (e) {
      stopwatch.stop();
      debugPrint('⚠️ SQLite failed for "$title" after ${stopwatch.elapsedMilliseconds}ms, trying file system: $e');
    }

    // Fallback to file system
    stopwatch.reset();
    stopwatch.start();
    
    final path = await _getBookPath(title);
    final file = File(path);

    String text;
    if (path.endsWith('.docx')) {
      final bytes = await file.readAsBytes();
      text = await Isolate.run(() => docxToText(bytes, title));
    } else {
      text = await file.readAsString();
    }
    
    stopwatch.stop();
    debugPrint('📁 Loaded "$title" from FILE in ${stopwatch.elapsedMilliseconds}ms (${text.length} chars)');
    return text;
  }

  /// Saves text content to a book file and updates SQLite database.
  ///
  /// Only supports plain text files (.txt). DOCX files cannot be edited.
  /// Creates a backup of the original file before saving.
  /// Updates both the database and file system for consistency.
  Future<void> saveBookText(String title, String content) async {
    debugPrint('💾 Saving "$title" (${content.length} chars)...');
    
    // Try to update SQLite first
    bool updatedInDb = false;
    try {
      final bookExists = await _sqliteProvider.bookExists(title);
      if (bookExists) {
        await _sqliteProvider.updateBookText(title, content);
        updatedInDb = true;
        debugPrint('✅ Updated "$title" in SQLite database');
      } else {
        debugPrint('ℹ️ Book "$title" not in database, will save to file only');
      }
    } catch (e) {
      debugPrint('⚠️ Could not update SQLite for "$title": $e');
      debugPrint('   Will continue to save to file as backup');
    }

    // Also save to file system (as backup or primary storage)
    try {
      final path = await _getBookPath(title);
      
      // Skip if path not found or is DOCX
      if (path.startsWith('error:')) {
        if (updatedInDb) {
          debugPrint('✅ Saved to database only (no file path)');
          return;
        } else {
          throw Exception('Cannot save: $path');
        }
      }
      
      if (path.endsWith('.docx')) {
        if (updatedInDb) {
          debugPrint('✅ Saved to database only (DOCX not editable)');
          return;
        } else {
          throw Exception('Cannot save to DOCX files. Only text files are supported.');
        }
      }

      final file = File(path);
      
      // Create backup of original file if it exists
      if (await file.exists()) {
        final backupPath = '$path.backup.${DateTime.now().millisecondsSinceEpoch}';
        await file.copy(backupPath);
        debugPrint('💾 Created backup: $backupPath');
      }

      try {
        // Save the new content
        await file.writeAsString(content, encoding: utf8);
        debugPrint('✅ Saved "$title" to file: $path');

        // Clean up old backups after successful save
        await _cleanupOldBackups(path);
      } catch (e) {
        // If save fails, restore from backup
        final backupPath = '$path.backup.${DateTime.now().millisecondsSinceEpoch}';
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.copy(path);
          debugPrint('⚠️ Restored from backup after save failure');
        }
        rethrow;
      }
    } catch (e) {
      if (updatedInDb) {
        debugPrint('⚠️ File save failed but database was updated: $e');
        // Don't throw - at least we saved to DB
      } else {
        debugPrint('❌ Failed to save "$title": $e');
        rethrow;
      }
    }
    
    debugPrint('✅ Save completed for "$title"');
  }

  /// Cleans up old backup files for a given file path.
  /// Keeps only the most recent 3 backups, deletes older ones.
  Future<void> _cleanupOldBackups(String originalPath) async {
    try {
      final directory = Directory(originalPath).parent;
      final baseName = originalPath.split(Platform.pathSeparator).last;

      // Find all backup files for this document
      final backupFiles = <File>[];
      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.startsWith('$baseName.backup.')) {
            backupFiles.add(entity);
          }
        }
      }

      // Sort by timestamp (newest first)
      backupFiles.sort((a, b) {
        final aTime = _getBackupTimestamp(a.path);
        final bTime = _getBackupTimestamp(b.path);
        return bTime.compareTo(aTime); // Descending order
      });

      // Keep only the first 3 (most recent)
      for (int i = 3; i < backupFiles.length; i++) {
        try {
          await backupFiles[i].delete();
          debugPrint('Deleted old backup: ${backupFiles[i].path}');
        } catch (e) {
          debugPrint('Failed to delete backup ${backupFiles[i].path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error during backup cleanup: $e');
    }
  }

  /// Extracts timestamp from backup filename
  int _getBackupTimestamp(String backupPath) {
    try {
      final fileName = backupPath.split(Platform.pathSeparator).last;
      final timestampStr = fileName.split('.backup.').last;
      return int.parse(timestampStr);
    } catch (e) {
      return 0; // Return 0 for files that can't be parsed
    }
  }

  /// Manual cleanup of old backup files across the entire library
  Future<int> cleanupAllOldBackups() async {
    int deletedCount = 0;
    try {
      final libraryDir =
          Directory('$libraryPath${Platform.pathSeparator}אוצריא');

      await for (final entity in libraryDir.list(recursive: true)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.contains('.backup.')) {
            // Check if this backup is old (older than 7 days)
            final timestamp = _getBackupTimestamp(entity.path);
            final backupDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final daysOld = DateTime.now().difference(backupDate).inDays;

            if (daysOld > 7) {
              try {
                await entity.delete();
                deletedCount++;
              } catch (e) {
                debugPrint('Failed to delete backup ${entity.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error during global backup cleanup: $e');
    }

    return deletedCount;
  }

  /// Retrieves the content of a specific link within a book.
  ///
  /// First tries to read from SQLite database, then falls back to reading from file.
  Future<String> getLinkContent(Link link) async {
    try {
      final bookTitle = getTitleFromPath(link.path2);
      final lineIndex = link.index2 - 1; // Convert to 0-based index
      
      // Try SQLite first
      try {
        final lines = await _sqliteProvider.getBookLines(bookTitle);
        if (lines.isNotEmpty && lineIndex >= 0 && lineIndex < lines.length) {
          debugPrint('✅ Loaded link content from SQLite: $bookTitle line $lineIndex');
          return lines[lineIndex];
        }
      } catch (e) {
        debugPrint('⚠️ SQLite failed for link content "$bookTitle", trying file: $e');
      }
      
      // Fallback to file system
      String path = await _getBookPath(bookTitle);
      if (path.startsWith('error:')) {
        return 'שגיאה בטעינת קובץ: ${link.path2}';
      }
      return await getLineFromFile(path, link.index2);
    } catch (e) {
      return 'שגיאה בטעינת תוכן המפרש: $e';
    }
  }

  /// Returns a list of all book paths in the library directory.
  ///
  /// This operation is performed in an isolate to prevent blocking the main thread.
  static Future<List<String>> getAllBooksPathsFromDirecctory(
      String path) async {
    return Isolate.run(() async {
      List<String> paths = [];
      final files = await Directory(path).list(recursive: true).toList();
      for (var file in files) {
        paths.add(file.path);
      }
      return paths;
    });
  }

  /// Retrieves the table of contents for a book.
  ///
  /// First tries to read from SQLite database, then falls back to parsing the text.
  Future<List<TocEntry>> getBookToc(String title) async {
    try {
      // Try SQLite first
      final toc = await _sqliteProvider.getBookToc(title);
      if (toc.isNotEmpty) {
        debugPrint('Loaded ${toc.length} TOC entries from SQLite for "$title"');
        return toc;
      }
    } catch (e) {
      debugPrint('SQLite TOC failed for "$title", parsing text: $e');
    }

    // Fallback to parsing text
    return _parseToc(getBookText(title));
  }

  /// Efficiently reads a specific line from a file.
  ///
  /// Uses a stream to read the file line by line until the desired index
  /// is reached, then closes the stream to conserve resources.
  Future<String> getLineFromFile(String path, int index) async {
    File file = File(path);
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(index)
        .toList();
    return (await lines).last;
  }

  /// Updates the mapping of book titles to their file system paths.
  ///
  /// Creates a map where keys are book titles and values are their corresponding
  /// file system paths, excluding PDF files.
  Future<Map<String, String>> _getTitleToPath() async {
    Map<String, String> titleToPath = {};
    List<String> paths = await getAllBooksPathsFromDirecctory(libraryPath);
    for (var path in paths) {
      if (path.toLowerCase().endsWith('.pdf')) continue;
      titleToPath[getTitleFromPath(path)] = path;
    }
    return titleToPath;
  }

  /// Loads and parses the metadata for all books in the library.
  ///
  /// First tries to read from SQLite database, then falls back to JSON file.
  Future<Map<String, Map<String, dynamic>>> _getMetadata() async {
    if (!Settings.isInitialized) {
      await Settings.init(cacheProvider: HiveCache());
    }
    
    Map<String, Map<String, dynamic>> metadata = {};
    
    // Try to get metadata from SQLite first
    try {
      final db = await SqliteDataProvider.database;
      final books = await db.query('book');
      
      for (final book in books) {
        final title = book['title'] as String;
        metadata[title] = {
          'author': book['author'] ?? '',
          'heDesc': book['heDesc'] ?? '',
          'heShortDesc': book['heShortDesc'] ?? '',
          'pubDate': book['pubDate'] ?? '',
          'pubPlace': book['pubPlace'] ?? '',
          'extraTitles': [title], // Can be enhanced if DB has this field
          'order': (book['orderIndex'] as num?)?.toInt() ?? 999,
        };
      }
      
      if (metadata.isNotEmpty) {
        debugPrint('✅ Loaded metadata from SQLite for ${metadata.length} books');
        return metadata;
      }
    } catch (e) {
      debugPrint('⚠️ Could not load metadata from SQLite: $e');
    }
    
    // Fallback to JSON file
    String metadataString = '';
    try {
      File file = File(
          '${Settings.getValue<String>('key-library-path') ?? '.'}${Platform.pathSeparator}metadata.json');
      metadataString = await file.readAsString();
    } catch (e) {
      debugPrint('⚠️ Could not load metadata from JSON: $e');
      return {};
    }
    
    final tempMetadata =
        await Isolate.run(() => jsonDecode(metadataString) as List);

    for (int i = 0; i < tempMetadata.length; i++) {
      final row = tempMetadata[i] as Map<String, dynamic>;
      metadata[row['title'].replaceAll('"', '')] = {
        'author': row['author'] ?? '',
        'heDesc': row['heDesc'] ?? '',
        'heShortDesc': row['heShortDesc'] ?? '',
        'pubDate': row['pubDate'] ?? '',
        'pubPlace': row['pubPlace'] ?? '',
        'extraTitles': row['extraTitles'] == null
            ? [row['title'].toString()]
            : row['extraTitles'].map<String>((e) => e.toString()).toList()
                as List<String>,
        'order': row['order'] == null || row['order'] == ''
            ? 999
            : row['order'].runtimeType == double
                ? row['order'].toInt()
                : row['order'] as int,
      };
    }
    
    debugPrint('✅ Loaded metadata from JSON for ${metadata.length} books');
    return metadata;
  }

  /// Retrieves the file system path for a book with the given title.
  Future<String> _getBookPath(String title) async {
    final titleToPath = await this.titleToPath;
    return titleToPath[title] ?? 'error: book path not found: $title';
  }

  /// Parses the table of contents from book content.
  ///
  /// Creates a hierarchical structure based on HTML heading levels (h1, h2, etc.).
  /// Each entry contains the heading text, its level, and its position in the document.
  Future<List<TocEntry>> _parseToc(Future<String> bookContentFuture) async {
    final String bookContent = await bookContentFuture;

    // Build the hierarchy using the shared parser in an isolate
    return Isolate.run(() => TocParser.parseEntriesFromContent(bookContent));
  }

  /// Gets the path to the JSON file containing links for a specific book.
  String _getLinksPath(String title) {
    return '${Settings.getValue<String>('key-library-path') ?? '.'}${Platform.pathSeparator}links${Platform.pathSeparator}${title}_links.json';
  }

  /// Merges books from SQLite databases into the library structure
  /// Supports both main database (seforim.db) and personal database (my_books.db)
  Future<void> _mergeBooksFromDatabase(Library library) async {
    print('🔄 Starting to merge books from databases...');
    debugPrint('🔄 Starting to merge books from databases...');
    
    // Try main database (seforim.db)
    await _mergeBooksFromSingleDatabase(library, 'seforim.db', 'ספרים ממאגר הנתונים');
    
    // Try personal database (my_books.db)
    await _mergeBooksFromSingleDatabase(library, 'my_books.db', 'הספרים האישיים שלי');
  }
  
  /// Merges books from a single SQLite database
  Future<void> _mergeBooksFromSingleDatabase(
    Library library,
    String dbFileName,
    String categoryName,
  ) async {
    print('📚 Trying to load from $dbFileName...');
    
    try {
      // Create a temporary provider for this specific database
      final provider = SqliteDataProvider();
      
      // Get all book titles from this database
      final dbBookTitles = await provider.getAllBookTitles();
      
      if (dbBookTitles.isEmpty) {
        print('⚠️ No books found in $dbFileName');
        debugPrint('⚠️ No books found in $dbFileName');
        return;
      }
      
      print('🔵 Found ${dbBookTitles.length} books in $dbFileName');
      debugPrint('🔵 Found ${dbBookTitles.length} books in $dbFileName');
      
      // Get existing book titles from file system
      final existingTitles = library.getAllBooks().map((b) => b.title).toSet();
      
      // Find books that are only in DB (not in file system)
      final dbOnlyBooks = dbBookTitles.where((title) => !existingTitles.contains(title)).toList();
      
      print('📊 Total books in DB: ${dbBookTitles.length}');
      print('📊 Existing books in file system: ${existingTitles.length}');
      print('📊 DB-only books: ${dbOnlyBooks.length}');
      if (dbOnlyBooks.length <= 10) {
        print('📚 DB-only books: ${dbOnlyBooks.join(", ")}');
      }
      
      if (dbOnlyBooks.isEmpty) {
        debugPrint('✅ All database books already in file system');
        return;
      }
      
      print('🟢 Building category structure from database...');
      
      // Build the full category hierarchy from database
      await _buildCategoryHierarchyFromDatabase(library, dbOnlyBooks);
    } catch (e) {
      debugPrint('❌ Error merging books from database: $e');
      rethrow;
    }
  }

  /// Builds the complete category hierarchy from database
  Future<void> _buildCategoryHierarchyFromDatabase(Library library, List<String> bookTitles) async {
    try {
      // Get all categories and books with their relationships from DB
      final categoriesData = await _sqliteProvider.getAllCategoriesWithBooks();
      
      if (categoriesData.isEmpty) {
        print('⚠️ No categories found in database');
        return;
      }
      
      print('📂 Found ${categoriesData.length} categories in database');
      
      // Build category map: categoryId -> Category object
      final Map<int, Category> categoryMap = {};
      final Map<String, Category> existingCategoriesByTitle = {};
      
      // Build map of existing categories by title
      void mapExistingCategories(Category cat) {
        existingCategoriesByTitle[cat.title] = cat;
        for (final sub in cat.subCategories) {
          mapExistingCategories(sub);
        }
      }
      for (final cat in library.subCategories) {
        mapExistingCategories(cat);
      }
      
      print('📋 Found ${existingCategoriesByTitle.length} existing categories in library');
      
      // First pass: create or reuse categories
      for (final catData in categoriesData) {
        final catId = catData['id'] as int;
        final title = catData['title'] as String;
        
        // Try to find existing category
        if (existingCategoriesByTitle.containsKey(title)) {
          print('♻️ Reusing existing category: $title');
          categoryMap[catId] = existingCategoriesByTitle[title]!;
        } else {
          // Create new category
          final category = Category(
            title: title,
            description: '',
            shortDescription: '',
            order: 999,
            subCategories: [],
            books: [],
            parent: null,
          );
          categoryMap[catId] = category;
        }
      }
      
      // Second pass: build hierarchy
      for (final catData in categoriesData) {
        final catId = catData['id'] as int;
        final parentId = catData['parentId'] as int?;
        final title = catData['title'] as String;
        
        // Skip if this category already exists in the library
        if (existingCategoriesByTitle.containsKey(title)) {
          continue; // Don't add it again!
        }
        
        if (parentId != null && categoryMap.containsKey(parentId)) {
          // Add as subcategory to parent
          final parent = categoryMap[parentId]!;
          final child = categoryMap[catId]!;
          
          // Check if child already exists in parent
          if (!parent.subCategories.any((c) => c.title == child.title)) {
            child.parent = parent;
            parent.subCategories.add(child);
          }
        } else if (parentId == null) {
          // Root category - add to library only if not already there
          final rootCat = categoryMap[catId]!;
          if (!library.subCategories.any((c) => c.title == rootCat.title)) {
            rootCat.parent = library;
            library.subCategories.add(rootCat);
          }
        }
      }
      
      // Third pass: add books to categories (optimized with batch query)
      int totalAdded = 0;
      print('📚 Adding ${bookTitles.length} books to categories...');
      
      // Get all metadata in one batch query (performance optimization)
      final allMetadata = await _sqliteProvider.getBooksMetadataBatch(bookTitles);
      print('📊 Retrieved metadata for ${allMetadata.length} books');
      
      for (final title in bookTitles) {
        try {
          final bookMeta = allMetadata[title];
          if (bookMeta == null) {
            print('⚠️ No metadata for "$title"');
            continue;
          }
          
          final categoryId = bookMeta['categoryId'] as int?;
          if (categoryId == null || !categoryMap.containsKey(categoryId)) {
            print('⚠️ Book "$title" has invalid category (id: $categoryId)');
            continue;
          }
          
          final category = categoryMap[categoryId]!;
          
          // Check if book already exists in category
          if (category.books.any((b) => b.title == title)) {
            print('  ♻️ Book "$title" already exists in "${category.title}", skipping');
            continue;
          }
          
          category.books.add(TextBook(
            title: title,
            category: category,
            author: bookMeta['author'] as String?,
            heShortDesc: bookMeta['heShortDesc'] as String?,
            pubDate: bookMeta['pubDate'] as String?,
            pubPlace: bookMeta['pubPlace'] as String?,
            order: (bookMeta['orderIndex'] as num?)?.toInt() ?? 999,
            topics: '',
          ));
          
          totalAdded++;
          if (totalAdded <= 5) {
            print('  ✅ Added "$title" to category "${category.title}"');
          }
        } catch (e) {
          print('⚠️ Could not add book "$title": $e');
          debugPrint('⚠️ Could not add book "$title": $e');
        }
      }
      
      print('📊 Total books added: $totalAdded');
      
      // Update order by generation for all categories
      debugPrint('🔄 Updating book order by generation for all categories...');
      for (final category in categoryMap.values) {
        if (category.books.isNotEmpty) {
          await _updateBooksOrderByGeneration(category.books);
        }
      }
      
      // Sort everything
      for (final category in categoryMap.values) {
        category.books.sort((a, b) => a.order.compareTo(b.order));
        category.subCategories.sort((a, b) => a.title.compareTo(b.title));
      }
      
      library.subCategories.sort((a, b) => a.title.compareTo(b.title));
      
      print('✅ Successfully built category hierarchy with $totalAdded books');
    } catch (e) {
      print('❌ Error building category hierarchy: $e');
      debugPrint('❌ Error building category hierarchy: $e');
      rethrow;
    }
  }

  /// Update books order based on their generation from CSV
  Future<void> _updateBooksOrderByGeneration(List<Book> books) async {
    if (books.isEmpty) return;
    
    // Generation order mapping
    const generationOrder = {
      'תורה שבכתב': 100,
      'חז"ל': 200,
      'ראשונים': 300,
      'אחרונים': 400,
      'מחברי זמננו': 500,
      'מפרשים נוספים': 600,
    };
    
    for (final book in books) {
      final originalOrder = book.order;
      
      // Get generation for this book
      String generation = 'מפרשים נוספים'; // default
      
      for (final gen in generationOrder.keys) {
        if (await hasTopic(book.title, gen)) {
          generation = gen;
          break;
        }
      }
      
      // Update order: generation base + original order
      // This keeps books in same generation together, but preserves relative order within generation
      final baseOrder = generationOrder[generation] ?? 600;
      
      // If original order is 999 (default), use alphabetical position
      if (originalOrder == 999) {
        book.order = baseOrder;
      } else {
        // Preserve original order within generation (0-99 range)
        book.order = baseOrder + (originalOrder % 100);
      }
    }
  }

  /// Checks if a book with the given title exists in the library.
  /// 
  /// First checks SQLite database, then falls back to file system.
  Future<bool> bookExists(String title) async {
    try {
      // Try SQLite first
      final exists = await _sqliteProvider.bookExists(title);
      if (exists) return true;
    } catch (e) {
      debugPrint('SQLite bookExists failed for "$title": $e');
    }

    // Fallback to file system
    final titleToPath = await this.titleToPath;
    return titleToPath.keys.contains(title);
  }

  /// Returns true if the book belongs to Tanach (Torah, Neviim or Ketuvim).
  ///
  /// The check is performed by examining the book path and verifying that it
  /// resides under one of the Tanach directories.
  Future<bool> isTanachBook(String title) async {
    final path = await _getBookPath(title);
    final normalized = path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
    final tanachBase =
        '${Platform.pathSeparator}אוצריא${Platform.pathSeparator}תנך${Platform.pathSeparator}';
    final torah = '$tanachBaseתורה';
    final neviim = '$tanachBaseנביאים';
    final ktuvim = '$tanachBaseכתובים';
    return normalized.contains(torah) ||
        normalized.contains(neviim) ||
        normalized.contains(ktuvim);
  }
}
