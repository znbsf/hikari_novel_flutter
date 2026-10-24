/// A response could not be parsed safely. Never includes response HTML or account data.
class ParseException extends FormatException {
  final String context;
  final String reason;

  const ParseException(this.context, this.reason) : super('Invalid site response');

  static T guard<T>(String context, T Function() parse) {
    try {
      return parse();
    } on ParseException {
      rethrow;
    } on FormatException {
      throw ParseException(context, 'invalid response');
    } on RangeError {
      throw ParseException(context, 'missing field');
    } on TypeError {
      throw ParseException(context, 'missing field');
    } on StateError {
      throw ParseException(context, 'missing structure');
    }
  }

  @override
  String toString() => 'ParseException: $context ($reason)';
}
