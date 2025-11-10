import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One-time cleanup script to remove duplicate categories
/// This should only be needed once after the bug was introduced
class DatabaseCleanupDuplicates {
  /// Remove duplicate categories from the database
  /// Keeps the category with the lower ID (original) and merges books
  static Future<CleanupResult> cleanupDuplicateCategories(
    String dbPath,
    void Function(String status)? onProgress,
  ) async {
    print('🧹 Starting duplicate categories cleanup...');
    print('📂 Database: $dbPath');

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

      // Find duplicate categories (same title and parentId)
      onProgress?.call('מחפש קטגוריות כפולות...');
      final duplicates = await db.rawQuery('''
        SELECT title, parentId, COUNT(*) as count, GROUP_CONCAT(id) as ids
        FROM category
        GROUP BY title, IFNULL(parentId, 'NULL')
        HAVING COUNT(*) > 1
        ORDER BY title
      ''');

      if (duplicates.isEmpty) {
        print('✅ No duplicate categories found!');
        onProgress?.call('לא נמצאו קטגוריות כפולות');
        return CleanupResult(
          duplicatesFound: 0,
          categoriesRemoved: 0,
          booksMoved: 0,
        );
      }

      print('⚠️ Found ${duplicates.length} sets of duplicate categories');
      for (final dup in duplicates) {
        print('   - "${dup['title']}" (parent: ${dup['parentId']}) - ${dup['count']} copies');
      }

      int totalRemoved = 0;
      int totalBooksMoved = 0;

      await db.transaction((txn) async {
        for (final dup in duplicates) {
          final title = dup['title'] as String;
          final parentId = dup['parentId'];
          final idsString = dup['ids'] as String;
          final ids = idsString.split(',').map((s) => int.parse(s)).toList()
            ..sort(); // Sort to keep the lowest ID

          final keepId = ids.first; // Keep the original (lowest ID)
          final removeIds = ids.sublist(1); // Remove the duplicates

          print('');
          print('🔄 Processing "$title" (parent: $parentId)');
          print('   ✅ Keeping category ID: $keepId');
          print('   🗑️ Removing duplicate IDs: ${removeIds.join(", ")}');

          // Move books from duplicate categories to the original
          for (final removeId in removeIds) {
            final booksToMove = await txn.rawQuery(
              'SELECT COUNT(*) as count FROM book WHERE categoryId = ?',
              [removeId],
            );
            final bookCount = booksToMove.first['count'] as int;

            if (bookCount > 0) {
              await txn.rawUpdate(
                'UPDATE book SET categoryId = ? WHERE categoryId = ?',
                [keepId, removeId],
              );
              print('   📚 Moved $bookCount books from $removeId to $keepId');
              totalBooksMoved += bookCount;
            }

            // Update child categories to point to the kept parent
            final childrenToMove = await txn.rawQuery(
              'SELECT COUNT(*) as count FROM category WHERE parentId = ?',
              [removeId],
            );
            final childCount = childrenToMove.first['count'] as int;

            if (childCount > 0) {
              await txn.rawUpdate(
                'UPDATE category SET parentId = ? WHERE parentId = ?',
                [keepId, removeId],
              );
              print('   📁 Moved $childCount child categories from $removeId to $keepId');
            }

            // Delete the duplicate category
            await txn.delete('category', where: 'id = ?', whereArgs: [removeId]);
            print('   ✅ Deleted duplicate category ID: $removeId');
            totalRemoved++;
          }
        }
      });

      print('');
      print('✅ Cleanup completed successfully!');
      print('   📊 Duplicate sets found: ${duplicates.length}');
      print('   🗑️ Categories removed: $totalRemoved');
      print('   📚 Books moved: $totalBooksMoved');

      onProgress?.call('ניקוי הושלם! הוסרו $totalRemoved קטגוריות כפולות');

      return CleanupResult(
        duplicatesFound: duplicates.length,
        categoriesRemoved: totalRemoved,
        booksMoved: totalBooksMoved,
      );
    } catch (e) {
      print('❌ Error during cleanup: $e');
      rethrow;
    } finally {
      if (db != null) {
        await db.close();
        print('✅ Database closed');
      }
    }
  }

  /// Analyze database for potential issues (dry run)
  static Future<AnalysisResult> analyzeDuplicates(String dbPath) async {
    print('🔍 Analyzing database for duplicates...');
    print('📂 Database: $dbPath');

    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('קובץ מאגר הנתונים לא קיים: $dbPath');
    }

    Database? db;
    try {
      db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      // Find duplicates
      final duplicates = await db.rawQuery('''
        SELECT title, parentId, COUNT(*) as count, GROUP_CONCAT(id) as ids
        FROM category
        GROUP BY title, IFNULL(parentId, 'NULL')
        HAVING COUNT(*) > 1
        ORDER BY title
      ''');

      final details = <DuplicateDetail>[];
      int totalBooksAffected = 0;

      for (final dup in duplicates) {
        final idsString = dup['ids'] as String;
        final ids = idsString.split(',').map((s) => int.parse(s)).toList();

        int booksInDuplicates = 0;
        for (final id in ids.sublist(1)) {
          final result = await db.rawQuery(
            'SELECT COUNT(*) as count FROM book WHERE categoryId = ?',
            [id],
          );
          booksInDuplicates += result.first['count'] as int;
        }

        totalBooksAffected += booksInDuplicates;

        details.add(DuplicateDetail(
          title: dup['title'] as String,
          parentId: dup['parentId'] as int?,
          count: dup['count'] as int,
          ids: ids,
          booksAffected: booksInDuplicates,
        ));
      }

      return AnalysisResult(
        duplicateSets: duplicates.length,
        totalDuplicates: details.fold(0, (sum, d) => sum + d.count - 1),
        booksAffected: totalBooksAffected,
        details: details,
      );
    } finally {
      if (db != null) {
        await db.close();
      }
    }
  }
}

class CleanupResult {
  final int duplicatesFound;
  final int categoriesRemoved;
  final int booksMoved;

  CleanupResult({
    required this.duplicatesFound,
    required this.categoriesRemoved,
    required this.booksMoved,
  });

  @override
  String toString() {
    return 'CleanupResult(duplicates: $duplicatesFound, removed: $categoriesRemoved, books moved: $booksMoved)';
  }
}

class AnalysisResult {
  final int duplicateSets;
  final int totalDuplicates;
  final int booksAffected;
  final List<DuplicateDetail> details;

  AnalysisResult({
    required this.duplicateSets,
    required this.totalDuplicates,
    required this.booksAffected,
    required this.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Analysis Result:');
    buffer.writeln('  Duplicate sets: $duplicateSets');
    buffer.writeln('  Total duplicates: $totalDuplicates');
    buffer.writeln('  Books affected: $booksAffected');
    if (details.isNotEmpty) {
      buffer.writeln('  Details:');
      for (final detail in details) {
        buffer.writeln('    - ${detail.title} (${detail.count} copies, ${detail.booksAffected} books)');
      }
    }
    return buffer.toString();
  }
}

class DuplicateDetail {
  final String title;
  final int? parentId;
  final int count;
  final List<int> ids;
  final int booksAffected;

  DuplicateDetail({
    required this.title,
    required this.parentId,
    required this.count,
    required this.ids,
    required this.booksAffected,
  });
}
