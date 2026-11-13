import 'dart:convert';

import 'package:baocode_mobile/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('后台连接默认关闭，用户选择可以保存和读取', () {
    expect(AppSettings.fromJson({}).keepBackgroundConnection, isFalse);
    final original = AppSettings()..keepBackgroundConnection = true;
    expect(
      AppSettings.fromJson(original.toJson()).keepBackgroundConnection,
      isTrue,
    );
  });

  test('existing settings gain the default code size without losing scale', () {
    final settings = AppSettings.fromJson({
      'textScale': 0.95,
      'language': 'zh',
    });
    expect(settings.textScale, 0.95);
    expect(settings.codeFontSize, 14);
    expect(settings.language, 'zh');
  });

  test('message and code sizes persist independently', () {
    final original = AppSettings()
      ..textScale = 1.2
      ..codeFontSize = 17
      ..themeMode = ThemeMode.dark
      ..language = 'en';
    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.textScale, 1.2);
    expect(restored.codeFontSize, 17);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.language, 'en');
  });

  test('stored font sizes are bounded', () {
    final settings = AppSettings.fromJson({
      'textScale': 500,
      'codeFontSize': -10,
    });
    expect(settings.textScale, 1.4);
    expect(settings.codeFontSize, 10);
  });

  test('放到首页的对话与置顶的 Bot 按电脑保存并能读回', () {
    final settings = AppSettings()
      ..homeSessions.add(('desk', 'session'))
      ..pinnedBots.add(('desk', 'bot'));
    final back = AppSettings.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(settings.toJson())) as Map,
      ),
    );
    expect(back.homeSessions, {('desk', 'session')});
    expect(back.pinnedBots, {('desk', 'bot')});
    expect(AppSettings.fromJson({}).homeSessions, isEmpty);
    expect(AppSettings.fromJson({}).pinnedBots, isEmpty);
  });

  test('通知分三类保存；旧的总开关关闭时三类都关', () {
    final old = AppSettings.fromJson({'notifications': false});
    expect(
      [old.notifyNeedsInput, old.notifyDone, old.notifyBots],
      [false, false, false],
    );
    final settings = AppSettings()..notifyDone = false;
    final back = AppSettings.fromJson(settings.toJson());
    expect(
      [back.notifyNeedsInput, back.notifyDone, back.notifyBots],
      [true, false, true],
    );
  });

  test('自动保留改动默认关闭，开启后能保存读回', () {
    expect(AppSettings().autoKeep, isFalse);
    expect(AppSettings.fromJson(const {}).autoKeep, isFalse);
    final back = AppSettings.fromJson(
      (AppSettings()..autoKeep = true).toJson(),
    );
    expect(back.autoKeep, isTrue);
  });
}
