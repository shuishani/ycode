import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import 'bot_notice_tracker.dart';

/// 手机自己对电脑的提醒：一轮做完或卡在等用户、Bot 有新的动态。通知由
/// 插件发；被拒绝或没有插件（无宿主的测试）都不影响会话。
///
/// 只看「该不该提醒」和「发什么」；什么时候算状态变了由 AppState 判断后
/// 调这里，通知文案的双语也由调用方给，免得这一层再懂界面语言。
class DesktopNotifications {
  DesktopNotifications({
    required this.channel,
    required this.settings,
    required this.tr,
  });

  final MethodChannel channel;
  final AppSettings Function() settings;

  /// 会话和设置页用的同一套双语。
  final String Function(String zh, String en) tr;

  /// 同一进程里每条 Bot 通知最多提醒一次。
  final _botNotices = BotNoticeTracker();

  /// 对话从 [before] 变成 [after] 该不该提醒：`true` 是等你处理，`false` 是
  /// 一轮做完，`null` 不提醒。电脑合并推送或手机断线时可能看不到「运行中」，
  /// 所以新变成未读也算做完。第一次见到的对话不提醒。
  static bool? turnNotice(SessionSummary? before, SessionSummary after) {
    if (before == null) return null;
    if (after.status == LinkSessionStatus.needsInput) {
      return before.status == LinkSessionStatus.needsInput ? null : true;
    }
    if (after.status != LinkSessionStatus.idle) return null;
    return before.status == LinkSessionStatus.running ||
            (after.unread && !before.unread)
        ? false
        : null;
  }

  /// 一条对话一轮做完或卡在等用户：发一条通知，除非不应打扰。
  Future<void> notifyTurn({
    required String desktopId,
    required String sessionId,
    required String sessionTitle,
    required bool needsInput,
    required bool foreground,
    required bool demo,
    required String desktopName,
  }) async {
    final settings = this.settings();
    if (demo ||
        foreground ||
        !(needsInput ? settings.notifyNeedsInput : settings.notifyDone)) {
      return;
    }
    final title = sessionTitle.trim();
    await _send(
      id: (desktopId, sessionId).hashCode & 0x7fffffff,
      title: title.isEmpty ? desktopName : title,
      body: [
        if (title.isNotEmpty) desktopName,
        needsInput
            ? tr('需要你处理', 'Needs your input')
            : tr('本轮已完成', 'Turn completed'),
      ].join(' · '),
    );
  }

  /// [desktopId] 上的 [bot] 有新动态：每条只提醒一次。
  Future<void> notifyBot(
    String desktopId,
    LinkBot bot, {
    required bool foreground,
    required bool demo,
  }) async {
    // 水位照推：关着通知或在前台时不发，但看过的算看过，重新打开不补发旧的。
    final quiet = demo || foreground || !settings().notifyBots;
    for (final notice in _botNotices.accept(desktopId, bot)) {
      if (quiet) continue;
      await _send(
        id: (desktopId, bot.id, notice.id).hashCode & 0x7fffffff,
        title: bot.name,
        body: switch (notice.kind) {
          'waiting' => tr('有智能体在等你处理', 'An agent is waiting for you'),
          'failed' => tr('有智能体出错了', 'An agent hit an error'),
          'done' => tr('有智能体已完成工作', 'An agent finished its work'),
          'running' => tr('有智能体已运行较长时间', 'An agent has run for a while'),
          _ => tr('有新的智能体动态', 'New agent activity'),
        },
      );
    }
  }

  Future<void> _send({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await channel.invokeMethod<void>('notify', {
        'id': id,
        'title': title,
        'body': body,
      });
    } on PlatformException {
      /* 通知被拒绝不影响会话。 */
    } on MissingPluginException {
      /* 无宿主的测试环境没有该插件。 */
    }
  }

  void forgetDesktop(String desktopId) => _botNotices.forgetDesktop(desktopId);
}
