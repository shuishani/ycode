import '../../state/app_state.dart';

/// 单个项目的来源，用于角标。
enum ConversationSource { local, ssh, wsl, unknown }

ConversationSource projectSource(String location) {
  if (location.startsWith('ssh://')) {
    final rest = location.substring(6);
    final slash = rest.indexOf('/');
    if (slash <= 0) return ConversationSource.unknown;
    final host = rest.substring(0, slash);
    if (host == 'wsl+') return ConversationSource.unknown;
    return host.startsWith('wsl+')
        ? ConversationSource.wsl
        : ConversationSource.ssh;
  }
  if (location.isEmpty || location.contains('://')) {
    return ConversationSource.unknown;
  }
  return ConversationSource.local;
}

class ConversationProject {
  const ConversationProject(this.ref, this.sessions);
  final ProjectRef ref;
  final List<SessionRef> sessions;
  DateTime? get activity => sessions.isEmpty
      ? null
      : sessions
            .map((s) => s.session.updatedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
}

/// 首页的搜索：项目名、电脑名和对话标题都能搜到。
class ConversationFilters {
  const ConversationFilters({this.query = ''});
  final String query;
  bool get searching => query.trim().isNotEmpty;

  List<SessionRef> sessions(
    Iterable<SessionRef> input,
    String Function(String) desktopName, {
    String projectName = '',
    bool pinnedFirst = true,
  }) {
    final needle = query.trim().toLowerCase();
    final result = input
        .where(
          (ref) =>
              '$projectName ${desktopName(ref.desktopId)} ${ref.session.title}'
                  .toLowerCase()
                  .contains(needle),
        )
        .toList();
    result.sort((a, b) {
      if (pinnedFirst && a.session.pinned != b.session.pinned) {
        return a.session.pinned ? -1 : 1;
      }
      final order = b.session.updatedAt.compareTo(a.session.updatedAt);
      if (order != 0) return order;
      final desktop = a.desktopId.compareTo(b.desktopId);
      return desktop != 0 ? desktop : a.session.id.compareTo(b.session.id);
    });
    return result;
  }

  List<ConversationProject> projects(
    Iterable<ProjectRef> input,
    List<SessionRef> allSessions,
    String Function(String) desktopName,
  ) {
    final original = input.toList();
    final order = {
      for (var i = 0; i < original.length; i++)
        (original[i].desktopId, original[i].project.id): i,
    };
    final needle = query.trim().toLowerCase();
    final result = <ConversationProject>[];
    for (final ref in original) {
      final matching = sessions(
        allSessions.where(
          (s) =>
              s.desktopId == ref.desktopId &&
              s.session.project == ref.project.id,
        ),
        desktopName,
        projectName: ref.project.name,
      );
      if (matching.isEmpty &&
          !'${ref.project.name} ${desktopName(ref.desktopId)}'
              .toLowerCase()
              .contains(needle)) {
        continue;
      }
      result.add(ConversationProject(ref, matching));
    }
    result.sort((a, b) {
      if ((a.ref.project.pinned == true) != (b.ref.project.pinned == true)) {
        return a.ref.project.pinned == true ? -1 : 1;
      }
      final at = a.activity, bt = b.activity;
      if (at != null && bt == null) return -1;
      if (at == null && bt != null) return 1;
      if (at != null && bt != null) {
        final time = bt.compareTo(at);
        if (time != 0) return time;
      }
      return order[(a.ref.desktopId, a.ref.project.id)]!.compareTo(
        order[(b.ref.desktopId, b.ref.project.id)]!,
      );
    });
    return result;
  }
}
