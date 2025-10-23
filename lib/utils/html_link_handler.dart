import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

/// מחלקה לטיפול בקישורי HTML בתוך הטקסט
class HtmlLinkHandler {
  /// מטפל בלחיצה על קישור HTML
  /// 
  /// הפונקציה מפרשת קישורים בפורמטים הבאים:
  /// - book://שם_הספר - פותח ספר בתחילת הספר
  /// - book://שם_הספר#כותרת - פותח ספר ומנווט לכותרת ספציפית
  /// - #כותרת - מנווט לכותרת באותו ספר
  /// 
  /// דוגמאות:
  /// - <a href="book://ברכות">ברכות</a>
  /// - <a href="book://ברכות#דף ב">ברכות דף ב</a>
  /// - <a href="#דף ג">דף ג</a>
  static Future<bool> handleLink(
    BuildContext context,
    String url,
    Function(TextBookTab) openBookCallback,
  ) async {
    try {
      // בדיקה אם זה קישור פנימי לכותרת באותו ספר
      if (url.startsWith('#')) {
        final headerName = Uri.decodeComponent(url.substring(1));
        await _navigateToHeader(context, headerName);
        return true;
      }

      // בדיקה אם זה קישור לספר
      if (url.startsWith('book://')) {
        final bookUrl = url.substring(7); // הסרת "book://"
        
        String bookTitle;
        String? headerName;
        
        // בדיקה אם יש כותרת ספציפית
        if (bookUrl.contains('#')) {
          final parts = bookUrl.split('#');
          bookTitle = Uri.decodeComponent(parts[0]);
          headerName = Uri.decodeComponent(parts[1]);
        } else {
          bookTitle = Uri.decodeComponent(bookUrl);
        }
        
        await _openBookWithHeader(context, bookTitle, headerName, openBookCallback);
        return true;
      }

      // אם זה לא קישור שאנחנו מטפלים בו, נחזיר false
      return false;
    } catch (e) {
      debugPrint('שגיאה בטיפול בקישור: $e');
      
      // הצגת הודעת שגיאה למשתמש
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בפתיחת הקישור: $url'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      return false;
    }
  }

  /// מנווט לכותרת באותו ספר הנוכחי
  static Future<void> _navigateToHeader(BuildContext context, String headerName) async {
    try {
      // נקבל את הספר הנוכחי מה-BLoC
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;
      
      if (state is! TextBookLoaded) {
        throw Exception('לא ניתן לנווט - הספר לא נטען');
      }

      // חיפוש הכותרת בתוכן הספציפי
      final index = await _findHeaderIndex(state.book, headerName);
      
      if (index != null) {
        // ניווט לאינדקס שנמצא
        state.scrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('נווט ל: $headerName'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('לא נמצאה הכותרת: $headerName');
      }
    } catch (e) {
      debugPrint('שגיאה בניווט לכותרת: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('לא ניתן לנווט לכותרת: $headerName'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// פותח ספר ומנווט לכותרת ספציפית (אם צוינה)
  static Future<void> _openBookWithHeader(
    BuildContext context,
    String bookTitle,
    String? headerName,
    Function(TextBookTab) openBookCallback,
  ) async {
    try {
      // חיפוש הספר בספרייה
      final library = await DataRepository.instance.library;
      
      // קבלת רשימת כל הספרים לבדיקה
      final allBooks = await library.getAllBooks();
      
      final foundBook = await library.findBookByTitle(bookTitle, TextBook);
      
      if (foundBook == null) {
        // נסה לחפש בלי להגביל לטיפוס TextBook
        final anyBook = await library.findBookByTitle(bookTitle);
        
        if (anyBook != null) {
          throw Exception('הספר "$bookTitle" נמצא אבל הוא מטיפוס ${anyBook.runtimeType}, לא TextBook');
        }
        
        // הצגת רשימת ספרים זמינים למשתמש
        final availableBooks = allBooks.take(10).map((b) => b.title).join(', ');
        throw Exception('לא נמצא ספר בשם: "$bookTitle".\nספרים זמינים (דוגמאות): $availableBooks');
      }

      // וידוא שזה TextBook
      if (foundBook is! TextBook) {
        throw Exception('הספר $bookTitle אינו ספר טקסט');
      }

      final book = foundBook as TextBook;
      int startIndex = 0;
      
      // אם צוינה כותרת, נחפש את האינדקס שלה
      if (headerName != null && headerName.isNotEmpty) {
        final headerIndex = await _findHeaderIndex(book, headerName);
        if (headerIndex != null) {
          startIndex = headerIndex;
        } else {
          // אם לא נמצאה הכותרת, נציג אזהרה אבל עדיין נפתח את הספר
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('לא נמצאה הכותרת "$headerName" בספר $bookTitle, פותח את תחילת הספר'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }

      // פתיחת הספר
      final tab = TextBookTab(
        book: book,
        index: startIndex,
        openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );
      
      openBookCallback(tab);
      
      if (context.mounted && headerName != null && headerName.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('פתח ספר: $bookTitle${headerName != null ? ' - $headerName' : ''}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('שגיאה בפתיחת ספר: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('לא ניתן לפתוח את הספר: $bookTitle'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// מחפש את האינדקס של כותרת בספר
  static Future<int?> _findHeaderIndex(TextBook book, String headerName) async {
    try {
      // קבלת תוכן הספציפי
      final tableOfContents = await book.tableOfContents;
      
      // חיפוש בתוכן העניינים
      for (final entry in tableOfContents) {
        if (isHeaderMatch(entry.text, headerName)) {
          return entry.index;
        }
      }

      // אם לא נמצא בתוכן העניינים, נחפש בתוכן הספר עצמו
      final content = await book.text;
      final lines = content.split('\n');
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        // הסרת תגי HTML לחיפוש נקי
        final cleanLine = line.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        
        if (isHeaderMatch(cleanLine, headerName)) {
          return i;
        }
      }

      return null;
    } catch (e) {
      debugPrint('שגיאה בחיפוש כותרת: $e');
      return null;
    }
  }

  /// בדיקה אם טקסט תואם לכותרת המבוקשת
  static bool isHeaderMatch(String text, String headerName) {
    // ניקוי הטקסטים לצורך השוואה
    final cleanText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final cleanHeader = headerName.trim().replaceAll(RegExp(r'\s+'), ' ');
    
    // השוואה מדויקת
    if (cleanText == cleanHeader) {
      return true;
    }
    
    // השוואה ללא רגישות לרווחים
    if (cleanText.replaceAll(' ', '') == cleanHeader.replaceAll(' ', '')) {
      return true;
    }
    
    // בדיקה אם הכותרת מכילה את הטקסט המבוקש
    if (cleanText.contains(cleanHeader)) {
      return true;
    }
    
    // בדיקה הפוכה - אם הטקסט המבוקש מכיל את הכותרת
    if (cleanHeader.contains(cleanText)) {
      return true;
    }
    
    return false;
  }
}