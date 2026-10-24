import 'package:logger/logger.dart';

class Log {
  static final Logger _logger = Logger(printer: PrefixPrinter(PrettyPrinter(methodCount: 3, dateTimeFormat: DateTimeFormat.dateAndTime)));

  static void d(dynamic message) {
    _logger.d(message);
  }

  static void i(dynamic message) {
    _logger.i(message);
  }

  static void e(dynamic message) {
    _logger.e(message);
  }
}
