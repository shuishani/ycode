import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/conversations/conversation_filters.dart';
import 'package:flutter_test/flutter_test.dart';

SessionRef task(
  String desktop,
  String id,
  String project, {
  LinkSessionStatus status = LinkSessionStatus.idle,
  bool pinned = false,
  int day = 1,
}) => SessionRef(
  desktop,
  SessionSummary(
    id: id,
    project: project,
    title: id,
    updatedAt: DateTime(2026, 11, day),
    status: status,
    pinned: pinned,
  ),
);

void main() {
  test('来源使用含用户名端口的原始标识而不是根路径', () {
    expect(projectSource(r'C:\Work\mobile'), ConversationSource.local);
    expect(projectSource('/home/dev/mobile'), ConversationSource.local);
    expect(
      projectSource('ssh://user@host:2222/home/dev/mobile'),
      ConversationSource.ssh,
    );
    expect(
      projectSource('ssh://wsl+Ubuntu/home/dev/mobile'),
      ConversationSource.wsl,
    );
    expect(projectSource('ssh://devbox/'), ConversationSource.ssh);
    expect(projectSource('ssh://wsl+Ubuntu/'), ConversationSource.wsl);
    expect(projectSource('ssh:///missing'), ConversationSource.unknown);
    expect(projectSource('future://host/project'), ConversationSource.unknown);
  });
  test('搜索匹配项目名、电脑名和对话标题，项目置顶优先', () {
    const projects = [
      ProjectRef('a', ProjectInfo(id: '/p', name: 'mobile', path: '/p')),
      ProjectRef('a', ProjectInfo(id: '/q', name: 'server', path: '/q')),
      ProjectRef(
        'a',
        ProjectInfo(id: '/r', name: 'mobile old', path: '/r', pinned: true),
      ),
    ];
    final sessions = [
      task('a', '修复登录', '/p', day: 3),
      task('a', 'mobile 接口', '/q'),
      task('a', '旧版', '/r'),
    ];
    final byProject = const ConversationFilters(query: 'Mobile')
        .projects(projects, sessions, (id) => id);
    expect(byProject.map((p) => p.ref.project.id), ['/r', '/p', '/q']);
    expect(byProject.last.sessions.map((s) => s.session.id), ['mobile 接口']);
    final byDesktop = const ConversationFilters(query: '我的电脑')
        .projects(projects, sessions, (_) => '我的电脑');
    expect(byDesktop, hasLength(3));
  });
  test('不搜索时列出没有对话的项目，搜不到时不显示', () {
    const projects = [
      ProjectRef('b', ProjectInfo(id: '/p', name: 'mobile', path: '/p')),
    ];
    expect(
      const ConversationFilters().projects(projects, [], (id) => id),
      hasLength(1),
    );
    expect(
      const ConversationFilters(query: '不存在')
          .projects(projects, [], (id) => id),
      isEmpty,
    );
  });
}
