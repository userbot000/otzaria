import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

class DatabaseImportService {
  static bool _isCancelled = false;
  static const String _importedCategoriesKey = 'key-imported-categories';

  /// Cancel the current import operation
  static void cancelImport() {
    _isCancelled = true;
  }

  /// Reset cancellation flag
  static void resetCancellation() {
    _isCancelled = false;
  }

  /// Get list of user-imported categories
  static List<String> getImportedCategories() {
    final jsonString = Settings.getValue<String>(_importedCategoriesKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.cast<String>();
    } catch (e) {
      print('⚠️ Failed to decode imported categories: $e');
      return [];
    }
  }

  /// Add a category to the imported categories list
  static Future<void> addImportedCategory(String categoryTitle) async {
    final categories = getImportedCategories();
    if (!categories.contains(categoryTitle)) {
      categories.add(categoryTitle);
      await Settings.setValue(_importedCategoriesKey, json.encode(categories));
      print('✅ Added "$categoryTitle" to imported categories list');
    }
  }

  /// Remove a category from the imported categories list
  static Future<void> removeImportedCategory(String categoryTitle) async {
    final categories = getImportedCategories();
    categories.remove(categoryTitle);
    await Settings.setValue(_importedCategoriesKey, json.encode(categories));
    print('✅ Removed "$categoryTitle" from imported categories list');
  }

  /// Get all category IDs recursively (including subcategories)
  static Future<List<int>> _getAllCategoryIdsRecursive(
    DatabaseExecutor db,
    int categoryId,
  ) async {
    final List<int> allIds = [categoryId];
    
    // Get direct children
    final children = await db.rawQuery(
      'SELECT id FROM category WHERE parentId = ?',
      [categoryId],
    );
    
    // Recursively get all descendants
    for (final child in children) {
      final childId = child['id'] as int;
      final descendants = await _getAllCategoryIdsRecursive(db, childId);
      allIds.addAll(descendants);
    }
    
    return allIds;
  }

  /// Remove a category and all its books from the database
  static Future<void> removeCategoryFromDatabase(
    String dbPath,
    String categoryTitle,
    void Function(String status)? onProgress,
  ) async {
    print('🗑️ Starting category removal...');
    print('📂 Database: $dbPath');
    print('📁 Category: $categoryTitle');

    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('קובץ מאגר הנתונים לא קיים: $dbPath');
    }

