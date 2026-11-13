# 官方协议同步与来源

YCode 是独立的非官方 Android 客户端，不是官方手机端的分支。官方手机端不开源；YCode 的界面参考官方 App 的截图自行设计和实现，不包含官方 App 的代码或图片素材。

## 协议

- `vendor/bao_link`、`vendor/bao_iroh` 来自 [BaoCode](https://github.com/baocode-dev/baocode) 官方提交 `4ba7d951`（1.9.4 之后）的 `packages/` 目录，Dart 与 Rust 绑定成对同步。
- 只多一个可选方法 `quota`（额度查询），声明在 `vendor/bao_link/lib/src/protocol.dart`。官方电脑端不支持时，手机端只显示「此电脑不支持额度查询」，不影响聊天、文件和 Bot；超时、断线这类真实错误照常报失败。
- `vendor/bao_link/lib/src/peer.dart` 有本地连接恢复修补：请求写失败及时返回，独立流写失败复位该流，无等待方的控制消息写失败结束连接；独立流超时包含开流等待，迟到的流不再发送请求。回前台的 `state` 探测使用电脑端已支持的独立请求流，避免排在大历史回复之后；`open`、`earlier` 与会话增量仍在控制流保持顺序。256 KiB 及以上的消息在工作 isolate 解析，控制流按原顺序应用结果。不改变 link v2 的消息格式，不自动重发请求；这些不是上述官方提交自带的改动。
- 排队消息由手机端在本地保存和发送，不需要协议扩展。

官方改了 `packages/bao_link`、`packages/bao_iroh` 或 `lib/link/` 时：先比较 `4ba7d951` 和新提交的差异，有选择地同步，保留 `quota`，再更新本文记录的提交；不要直接覆盖整个 `vendor`。

## 兼容约定

- 只用 link v2：iroh/QUIC、Ed25519、ALPN `baocode/link/2`。旧的 X25519 配对记录保留并标为「需要重新配对」，不自动信任，也不自动拨号。
- 中继以电脑公布的策略为准：direct 电脑不碰任何中继；配对时在 hello 之前只走局域网地址。
- 断线不重放写请求；增量补丁对不上基线时重新打开订阅。

## 来自 BaoCode 的文件

以下文件从 BaoCode 电脑端（官方提交 `cff287f1`）复制或改编，适配了手机的主题和交互，适用 GPL-3.0-only，版权归 BaoCode 作者。修改它们之前，先对照电脑端的同名文件。

- `lib/chat/`：`chat_models.dart`、`chat_output.dart`、`step_folds.dart`
- `lib/chat/markdown/`：`code_citation.dart`、`file_link.dart`、`finite_selection_edges.dart`、`hover_builder.dart`、`hover_scrollbar.dart`、`inline_code.dart`、`lazy_segment.dart`、`markdown_cjk.dart`、`markdown_math.dart`、`markdown_tags.dart`、`markdown_view.dart`、`mermaid_code_block.dart`、`safe_selection_indexes.dart`、`will_change_paint.dart`
- `lib/chat/widgets/`：`activity_row.dart`、`agent_step.dart`、`assistant_text.dart`、`chat_item_view.dart`、`command_step.dart`、`edge_fade_mask.dart`、`edit_step.dart`、`fade_curve.dart`、`flip_switcher.dart`、`fold_line.dart`、`live_selectable_text.dart`、`notice_row.dart`、`pixel_loader.dart`、`plan_card.dart`、`rolling_text.dart`、`shell_highlight.dart`、`shimmer_text.dart`、`step_clock.dart`、`step_header.dart`、`step_images.dart`、`strings.dart`、`terminal_text.dart`、`thinking_section.dart`、`thinking_spark.dart`、`tool_call_row.dart`、`turn_footer.dart`
- 其他：`lib/link/chat_codec.dart`、`lib/theme/material_file_icons.dart`、`lib/ui/tasks/chat_page.dart`、`lib/ui/widgets/model_icon.dart`

图标等素材的来源见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。
