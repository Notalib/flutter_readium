import '../index.dart';

const dateTimeLocal = DateTimeLocal();

class DateTimeLocal implements JsonConverter<DateTime?, String?> {
  const DateTimeLocal();

  @override
  DateTime? fromJson(Object? x) {
    if (x is String) {
      x = DateTime.tryParse(x);
    }

    if (x is DateTime) {
      return x.toLocal();
    }

    return null;
  }

  @override
  String? toJson(final DateTime? x) => x?.toUtc().toIso8601String();
}
