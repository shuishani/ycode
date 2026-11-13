# Changelog

## 0.2.0

- New: a "Focus" option under Layout opens straight into your last conversation, with projects and conversations in a side panel, grouped by project; tap one to switch. "List" stays the default.
- New (experimental): Settings → Notifications → "Keep desktop connection in background" keeps task notifications coming with the app in the background. It shows a persistent notification, uses more battery, and some phones may still stop it.
- Improved: the home list drops the filter and keeps just search; the create menu keeps just New conversation and Add bot.
- Improved: Agent mode uses an infinity icon.
- Improved: coming back to the app no longer re-syncs the whole conversation; switching networks checks the connection right away.
- Improved: long conversations and ones with many pictures load more smoothly.
- Improved: a tool's screenshot shows once; open it to swipe through the others.
- Improved: Markdown file previews show the project's pictures inline; tap one to view it full screen.
- Fixed: no "finished" notification when a task finished quickly.
- Fixed: syncing a long conversation could mistake the connection for lost and reload over and over.
- Fixed: a message that failed to send took a long time to say so.
- Fixed: a plan card could say the file is missing; a sync timeout showed the raw error.


## 0.1.1

Context usage and undoing file changes need BaoCode desktop 1.9.3 or later; with an older desktop they don't appear and everything else works as before.

- New: a context usage ring in the composer, orange above 80%; tap it to see what each part takes and how much is left before auto-compact. With BaoCode desktop 1.9.4 or later it updates as the conversation goes; with 1.9.3, when you open the conversation.
- New: when you edit an earlier message and send it again, YCode can undo the files the agent changed after it — asking, undoing or keeping as the desktop's "Edited Messages" setting says (Claude Code and BaoCode Agent).
- New: an arrow on a project's row unfolds its conversations right on the home list, without opening the project.
- Improved: picking a project in the filter closes the panel and lists that project's conversations directly; new conversations then start in it.
- Improved: checking for updates reads a small file attached to the release first, so it no longer fails when many people share one network and GitHub's hourly limit runs out.
- Fixed: file links written as `/D:/path` by a model on a Windows desktop now open.

## 0.1.0

The first open-source release of YCode, an unofficial Android client for the BaoCode desktop app.

- Pair with your computer by QR code, pasted link or LAN discovery, end-to-end encrypted over link v2.
- Conversations, Bots, Files and Settings tabs; streaming messages, edit and resend, queued sends, images and @ files, / commands.
- Checks for updates on launch and downloads and installs them in the app.