    Database? db;
    try {
      onProgress?.call('פותח מאגר נתונים...');
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          readOnly: false,
          singleInstance: false,
        ),
      );
      print('✅ Database opened');

      // Find the category ID
      onProgress?.call('מחפש קטגוריה...');
      final categoryResult = await db.rawQuery(
        'SELECT id FROM category WHERE title = ?',
        [categoryTitle],
      );

      if (categoryResult.isEmpty) {
        throw Exception('הקטגוריה "$categoryTitle" לא נמצאה במאגר');
      }

      final categoryId = categoryResult.first['id'] as int;
      print('📁 Found category ID: $categoryId');

      // Count books in this category
      final bookCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM book WHERE categoryId = ?',
        [categoryId],
      );
      final bookCount = bookCountResult.first['count'] as int;
      print('📚 Found $bookCount books in category');

      onProgress?.call('מוחק $bookCount ספרים...');

      // Use proper transaction API for atomic operations
      await db.transaction((txn) async {
        // Get all categories to delete (including subcategories)
        final allCategoryIds = await _getAllCategoryIdsRecursive(txn, categoryId);
        print('📂 Total categories to delete (including subcategories): ${allCategoryIds.length}');
        print('📂 Category IDs: $allCategoryIds');
        
        // Get all book IDs in all these categories
        final placeholders = allCategoryIds.map((_) => '?').join(',');
        final bookIdsResult = await txn.rawQuery(
          'SELECT id FROM book WHERE categoryId IN ($placeholders)',
          allCategoryIds,
        );
        final bookIds = bookIdsResult.map((row) => row['id'] as int).toList();
        print('📚 Total books to delete: ${bookIds.length}');

        if (bookIds.isNotEmpty) {
          // Delete lines for these books (batch delete)
          onProgress?.call('מוחק שורות טקסט...');
          final bookPlaceholders = bookIds.map((_) => '?').join(',');
          await txn.rawDelete(
            'DELETE FROM line WHERE bookId IN ($bookPlaceholders)',
            bookIds,
          );
          print('✅ Lines deleted');

          // Delete TOC entries for these books (batch delete)
          onProgress?.call('מוחק תוכן עניינים...');
          await txn.rawDelete(
            'DELETE FROM tocEntry WHERE bookId IN ($bookPlaceholders)',
            bookIds,
          );
          print('✅ TOC entries deleted');

          // Delete books (batch delete)
          onProgress?.call('מוחק ספרים...');
          await txn.rawDelete(
            'DELETE FROM book WHERE categoryId IN ($placeholders)',
            allCategoryIds,
          );
          print('✅ Books deleted');
        }

        // Delete all categories (batch delete)
        onProgress?.call('מוחק קטגוריות...');
        await txn.rawDelete(
          'DELETE FROM category WHERE id IN ($placeholders)',
          allCategoryIds,
        );
        print('✅ Categories deleted');
        
        // Delete from category_closure table if it exists
        try {
          onProgress?.call('מעדכן עץ קטגוריות...');
          await txn.rawDelete(
            'DELETE FROM category_closure WHERE ancestorId IN ($placeholders) OR descendantId IN ($placeholders)',
            [...allCategoryIds, ...allCategoryIds],
          );
          print('✅ Category closure updated');
        } catch (e) {
          print('⚠️ Could not update category_closure (table might not exist): $e');
        }
      });
      
      print('✅ Transaction committed successfully');

      // Remove from imported categories list
      await removeImportedCategory(categoryTitle);

      onProgress?.call('הקטגוריה "$categoryTitle" נמחקה בהצלחה!');
    } catch (e) {
      print('❌ Fatal error: $e');
      rethrow;
    } finally {
      if (db != null) {
        await db.close();
        print('✅ Database closed');
      }
    }
  }

  /// Get the CREATE TABLE statement for a table
  static Future<String> getTableSchema(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    if (result.isEmpty) {
      throw Exception('Table $tableName not found');
    }
    return result.first['sql'] as String;
  }

  /// Convert books from a folder to a temporary database
  static Future<String> convertBooksToDatabase(
    String folderPath,
    void Function(int current, int total, String bookName)? onProgress, {
    String? mainDbPath,
  }) async {
    _isCancelled = false;
    print('📖 Starting book conversion...');
    print('📂 Folder: $folderPath');
    
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      print('❌ Folder does not exist: $folderPath');
      throw Exception('התיקייה לא קיימת: $folderPath');
    }
    print('✅ Folder exists');

    // Create temporary database
    final tempDbPath = path.join(
      Directory.systemTemp.path,
      'temp_books_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    print('💾 Creating temp database: $tempDbPath');

    final db = await databaseFactory.openDatabase(tempDbPath);
    print('✅ Temp database created');

    // Enable performance optimizations for bulk insert
    await db.execute('PRAGMA synchronous = OFF');
    await db.execute('PRAGMA journal_mode = MEMORY');
    await db.execute('PRAGMA temp_store = MEMORY');
    await db.execute('PRAGMA cache_size = -64000'); // 64MB cache
    print('✅ Performance optimizations enabled');

    try {
      // If mainDbPath provided, copy ALL tables schema from it
      if (mainDbPath != null && await File(mainDbPath).exists()) {
        print('📋 Copying ALL tables schema from main database: $mainDbPath');
        final mainDb = await databaseFactory.openDatabase(mainDbPath);
        
        try {
          // Get ALL tables from main database
          final tablesResult = await mainDb.rawQuery(
            "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
          );
          
          print('📊 Found ${tablesResult.length} tables in main database');
          
          // Create all tables in temp database
          for (final table in tablesResult) {
            final tableName = table['name'] as String;
            final sql = table['sql'] as String;
            
            try {
              await db.execute(sql);
              print('✅ Created table: $tableName');
            } catch (e) {
              print('⚠️ Failed to create table $tableName: $e');
              // Continue anyway - some tables might not be needed
            }
          }
          
          print('✅ All tables created successfully!');
        } finally {
          await mainDb.close();
        }
      } else {
        print('📋 Creating minimal schema (no main DB provided)...');
        
        await db.execute('''
          CREATE TABLE IF NOT EXISTS category (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL
          )
        ''');
        print('✅ Category table created');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS book (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL
          )
        ''');
        print('✅ Book table created');
        
        await db.execute('''
          CREATE TABLE IF NOT EXISTS line (
          id INTEGER PRIMARY KEY,
          book INTEGER NOT NULL,
          line_number INTEGER NOT NULL,
          text TEXT NOT NULL,
          FOREIGN KEY (book) REFERENCES book(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS tocEntry (
          id INTEGER PRIMARY KEY,
          book INTEGER NOT NULL,
          parent INTEGER,
          text INTEGER NOT NULL,
          level INTEGER NOT NULL,
          order_num INTEGER NOT NULL,
          start_line INTEGER NOT NULL,
          FOREIGN KEY (book) REFERENCES book(id),
          FOREIGN KEY (text) REFERENCES tocText(id)
        )
      ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS tocText (
            id INTEGER PRIMARY KEY,
            text TEXT NOT NULL UNIQUE
          )
        ''');
        print('✅ TOC text table created');
      }

      // Get all text files (including subdirectories)
      final files = await folder
          .list(recursive: true)
          .where((entity) =>
              entity is File &&
              (entity.path.endsWith('.txt') || entity.path.endsWith('.text')))
          .cast<File>()
          .toList();

      print('📚 Found ${files.length} text files');
      
      if (files.isEmpty) {
        throw Exception('לא נמצאו קבצי טקסט בתיקייה');
      }

      // Build category tree structure
      print('🌳 Building category tree...');
      final categoryMap = <String, int>{}; // path -> categoryId
      final rootFolderName = path.basename(folderPath);
      int categoryId = 1;
      
      // Create root category
      await db.insert('category', {
        'id': categoryId,
        'title': rootFolderName,
        'level': 0,
      });
      categoryMap[folderPath] = categoryId;
      print('✅ Root category created: $rootFolderName (id: $categoryId)');
      categoryId++;
      
      // Collect all unique directory paths from files (optimized)
      final allDirs = <String>{};
      for (final file in files) {
        var dir = path.dirname(file.path);
        while (dir != folderPath && dir.isNotEmpty) {
          allDirs.add(dir);
          final parent = path.dirname(dir);
          if (parent == dir) break; // Reached root
          dir = parent;
        }
      }
      
      // Sort directories by depth (shallow to deep) to create parent categories first
      final sortedDirs = allDirs.toList()
        ..sort((a, b) => a.split(path.separator).length.compareTo(b.split(path.separator).length));
      
      // Create categories for each subdirectory using batch insert
      if (sortedDirs.isNotEmpty) {
        final batch = db.batch();
        
        for (final dirPath in sortedDirs) {
          if (categoryMap.containsKey(dirPath)) continue;
          
          final dirName = path.basename(dirPath);
          final parentPath = path.dirname(dirPath);
          final parentId = categoryMap[parentPath];
          
          if (parentId == null) {
            print('⚠️ Parent not found for $dirName, using root');
            continue;
          }
          
          final level = dirPath.split(path.separator).length - folderPath.split(path.separator).length;
          
          batch.insert('category', {
            'id': categoryId,
            'title': dirName,
            'parentId': parentId,
            'level': level,
          });
          categoryMap[dirPath] = categoryId;
          print('   ✅ Category: $dirName (id: $categoryId, parent: $parentId, level: $level)');
          categoryId++;
        }
        
        await batch.commit(noResult: true);
        print('✅ Created ${categoryMap.length} categories (batch)');
      } else {
        print('✅ No subdirectories to create');
      }
      
      // Create default source (if source table exists)
      try {
        await db.insert('source', {
          'id': 1,
          'name': 'ייבוא מקומי',
        });
        print('✅ Default source created');
      } catch (e) {
        print('⚠️ Could not create default source: $e');
      }

      int bookId = 1;
      int lineId = 1;
      int tocTextId = 1;
      int tocEntryId = 1;

      // Get actual column names from tables
      print('📋 Reading table schemas...');
      final bookColumns = await getTableColumns(db, 'book');
      final lineColumns = await getTableColumns(db, 'line');
      final tocEntryColumns = await getTableColumns(db, 'tocEntry');
      print('   book columns: ${bookColumns.join(", ")}');
      print('   line columns: ${lineColumns.join(", ")}');
      print('   tocEntry columns: ${tocEntryColumns.join(", ")}');
      
      print('🔄 Starting to process ${files.length} files...');
      
      // Wrap all file processing in a single transaction for maximum performance
      await db.transaction((txn) async {
      
      for (int i = 0; i < files.length; i++) {
        // Check for cancellation
        if (_isCancelled) {
          await db.close();
          final tempFile = File(tempDbPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          throw Exception('הפעולה בוטלה על ידי המשתמש');
        }

        final file = files[i];
        final rawTitle = path.basenameWithoutExtension(file.path);
        
        // Sanitize and validate book title
        final bookTitle = _sanitizeTitle(rawTitle);
        if (bookTitle.isEmpty) {
          print('   ⚠️ Skipping file with invalid title: $rawTitle');
          continue;
        }

        print('📖 Processing file ${i + 1}/${files.length}: $bookTitle');
        onProgress?.call(i + 1, files.length, bookTitle);

        // Check for duplicates
        final existing = await txn.query('book', where: 'title = ?', whereArgs: [bookTitle]);
        if (existing.isNotEmpty) {
          print('   ⚠️ Book "$bookTitle" already exists, skipping');
          continue;
        }

        // Find the correct category for this file based on its directory
        final fileDir = path.dirname(file.path);
        final fileCategoryId = categoryMap[fileDir] ?? categoryMap[folderPath] ?? 1;
        print('   📁 Assigning to category ID: $fileCategoryId');

        // Insert book with all required fields
        try {
          await txn.insert('book', {
            'id': bookId,
            'title': bookTitle,
            'categoryId': fileCategoryId,
            'sourceId': 1,
            'orderIndex': bookId,  // Use bookId as order
            'totalLines': 0,  // Will be updated later
            'isBaseBook': 0,
            'hasTargumConnection': 0,
            'hasReferenceConnection': 0,
            'hasCommentaryConnection': 0,
            'hasOtherConnection': 0,
          });
          print('   ✅ Book inserted: $bookTitle');
        } catch (e) {
          print('   ❌ Failed to insert book: $e');
          throw Exception('Failed to insert book "$bookTitle": $e');
        }

        // Read and insert lines with batch insert for performance
        print('   📝 Reading file content...');
        final content = await file.readAsString();
        final lines = content.split('\n');
        print('   📝 Found ${lines.length} lines');

        int linesInserted = 0;
        
        // Use batch insert within transaction for much better performance
        final batch = txn.batch();
        for (int lineNum = 0; lineNum < lines.length; lineNum++) {
          final lineText = lines[lineNum].trim();
          if (lineText.isNotEmpty) {
            batch.insert('line', {
              'id': lineId,
              'bookId': bookId,
              'lineIndex': lineNum,  // 0-based index
              'content': lineText,   // 'content' not 'text'!
            });
            lineId++;
            linesInserted++;
          }
        }
        
        // Commit all lines at once
        try {
          await batch.commit(noResult: true);
          print('   ✅ Inserted $linesInserted lines (batch)');
        } catch (e) {
          print('   ❌ Failed to insert lines: $e');
          throw Exception('Failed to insert lines in "$bookTitle": $e');
        }

        // Create simple TOC entry
        await txn.insert('tocText', {
          'id': tocTextId,
          'text': bookTitle,
        });

        await txn.insert('tocEntry', {
          'id': tocEntryId,
          'bookId': bookId,
          'parentId': null,  // 'parentId' not 'parent'
          'textId': tocTextId,  // 'textId' not 'text'
          'level': 0,
          'isLastChild': 1,
          'hasChildren': 0,
        });

        tocTextId++;
        tocEntryId++;
        bookId++;
      }
      
      }); // End of transaction
      print('✅ All files processed in single transaction');

      // Clean up any duplicate categories that might have been created
      await _cleanupDuplicateCategories(db);

      await db.close();
      return tempDbPath;
    } catch (e) {
      await db.close();
      // Clean up temp file on error
      final tempFile = File(tempDbPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Get the actual schema of a table from the database
  static Future<List<String>> getTableColumns(Database db, String tableName) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = result.map((row) => row['name'] as String).toList();
    print('📋 Table $tableName columns: ${columns.join(", ")}');
    return columns;
  }

  /// Rebuild the category_closure table for hierarchical queries
  /// This table is used for efficient tree traversal
  static Future<void> _rebuildCategoryClosure(Database db) async {
    print('🔄 Rebuilding category closure table...');
    
    try {
      await db.transaction((txn) async {
        // Clear existing closure table
        await txn.delete('category_closure');
        
        // Get all categories ordered by level (parents first)
        final categories = await txn.rawQuery('''
          SELECT id, parentId FROM category ORDER BY level ASC, id ASC
        ''');
        
        // Build ancestor map in memory (much faster than queries)
        final Map<int, Set<int>> ancestorMap = {};
        
        // Use batch for all inserts
        final batch = txn.batch();
        
        for (final cat in categories) {
          final catId = cat['id'] as int;
          final parentId = cat['parentId'] as int?;
          
          // Initialize ancestor set for this category
          ancestorMap[catId] = <int>{catId}; // Self-reference
          
          // Add self-reference to batch
          batch.insert('category_closure', {
            'ancestorId': catId,
            'descendantId': catId,
          });
          
          // Add all ancestors from parent
          if (parentId != null && ancestorMap.containsKey(parentId)) {
            for (final ancestorId in ancestorMap[parentId]!) {
              ancestorMap[catId]!.add(ancestorId);
              batch.insert('category_closure', {
                'ancestorId': ancestorId,
                'descendantId': catId,
              });
            }
          }
        }
        
        // Commit all inserts at once
        await batch.commit(noResult: true);
        
        print('   ✅ Rebuilt closure table with ${categories.length} categories');
      });
      
      print('✅ Category closure table rebuilt successfully');
    } catch (e) {
      print('⚠️ Error rebuilding closure table: $e');
      // Don't throw - this is not critical
    }
  }

  /// Clean up duplicate categories (same title and parent)
  /// Keeps the category with the lowest ID and updates all references
  /// Note: This should be called OUTSIDE of any transaction
  static Future<void> _cleanupDuplicateCategories(Database db) async {
    print('🧹 Checking for duplicate categories...');
    
    try {
      // Find duplicate categories (same title and parentId)
      final duplicates = await db.rawQuery('''
        SELECT title, parentId, GROUP_CONCAT(id) as ids, COUNT(*) as count
        FROM category
        GROUP BY title, IFNULL(parentId, 'NULL')
        HAVING count > 1
      ''');
      
      if (duplicates.isEmpty) {
        print('✅ No duplicate categories found');
        return;
      }
      
      print('⚠️ Found ${duplicates.length} duplicate category groups');
      
      // Process each duplicate group in its own transaction
      for (final dup in duplicates) {
        await db.transaction((txn) async {
          final title = dup['title'] as String;
          final idsStr = dup['ids'] as String;
          final ids = idsStr.split(',').map((s) => int.parse(s)).toList()..sort();
          
          final keepId = ids.first; // Keep the lowest ID
          final deleteIds = ids.sublist(1); // Delete the rest
          
          print('   🔄 Category "$title": keeping id=$keepId, deleting ${deleteIds.join(", ")}');
          
          // Update all books that reference the duplicate categories
          for (final deleteId in deleteIds) {
            await txn.rawUpdate('''
              UPDATE book SET categoryId = ? WHERE categoryId = ?
            ''', [keepId, deleteId]);
            
            // Update child categories that reference this as parent
            await txn.rawUpdate('''
              UPDATE category SET parentId = ? WHERE parentId = ?
            ''', [keepId, deleteId]);
          }
          
          // Delete the duplicate categories
          await txn.rawDelete('''
            DELETE FROM category WHERE id IN (${deleteIds.map((_) => '?').join(',')})
          ''', deleteIds);
          
          print('   ✅ Cleaned up "${title}"');
        });
      }
      
      print('✅ Duplicate categories cleaned up successfully');
    } catch (e) {
      print('⚠️ Error cleaning up duplicates: $e');
      // Don't throw - this is a cleanup operation, not critical
    }
  }

  /// Sanitize book title to prevent SQL injection and invalid characters
  static String _sanitizeTitle(String title) {
    // Remove control characters and trim
    title = title.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    
    // Limit length to prevent overflow
    if (title.length > 255) {
      title = title.substring(0, 255);
    }
    
    return title;
  }

  /// Merge temporary database with main seforim.db
  static Future<void> mergeDatabases(
    String mainDbPath,
    String tempDbPath,
    void Function(String status)? onProgress, {
    bool createBackup = true,
    String? backupPath,
  }) async {
    print('🔄 Starting merge process...');
    print('📂 Main DB: $mainDbPath');
    print('📂 Temp DB: $tempDbPath');
    
    // Check if main DB is locked
    final mainDbFile = File(mainDbPath);
    if (!await mainDbFile.exists()) {
      throw Exception('קובץ מאגר הנתונים לא קיים: $mainDbPath');
    }
    
    print('✅ Main DB file exists');
    
    Database? mainDb;
    try {
      print('🔓 Attempting to open main database...');
      
      // Try to enable WAL mode for concurrent access
      try {
        final testDb = await databaseFactory.openDatabase(mainDbPath);
        await testDb.execute('PRAGMA journal_mode=WAL');
        await testDb.close();
        print('✅ WAL mode enabled');
      } catch (e) {
        print('⚠️ Could not enable WAL mode: $e');
      }
      
      mainDb = await databaseFactory.openDatabase(
        mainDbPath,
        options: OpenDatabaseOptions(
          readOnly: false,
          singleInstance: true,  // Prevent concurrent access issues
        ),
      );
      print('✅ Main database opened successfully (single instance mode)');
      
      // Check if database is locked by trying an immediate transaction
      try {
        await mainDb.execute('BEGIN IMMEDIATE');
        await mainDb.execute('ROLLBACK');
        print('✅ Database lock check passed');
      } catch (e) {
        await mainDb.close();
        throw Exception('מאגר הנתונים נעול על ידי תהליך אחר.\n\nסגור את האפליקציה ונסה שוב.\n\nשגיאה: $e');
      }
      
      // Enable performance optimizations for merge
      await mainDb.execute('PRAGMA synchronous = NORMAL');
      await mainDb.execute('PRAGMA cache_size = -64000'); // 64MB cache
      print('✅ Merge performance optimizations enabled');
      
      // Get actual schema from main database
      print('📋 Reading main database schema...');
      final categoryColumns = await getTableColumns(mainDb, 'category');
      final bookColumns = await getTableColumns(mainDb, 'book');
      final lineColumns = await getTableColumns(mainDb, 'line');
      final tocEntryColumns = await getTableColumns(mainDb, 'tocEntry');
      final tocTextColumns = await getTableColumns(mainDb, 'tocText');
      
      print('');
      print('🔍 DETECTED SCHEMA:');
      print('   category: ${categoryColumns.join(", ")}');
      print('   book: ${bookColumns.join(", ")}');
      print('   line: ${lineColumns.join(", ")}');
      print('   tocEntry: ${tocEntryColumns.join(", ")}');
      print('   tocText: ${tocTextColumns.join(", ")}');
      print('');
      
    } catch (e) {
      print('❌ Failed to open main database: $e');
      throw Exception('לא ניתן לפתוח את מאגר הנתונים.\n\nהסיבה: $e\n\nנסה לסגור את האפליקציה ולהריץ את הייבוא מחוץ לאפליקציה.');
    }

    try {
      // Create backup if requested
      if (createBackup) {
        onProgress?.call('יוצר גיבוי...');
        print('💾 Creating backup...');

        try {
          final defaultBackupPath = '$mainDbPath.backup.${DateTime.now().millisecondsSinceEpoch}';
          final finalBackupPath = backupPath ?? defaultBackupPath;
          
          // Check if there's enough space
          final dbFile = File(mainDbPath);
          final dbSize = await dbFile.length();
          print('📊 Database size: ${(dbSize / 1024 / 1024).toStringAsFixed(2)} MB');
          
          await dbFile.copy(finalBackupPath);
          print('✅ Backup created: $finalBackupPath');
        } catch (e) {
          print('⚠️ Backup failed: $e');
          if (e.toString().contains('not enough space')) {
            print('💡 Continuing without backup due to disk space...');
            onProgress?.call('⚠️ אין מספיק מקום לגיבוי, ממשיך בלי גיבוי...');
          } else {
            rethrow;
          }
        }
      } else {
        print('⚠️ Skipping backup as requested');
        onProgress?.call('מדלג על גיבוי...');
      }

      onProgress?.call('מחשב offsets...');
      print('🔢 Calculating offsets...');

      // Get max IDs from main database
      final maxBookIdResult = await mainDb.rawQuery('SELECT MAX(id) as max_id FROM book');
      final maxBookId = maxBookIdResult.first['max_id'] as int? ?? 0;
      print('📚 Max book ID: $maxBookId');

      final maxLineIdResult = await mainDb.rawQuery('SELECT MAX(id) as max_id FROM line');
      final maxLineId = maxLineIdResult.first['max_id'] as int? ?? 0;
      print('📝 Max line ID: $maxLineId');

      final maxTocEntryIdResult = await mainDb.rawQuery('SELECT MAX(id) as max_id FROM tocEntry');
      final maxTocEntryId = maxTocEntryIdResult.first['max_id'] as int? ?? 0;
      print('📖 Max TOC entry ID: $maxTocEntryId');

      final maxTocTextIdResult = await mainDb.rawQuery('SELECT MAX(id) as max_id FROM tocText');
      final maxTocTextId = maxTocTextIdResult.first['max_id'] as int? ?? 0;
      print('📑 Max TOC text ID: $maxTocTextId');

      final maxCategoryIdResult = await mainDb.rawQuery('SELECT MAX(id) as max_id FROM category');
      final maxCategoryId = maxCategoryIdResult.first['max_id'] as int? ?? 0;
      print('📂 Max category ID: $maxCategoryId');

      // Calculate offsets
      final categoryOffset = maxCategoryId + 10000;
      final bookOffset = maxBookId + 1000;
      final lineOffset = maxLineId + 10000;
      final tocEntryOffset = maxTocEntryId + 1000;
      final tocTextOffset = maxTocTextId + 1000;
      
      print('➕ Offsets: book=$bookOffset, line=$lineOffset, toc=$tocEntryOffset');

      onProgress?.call('מאחד מאגרי נתונים...');
      print('🔗 Attaching temp database...');

      // Attach temp database
      await mainDb.execute("ATTACH DATABASE '$tempDbPath' AS temp_db");
      print('✅ Temp database attached');

      // Start transaction
      print('🔄 Starting transaction...');
      await mainDb.execute('BEGIN TRANSACTION');

      try {
        // Get columns again for INSERT statements
        final bkColumns = await getTableColumns(mainDb, 'book');
        
        // Build category mapping: temp_id -> main_id
        print('🌳 Building category tree mapping...');
        final categoryMapping = <int, int>{}; // temp_id -> main_id
        
        // Get all categories from temp DB, ordered by level (parents first)
        final tempCategories = await mainDb.rawQuery('''
          SELECT id, title, parentId, level
          FROM temp_db.category
          ORDER BY level ASC, id ASC
        ''');
        
        print('📂 Processing ${tempCategories.length} categories...');
        
        // Load all existing categories at once for faster lookup
        final existingCategories = await mainDb.rawQuery('''
          SELECT id, title, parentId FROM category
        ''');
        
        // Build lookup map: "title_parentId" -> id
        // Use consistent key format: if parentId is null, use empty string
        final existingCatMap = <String, int>{};
        for (final cat in existingCategories) {
          final title = cat['title'] as String;
          final parentId = cat['parentId'] as int?;
          final key = parentId != null ? '${title}_$parentId' : '${title}_ROOT';
          existingCatMap[key] = cat['id'] as int;
        }
        print('   📋 Loaded ${existingCatMap.length} existing categories for lookup');
        
        // Process categories one by one to maintain proper parent-child relationships
        // We can't use batch here because we need to update the lookup map as we go
        for (final tempCat in tempCategories) {
          final tempId = tempCat['id'] as int;
          final title = tempCat['title'] as String;
          final tempParentId = tempCat['parentId'] as int?;
          final level = tempCat['level'] as int;
          
          // Find parent in main DB (if exists)
          int? mainParentId;
          if (tempParentId != null) {
            mainParentId = categoryMapping[tempParentId];
            if (mainParentId == null) {
              print('   ⚠️ Parent mapping not found for temp_id=$tempParentId, using root');
            }
          }
          
          // Check if category already exists using the lookup map
          // Use same key format as above
          final lookupKey = mainParentId != null ? '${title}_$mainParentId' : '${title}_ROOT';
          final existingId = existingCatMap[lookupKey];
          
          print('   🔍 Looking for "$title" with key: $lookupKey');
          
          if (existingId != null) {
            categoryMapping[tempId] = existingId;
            print('   ✅ Category "$title" exists (temp:$tempId -> main:$existingId)');
          } else {
            // Create new category
            final newId = maxCategoryId + categoryOffset + tempId;
            
            final insertData = <String, dynamic>{
              'id': newId,
              'title': title,
              'level': level,
            };
            if (mainParentId != null) {
              insertData['parentId'] = mainParentId;
            }
            
            await mainDb.insert('category', insertData);
            categoryMapping[tempId] = newId;
            
            // IMPORTANT: Add to lookup map so child categories can find it!
            existingCatMap[lookupKey] = newId;
            
            print('   ✅ Created "$title" (temp:$tempId -> main:$newId, parent:$mainParentId)');
          }
        }
        
        print('✅ Category mapping complete: ${categoryMapping.length} categories');

        // Copy books with correct category mapping
        // Note: We're already inside a transaction, so we insert directly
        print('📚 Copying books with category mapping...');
        final tempBooks = await mainDb.rawQuery('SELECT * FROM temp_db.book');
        
        int skippedBooks = 0;
        
        for (final book in tempBooks) {
          final tempCategoryId = book['categoryId'] as int;
          final mainCategoryId = categoryMapping[tempCategoryId];
          
          if (mainCategoryId == null) {
            print('   ⚠️ Category mapping not found for book "${book['title']}", skipping');
            skippedBooks++;
            continue;
          }
          
          final bookData = <String, dynamic>{};
          for (final col in bkColumns) {
            if (col == 'id') {
              bookData[col] = (book['id'] as int) + bookOffset;
            } else if (col == 'categoryId') {
              bookData[col] = mainCategoryId;
            } else {
              bookData[col] = book[col];
            }
          }
          
          await mainDb.insert('book', bookData);
        }
        
        print('✅ Books copied with correct categories (${tempBooks.length - skippedBooks} books, $skippedBooks skipped)');

        // Copy TOC texts (use INSERT OR IGNORE for UNIQUE constraint)
        print('📑 Copying TOC texts...');
        await mainDb.execute('''
          INSERT OR IGNORE INTO tocText (id, text)
          SELECT 
            id + $tocTextOffset,
            text
          FROM temp_db.tocText
        ''');
        print('✅ TOC texts copied');

        // Copy lines - use actual columns
        print('📝 Copying lines...');
        final lineColumns = await getTableColumns(mainDb, 'line');
        final lineCols = lineColumns.join(', ');
        final lineColsWithOffset = lineColumns.map((col) {
          if (col == 'id') return 'id + $lineOffset';
          if (col == 'bookId') return 'bookId + $bookOffset';
          return col;
        }).join(', ');
        
        print('   Using columns: $lineCols');
        await mainDb.execute('''
          INSERT INTO line ($lineCols)
          SELECT $lineColsWithOffset
          FROM temp_db.line
        ''');
        print('✅ Lines copied');

        // Copy TOC entries - use actual columns
        print('📖 Copying TOC entries...');
        final tocColumns = await getTableColumns(mainDb, 'tocEntry');
        final tocCols = tocColumns.join(', ');
        final tocColsWithOffset = tocColumns.map((col) {
          if (col == 'id') return 'id + $tocEntryOffset';
          if (col == 'bookId') return 'bookId + $bookOffset';
          if (col == 'parentId') return 'CASE WHEN parentId IS NULL THEN NULL ELSE parentId + $tocEntryOffset END';
          if (col == 'textId') return 'textId + $tocTextOffset';
          return col;
        }).join(', ');
        
        print('   Using columns: $tocCols');
        await mainDb.execute('''
          INSERT INTO tocEntry ($tocCols)
          SELECT $tocColsWithOffset
          FROM temp_db.tocEntry
        ''');
        print('✅ TOC entries copied');
        
        print('💾 Committing transaction...');
        await mainDb.execute('COMMIT');
        print('✅ Transaction committed successfully');
        onProgress?.call('הושלם בהצלחה!');
      } catch (e) {
        print('❌ Error during merge: $e');
        print('🔙 Rolling back transaction...');
        await mainDb.execute('ROLLBACK');
        print('✅ Rollback completed');
        onProgress?.call('שגיאה: $e');
        rethrow;
      } finally {
        print('🔌 Detaching temp database...');
        await mainDb.execute('DETACH DATABASE temp_db');
        print('✅ Temp database detached');
      }
      
      // Rebuild category closure table after merge
      onProgress?.call('מעדכן עץ קטגוריות...');
      await _rebuildCategoryClosure(mainDb);
      
      // Clean up any duplicate categories after merge (outside transaction)
      onProgress?.call('מנקה כפילויות...');
      await _cleanupDuplicateCategories(mainDb);
      
    } catch (e) {
      print('❌ Fatal error in merge: $e');
      rethrow;
    } finally {
      print('🔒 Closing main database...');
      await mainDb.close();
      print('✅ Main database closed');
    }
  }

  /// Full import process: convert and merge
  static Future<void> importBooksFromFolder(
    String folderPath,
    String mainDbPath,
    void Function(String status, {int? current, int? total})? onProgress, {
    bool createBackup = true,
    String? backupPath,
    bool deleteSourceFiles = false,
  }) async {
    String? tempDbPath;
    List<File> importedFiles = [];

    try {
      onProgress?.call('ממיר קבצים למאגר נתונים...');

      // Get list of files before conversion
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        importedFiles = await folder
            .list(recursive: true)
            .where((entity) =>
                entity is File &&
                (entity.path.endsWith('.txt') || entity.path.endsWith('.text')))
            .cast<File>()
            .toList();
      }

      // Convert books to temporary database
      tempDbPath = await convertBooksToDatabase(
        folderPath,
        (current, total, bookName) {
          onProgress?.call(
            'ממיר: $bookName',
            current: current,
            total: total,
          );
        },
        mainDbPath: mainDbPath,
      );

      onProgress?.call('מאחד עם מאגר הנתונים הראשי...');

      // Merge with main database
      await mergeDatabases(
        mainDbPath,
        tempDbPath,
        (status) => onProgress?.call(status),
        createBackup: createBackup,
        backupPath: backupPath,
      );

      // Add root category to imported categories list (using folder name)
      // Note: This registers only the root folder, but the entire tree structure is preserved
      final folderName = path.basename(folderPath);
      await addImportedCategory(folderName);
      print('📝 Registered root category "$folderName" as user-imported (tree structure preserved)');

      // Delete source text files if requested (for internal folders)
      if (deleteSourceFiles && importedFiles.isNotEmpty) {
        onProgress?.call('מוחק קבצי טקסט מקוריים...');
        print('🗑️ Deleting ${importedFiles.length} source text files...');
        
        int deletedCount = 0;
        for (final file in importedFiles) {
          try {
            if (await file.exists()) {
              await file.delete();
              deletedCount++;
              print('   ✅ Deleted: ${path.basename(file.path)}');
            }
          } catch (e) {
            print('   ⚠️ Failed to delete ${path.basename(file.path)}: $e');
            // Continue with other files even if one fails
          }
        }
        print('✅ Deleted $deletedCount/${ importedFiles.length} text files');
      }

      onProgress?.call('הושלם בהצלחה!');
    } finally {
      // Clean up temporary database
      if (tempDbPath != null) {
        final tempFile = File(tempDbPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }
  }
}
