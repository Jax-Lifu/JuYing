import '../../domain/models/live_program.dart';

abstract final class LiveProgramSchedule {
  static LiveProgram? current(
    Iterable<LiveProgram> programs, {
    required DateTime now,
  }) =>
      programs.where((program) {
        return !now.isBefore(program.startsAt) && now.isBefore(program.endsAt);
      }).firstOrNull;

  static double progress(LiveProgram program, {required DateTime now}) {
    final total = program.endsAt.difference(program.startsAt).inMilliseconds;
    if (total <= 0) return 0;
    final elapsed = now.difference(program.startsAt).inMilliseconds;
    return (elapsed / total).clamp(0, 1);
  }
}
