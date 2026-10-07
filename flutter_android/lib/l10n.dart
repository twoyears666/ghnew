import 'settings.dart';

/// Lightweight in-app localization. `L(key)` returns the active (zh/en) string.
class L {
  static const _table = <String, (String, String)>{
    // Login / account
    'login': ('登录', 'Log in'),
    'logOut': ('退出登录', 'Sign out'),
    'signOutTitle': ('退出登录', 'Sign out'),
    'signOutConfirm': ('将清除本机保存的登录与仓库数据。',
        'Logged-in account and tracked data will be removed.'),
    'cancel': ('取消', 'Cancel'),
    'loginToGetArtifacts': ('登录以获取产物', 'Log in to get artifacts'),
    'settings': ('设置', 'Settings'),
    'tokenPrompt': ('用 GitHub 个人访问令牌登录，令牌仅保存在本设备并加密存储。',
        'Log in with a GitHub PAT. It is stored on this device, encrypted.'),
    'createToken': ('在 GitHub 创建令牌', 'Create token on GitHub'),
    'tokenLabel': ('令牌', 'Token'),
    'tokenPlaceholder': ('ghp_…', 'ghp_…'),

    // Repos
    'addRepo': ('添加仓库', 'Add repository'),
    'ownerRepoPlaceholder': ('owner / 仓库', 'owner / repository'),
    'alreadyAdded': ('该仓库已在跟踪列表中', 'This repository is already being tracked.'),
    'addRepos': ('添加仓库', 'Add repositories'),
    'addSelected': ('添加所选', 'Add selected'),
    'skip': ('跳过', 'Skip'),
    'repoSettings': ('仓库设置', 'Repository settings'),
    'trackReleases': ('跟踪 Releases', 'Track releases'),
    'trackActions': ('跟踪 Actions', 'Track actions'),
    'sendNotifications': ('发送通知', 'Send notifications'),
    'remove': ('移除', 'Remove'),
    'pinnedRepos': ('置顶仓库', 'Pinned repositories'),
    'repoList': ('仓库列表', 'Repositories'),
    'pinRepo': ('星标置顶', 'Pin to top'),
    'unpinRepo': ('取消置顶', 'Unpin'),
    'howToAdd': ('输入 owner / 仓库 名称添加（如 twoyears666/ghnew）',
        'Enter owner / repository (e.g. twoyears666/ghnew)'),
    'repository': ('仓库', 'Repository'),
    'noRepos': ('未找到仓库', 'No repositories found'),

    // Menu / navigation
    'refresh': ('刷新', 'Refresh'),
    'messages': ('消息', 'Messages'),
    'noMessages': ('还没有 Release 或 Action。\n点刷新。',
        'No releases or actions yet.\nPress Refresh.'),
    'open': ('打开', 'open'),

    // Settings panel
    'appearance': ('外观', 'Appearance'),
    'darkMode': ('深色模式', 'Dark mode'),
    'language': ('语言', 'Language'),
    'support': ('支持', 'Support'),
    'openIssue': ('提交 Issue', 'Open an issue'),
    'ghnewRepo': ('ghnew 仓库', 'ghnew repository'),
    'dangerZone': ('危险区', 'Danger zone'),
    'reset': ('重置', 'Reset'),
    'resetPrompt': ('重置将清除所有仓库、消息与登录信息，且不可恢复，确定吗？',
        'Reset clears all repos, messages and login. This cannot be undone.'),
    'done': ('完成', 'Done'),
    'save': ('保存', 'Save'),

    // Right column
    'artifacts': ('产物', 'Artifacts'),
    'assets': ('资源', 'Assets'),
    'noArtifacts': ('无产物', 'No artifacts'),
    'warnings': ('警告', 'Warnings'),
    'noWarnings': ('无警告', 'No warnings'),
    'progress': ('进度', 'Progress'),
    'download': ('下载', 'Download'),
    'downloaded': ('已下载', 'Downloaded'),
    'downloadFailed': ('下载失败', 'Download failed'),
    'changelog': ('更新日志', 'Changelog'),
    'noBody': ('无说明', 'No description'),
    'selectReleaseOrRun': ('点击一条 Release 或 Run 查看详情', 'Select a release or run to inspect it'),

    // Acceleration
    'accelerate': ('加速', 'Accelerate'),
    'relayTab': ('中转（推荐）', 'Relay (recommended)'),
    'concTab': ('并发（容易限流）', 'Concurrency (rate-limit)'),
    'masterSwitch': ('总开关', 'Master switch'),
    'relayNodes': ('节点', 'Nodes'),
    'testLatency': ('测试节点延迟', 'Test node latency'),
    'latencyFast': ('快速', 'Fast'),
    'latencyMedium': ('中等', 'Medium'),
    'latencySlow': ('慢速', 'Slow'),
    'latencyFail': ('失败', 'Failed'),
    'includeArtifacts': ('同时加速 Actions 产物', 'Also accelerate actions artifacts'),
    'artifactRiskWarn': ('产物下载需要鉴权，走第三方中转可能失败，并会向节点暴露你的令牌，请谨慎开启。',
        'Artifacts require auth; a third-party relay may fail and exposes your token to the node. Enable with caution.'),
    'concLevel': ('并发数', 'Concurrency'),
    'relayHint': ('开启后，公开的 Release 资源将通过所选镜像节点下载。',
        'When on, public release assets download through the selected mirror.'),
    'concHint': ('将单个文件切成多段并行下载以提速。为降低限流风险，连接数会按服务器反馈自适应：以较少的连接起步并逐步增加，遇到 429/403 限流时自动退避重试并降低并发，稳定后再缓慢恢复；探测到不支持分块时回退单线程。',
        'Splits a single file into parallel chunks for speed. To avoid rate limits, concurrency adapts to server feedback: it starts small and ramps up, backs off and lowers parallelism on 429/403, then recovers slowly once stable; it falls back to single-thread when ranges are unsupported.'),

    // Downloads
    'downloadSection': ('下载', 'Downloads'),
    'autoUnzip': ('自动解压 Actions 产物', 'Auto-unzip actions artifacts'),
    'autoUnzipHint': ('产物均为 zip 压缩包，下载完成后自动解压到同名文件夹（原 zip 保留）。',
        'Artifacts are zip archives; unpack them into a like-named folder after download (the zip is kept).'),
    'unzipDoneTitle': ('解压完成', 'Unpacked'),
    'unzipFolderMessage': ('该产物包含多个文件，已解压到同名文件夹。是否打开文件夹查看？',
        'This artifact holds several files and was unpacked into a folder. Open the folder to view it?'),
    'openFolder': ('打开文件夹', 'Open folder'),
  };

  static String str(String key) {
    final entry = _table[key];
    if (entry == null) return key;
    return SettingsStore.i.isZh ? entry.$1 : entry.$2;
  }
}