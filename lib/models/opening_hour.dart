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
    final i = dayOfWeek % 7;
    return days[i < 0 ? i + 7 : i];
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
    int day = 0;
    final rawDay = json['day_of_week'] ?? json['day'];
    if (rawDay is num) {
      day = rawDay.toInt();
    } else if (rawDay != null) {
      day = int.tryParse(rawDay.toString()) ?? 0;
    }
    bool closed = false;
    final rawClosed = json['is_closed'];
    if (rawClosed is bool) {
      closed = rawClosed;
    } else if (rawClosed is num) {
      closed = rawClosed != 0;
    }

    return OpeningHour(
      dayOfWeek: day,
      openTime: json['open_time']?.toString(),
      closeTime: json['close_time']?.toString(),
      isClosed: closed,
      breakStart: json['break_start']?.toString(),
      breakEnd: json['break_end']?.toString(),
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
