import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/desktop_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _s(LinkSessionStatus status, {bool unread = false}) =>
    SessionSummary(
      id: 's',
      project: 'p',
      title: '对话',
      updatedAt: DateTime(2026),
      status: status,
      unread: unread,
    );

void main() {
  const running = LinkSessionStatus.running;
  const idle = LinkSessionStatus.idle;
  const needsInput = LinkSessionStatus.needsInput;
  bool? notice(SessionSummary? before, SessionSummary after) =>
      DesktopNotifications.turnNotice(before, after);

  test('第一次见到的对话不提醒', () {
    expect(notice(null, _s(needsInput)), isNull);
    expect(notice(null, _s(idle, unread: true)), isNull);
  });

  test('运行中变空闲算做完，变成等你处理算需要处理', () {
    expect(notice(_s(running), _s(idle)), isFalse);
    expect(notice(_s(running), _s(idle, unread: true)), isFalse);
    expect(notice(_s(running), _s(needsInput)), isTrue);
    expect(notice(_s(idle), _s(needsInput)), isTrue);
  });

  test('没看到运行中，但新变成未读，也算做完', () {
    expect(notice(_s(idle), _s(idle, unread: true)), isFalse);
    expect(notice(_s(needsInput), _s(idle, unread: true)), isFalse);
  });

  test('没有新变化不重复提醒', () {
    expect(notice(_s(needsInput), _s(needsInput)), isNull);
    expect(notice(_s(idle, unread: true), _s(idle, unread: true)), isNull);
    expect(notice(_s(idle), _s(idle)), isNull);
    expect(notice(_s(idle), _s(running)), isNull);
    expect(notice(_s(idle, unread: true), _s(idle)), isNull, reason: '看过了');
  });
}
