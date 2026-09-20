import 'package:equatable/equatable.dart';

class OpeningHour extends Equatable {
  final int dayOfWeek;
  final String? openTime;
  final String? closeTime;
  final bool isClosed;
  final String? breakStart;
  final String? breakEnd;

  const OpeningHour({
    required this.dayOfWeek,
    this.openTime,
    this.closeTime,
    this.isClosed = false,
    this.breakStart,
    this.breakEnd,
  });

  String get dayName {
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return days[dayOfWeek % 7];
  }

  String get display {
    if (isClosed) return 'Fermé';
    if (openTime == null || closeTime == null) return '—';
    final base = '$openTime - $closeTime';
    if (breakStart != null && breakEnd != null) {
      return '$base (pause $breakStart - $breakEnd)';
    }
    return base;
  }

  factory OpeningHour.fromJson(Map<String, dynamic> json) {
    return OpeningHour(
      dayOfWeek: (json['day_of_week'] as int?) ?? json['day'] as int? ?? 0,
      openTime: json['open_time'] as String?,
      closeTime: json['close_time'] as String?,
      isClosed: (json['is_closed'] as bool?) ?? false,
      breakStart: json['break_start'] as String?,
      breakEnd: json['break_end'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        dayOfWeek,
        openTime,
        closeTime,
        isClosed,
      ];
}
