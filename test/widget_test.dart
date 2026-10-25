import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/models/channel.dart';
import 'package:jio_tv_plus_flutter/models/program.dart';

void main() {
  test('Channel and Program model serialization and progress calculation', () {
    final now = DateTime.now();
    final program = Program(
      programId: 'prog_104_01',
      channelId: '104',
      title: 'Dangal',
      episode: 'National Debate',
      startTime: now.subtract(const Duration(minutes: 30)),
      endTime: now.add(const Duration(minutes: 30)),
      hasCatchup: true,
    );

    expect(program.isLive, isTrue);
    expect(program.progressFraction, closeTo(0.5, 0.05));
    expect(program.duration, const Duration(hours: 1));

    final channel = Channel(
      channelId: '104',
      channelNo: 104,
      channelName: 'Aaj Tak HD',
      logoUrl: 'https://example.com/logo.png',
      streamUrl: 'https://example.com/stream.m3u8',
      category: 'News',
      language: 'Hindi',
      isHd: true,
      currentProgram: program,
    );

    expect(channel.channelNo, 104);
    expect(channel.isHd, isTrue);
    expect(channel.currentProgram?.title, 'Dangal');
  });
}
