import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/live/live_program_schedule.dart';
import 'package:juying/domain/models/live_program.dart';

void main() {
  final program = LiveProgram(
    sourceId: 'source',
    sourceItemId: 'channel',
    title: '节目',
    startsAt: DateTime.utc(2026, 8, 20, 10),
    endsAt: DateTime.utc(2026, 8, 20, 11),
  );

  test('当前节目只在统一时段内返回', () {
    expect(
      LiveProgramSchedule.current([program],
          now: DateTime.utc(2026, 8, 20, 10, 30)),
      program,
    );
    expect(
      LiveProgramSchedule.current([program],
          now: DateTime.utc(2026, 8, 20, 11)),
      isNull,
    );
  });

  test('节目进度限制在有效范围内', () {
    expect(
      LiveProgramSchedule.progress(program,
          now: DateTime.utc(2026, 8, 20, 10, 30)),
      0.5,
    );
    expect(
      LiveProgramSchedule.progress(program, now: DateTime.utc(2026, 8, 20, 12)),
      1,
    );
  });
}
