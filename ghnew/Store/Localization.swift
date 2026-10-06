import Foundation

/// Lightweight in-app localization. `L(key)` returns the string for the active
/// `AppSettings.shared.language`. Unknown keys fall back to English.
enum Localization {
    private static let table: [String: (zh: String, en: String)] = [
        // Login / account
        "login": ("登录", "Log in"),
        "loggedIn": ("已登录", "Logged in"),
        "logOut": ("退出登录", "Sign out"),
        "signOutTitle": ("退出登录", "Sign out"),
        "signOutPrompt": ("要退出当前账号吗？", "Sign out of this account?"),
        "signOutConfirm": ("将清除本机保存的登录与仓库数据。", "Logged-in account and tracked data will be removed."),
        "confirm": ("确认", "Confirm"),
        "cancel": ("取消", "Cancel"),
        "createToken": ("在 GitHub 创建令牌后粘贴", "Create a token on GitHub, then paste it"),
        "tokenPrompt": ("用 GitHub 个人访问令牌登录，令牌仅保存在本设备并加密存储。", "Log in with a GitHub PAT. It is stored on this device, encrypted."),
        "loginToGetArtifacts": ("登录以获取产物", "Log in to get artifacts"),
        "loginToDownload": ("登录以获取产物", "Log in to get artifacts"),
        "settings": ("设置", "Settings"),

        // Repos
        "addRepo": ("添加仓库", "Add repository"),
        "addRepoUrl": ("添加仓库", "Add repository"),
        "trackedRepos": ("跟踪的仓库", "Tracked repositories"),
        "ownerRepo": ("owner / 仓库", "owner / repository"),
        "ownerRepoPlaceholder": ("owner / 仓库", "owner / repository"),
        "alreadyAdded": ("该仓库已在跟踪列表中", "This repository is already being tracked."),
        "replySelectRepos": ("选择要添加的仓库", "Select repositories to add"),
        "addSelected": ("添加所选", "Add selected"),
        "skip": ("跳过", "Skip"),
        "repoSettings": ("仓库设置", "Repository settings"),
        "trackReleases": ("跟踪 Releases", "Track releases"),
        "trackActions": ("跟踪 Actions", "Track actions"),
        "sendNotifications": ("发送通知", "Send notifications"),
        "remove": ("移除", "Remove"),
        "howToAdd": ("输入 owner / 仓库 名称添加（如 twoyears666/ghnew）", "Enter owner / repository (e.g. twoyears666/ghnew)"),

        // Menu / navigation
        "refresh": ("刷新", "Refresh"),
        "messages": ("消息", "Messages"),
        "noMessages": ("还没有 Release 或 Action。\n下拉刷新或点刷新。", "No releases or actions yet.\nPull to refresh or press Refresh."),
        "open": ("打开", "open"),
        "openInBrowser": ("在浏览器打开", "Open in browser"),
        "isIssuePlease": ("报告问题", "Report an issue"),

        // Settings panel
        "appearance": ("外观", "Appearance"),
        "darkMode": ("深色模式", "Dark mode"),
        "language": ("语言", "Language"),
        "support": ("支持", "Support"),
        "openIssue": ("提交 Issue", "Open an issue"),
        "ghnewRepo": ("ghnew 仓库", "ghnew repository"),
        "dangerZone": ("危险区", "Danger zone"),
        "reset": ("重置", "Reset"),
        "resetPrompt": ("重置将清除所有仓库、消息与登录信息，且不可恢复，确定吗？", "Reset clears all repos, messages and login. This cannot be undone."),
        "resetDone": ("已重置", "Reset done"),

        // Right column
        "releases": ("Releases", "Releases"),
        "artifacts": ("产物", "Artifacts"),
        "assets": ("资源", "Assets"),
        "noArtifacts": ("无产物", "No artifacts"),
        "annotations": ("注解", "Annotations"),
        "noAnnotations": ("无注解", "No annotations"),
        "progress": ("进度", "Progress"),
        "duration": ("耗时", "Duration"),
        "download": ("下载", "Download"),
        "downloading": ("下载中…", "Downloading…"),
        "downloaded": ("已下载", "Downloaded"),
        "downloadFailed": ("下载失败", "Download failed"),
        "queued": ("排队中", "Queued"),
        "inProgress": ("运行中", "In progress"),
        "completed": ("已完成", "Completed"),
        "changelog": ("更新日志", "Changelog"),
        "noBody": ("无说明", "No description"),
        "selectReleaseOrRun": ("点击一条 Release 或 Run 查看详情", "Select a release or run to inspect it"),
        "done": ("完成", "Done"),
        "save": ("保存", "Save"),
        "repository": ("仓库", "Repository"),
        "addRepos": ("添加仓库", "Add repositories"),
        "noRepos": ("未找到仓库", "No repositories found"),

        // Acceleration
        "accelerate": ("加速", "Accelerate"),
        "relayTab": ("中转（推荐）", "Relay (recommended)"),
        "concTab": ("并发（容易限流）", "Concurrency (rate-limit)"),
        "masterSwitch": ("总开关", "Master switch"),
        "relayNodes": ("节点", "Nodes"),
        "testLatency": ("测试节点延迟", "Test node latency"),
        "latencyFast": ("快速", "Fast"),
        "latencyMedium": ("中等", "Medium"),
        "latencySlow": ("慢速", "Slow"),
        "latencyFail": ("失败", "Failed"),
        "includeArtifacts": ("同时加速 Actions 产物", "Also accelerate actions artifacts"),
        "artifactRiskWarn": ("产物下载需要鉴权，走第三方中转可能失败，并会向节点暴露你的令牌，请谨慎开启。", "Artifacts require auth; a third-party relay may fail and exposes your token to the node. Enable with caution."),
        "concLevel": ("并发数", "Concurrency"),
        "relayHint": ("开启后，公开的 Release 资源将通过所选镜像节点下载。", "When on, public release assets download through the selected mirror."),
        "concHint": ("将单个文件切成多段并行下载以提速；连接数过多容易触发限流，探测到不支持时自动回退单线程。", "Splits a single file into parallel chunks for speed; too many connections may hit rate limits and it falls back to single-thread when unsupported."),

        // Downloads 下载
        "downloadSection": ("下载", "Downloads"),
        "autoUnzip": ("自动解压 Actions 产物", "Auto-unzip actions artifacts"),
        "autoUnzipHint": ("产物均为 zip 压缩包，下载完成后自动解压到同名文件夹（原 zip 保留）。", "Artifacts are zip archives; unpack them into a like-named folder after download (the zip is kept).")
    ]

    static func L(_ key: String) -> String {
        guard let e = table[key] else { return key }
        return AppSettings.shared.language == .zh ? e.zh : e.en
    }
}