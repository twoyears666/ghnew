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
        "warnings": ("警告", "Warnings"),
        "noWarnings": ("无警告", "No warnings"),
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
        "noRepos": ("未找到仓库", "No repositories found")
    ]

    static func L(_ key: String) -> String {
        guard let e = table[key] else { return key }
        return AppSettings.shared.language == .zh ? e.zh : e.en
    }
}