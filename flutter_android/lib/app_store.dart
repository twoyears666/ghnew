import 'dart:async';

import 'package:flutter/foundation.dart';

import 'crypto.dart';
import 'github_api.dart';
import 'models.dart';
import 'persistence.dart';

/// Global store instance (mirrors SwiftUI's EnvironmentObject pattern).
final AppStore store = AppStore();

/// Central observable store (port of AppStore.swift): tracked repos, the
/// message inbox, selection, login, polling, and deep-link routing.
class AppStore extends ChangeNotifier {
  final GitHubApi api = GitHubApi.shared;

  List<TrackedRepo> repos = [];
  List<GHMessage> messages = [];
  String? selectedRepoID;
  String? selectedMessageID;
  GitHubUser? currentUser;
  bool isRefreshing = false;
  String? errorMessage;
  bool showAddRepo = false;
  bool showRepoPicker = false;
  String? pendingOwner;
  String? pendingName;

  Timer? _pollTimer;
  static const _pollInterval = Duration(minutes: 5);

  /// How many messages a repo keeps on disk (releases + actions combined).
  /// Older history is fetched on demand and never persisted.
  static const persistedPerRepo = 10;
  /// Page size used when fetching a repo's history.
  static const trackerPageSize = 10;

  /// Per-repo pagination cursor for the on-demand "load older" path.
  final Map<String, _PageCursor> _cursors = {};
  /// True while an on-demand older-page fetch is in flight.
  bool olderLoading = false;

  /// Whether the selected repo still has older history to fetch.
  bool get canLoadOlder {
    final repo = selectedRepo;
    if (repo == null || olderLoading) return false;
    final c = _cursors[repo.id];
    if (c == null) return true; // not seeded yet → assume more
    final releaseMore = repo.watchRelease && !c.releaseDone;
    final runMore = repo.watchAction && !c.runsDone;
    return releaseMore || runMore;
  }

  bool get isLoggedIn => currentUser?.login != null &&
      (api.token?.isNotEmpty ?? false);

  TrackedRepo? get selectedRepo {
    for (final r in repos) {
      if (r.id == selectedRepoID) return r;
    }
    return null;
  }

  GHMessage? get selectedMessage {
    for (final m in messages) {
      if (m.id == selectedMessageID) return m;
    }
    return null;
  }

  List<GHMessage> get messagesForSelected {
    final id = selectedRepoID;
    if (id == null) return [];
    final out = messages.where((m) => m.repoID == id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Load persisted state and begin polling.
  Future<void> init() async {
    repos = _pinnedFirst(await Storage.i.loadRepos());
    messages = (await Storage.i.loadMessages())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    currentUser = await Storage.i.loadUser();
    // Cap old data written by earlier versions to the persisted window.
    for (final r in repos) {
      await _trimPersisted(r.id);
    }
    await api.loadToken();
    if (selectedRepoID == null && repos.isNotEmpty) {
      selectedRepoID = repos.first.id;
    }
    if (isLoggedIn) {
      try {
        await _verifyLogin();
      } catch (_) {}
    }
    _startPolling();
  }

  Future<void> _verifyLogin() async {
    final user = await api.fetchUser();
    if (user?.login == null) {
      api.token = null;
      currentUser = null;
      await Storage.i.saveUser(null);
      await SecretStore.clearToken();
    } else {
      currentUser = user;
    }
    notifyListeners();
  }

  Future<void> login(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) throw ApiException(null, 'token required');
    api.token = t;
    final user = await api.fetchUser();
    if (user?.login == null) {
      throw ApiException(null, 'invalid token');
    }
    await SecretStore.storeToken(t);
    currentUser = user;
    await Storage.i.saveUser(user);
    showRepoPicker = true;
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    currentUser = null;
    await Storage.i.saveUser(null);
    await SecretStore.clearToken();
    notifyListeners();
  }

  Future<void> addRepo({
    required String owner,
    required String name,
    required bool watchRelease,
    required bool watchAction,
    bool notify = true,
  }) async {
    final o = owner.trim();
    final n = name.trim();
    if (o.isEmpty || n.isEmpty) throw ApiException(null, 'bad repo');
    final key = '${o.toLowerCase()}/${n.toLowerCase()}';
    if (repos.any((r) => r.id.toLowerCase() == key)) {
      throw ApiException(null, 'repo already tracked');
    }
    final gh = await api.validateRepo(o, n);
    final parts = gh.fullName.split('/');
    final actualName = parts.isNotEmpty ? parts.last : n;
    final tracked = TrackedRepo(
      owner: o,
      name: actualName,
      watchRelease: watchRelease,
      watchAction: watchAction,
      notify: notify,
      defaultBranch: gh.defaultBranch,
    );
    repos.add(tracked);
    await Storage.i.saveRepos(repos);
    if (selectedRepoID == null) selectedRepoID = tracked.id;
    notifyListeners();
    await refreshRepo(tracked);
  }

  Future<void> removeRepo(TrackedRepo repo) async {
    repos.removeWhere((r) => r.id == repo.id);
    await Storage.i.saveRepos(repos);
    if (selectedRepoID == repo.id) {
      selectedRepoID = repos.isNotEmpty ? repos.first.id : null;
    }
    _cursors.remove(repo.id);
    for (final m in messages.where((m) => m.repoID == repo.id).toList()) {
      await Storage.i.deleteMessage(m);
    }
    messages.removeWhere((m) => m.repoID == repo.id);
    if (selectedMessageID != null &&
        !messages.any((m) => m.id == selectedMessageID)) {
      selectedMessageID = null;
    }
    notifyListeners();
  }

  void updateRepo(TrackedRepo repo) {
    final i = repos.indexWhere((r) => r.id == repo.id);
    if (i < 0) return;
    repos[i] = repo;
    Storage.i.saveRepos(repos);
    notifyListeners();
  }

  /// Star / unstar a repo (long-press menu). A newly pinned repo joins the end
  /// of the pinned block; an unpinned one jumps to the top of the normal block.
  void togglePinned(String id) {
    final i = repos.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final r = repos.removeAt(i);
    r.pinned = !r.pinned;
    final boundary = repos.indexWhere((x) => !x.pinned);
    repos.insert(boundary < 0 ? repos.length : boundary, r);
    Storage.i.saveRepos(repos);
    notifyListeners();
  }

  /// Apply a drag-reorder: `pinnedIds` / `normalIds` are repo ids in their new
  /// order, and group membership is derived from which list they arrived in.
  void applyRepoOrder(List<String> pinnedIds, List<String> normalIds) {
    final byId = {for (final r in repos) r.id: r};
    final out = <TrackedRepo>[];
    final pinnedFlags = <bool>[];
    for (final id in pinnedIds) {
      final r = byId[id];
      if (r != null) {
        out.add(r);
        pinnedFlags.add(true);
      }
    }
    for (final id in normalIds) {
      final r = byId[id];
      if (r != null) {
        out.add(r);
        pinnedFlags.add(false);
      }
    }
    // Safety: never drop a repo (or half-apply) through a bad index mapping.
    if (out.length != repos.length) return;
    for (var i = 0; i < out.length; i++) {
      out[i].pinned = pinnedFlags[i];
    }
    repos = out;
    Storage.i.saveRepos(repos);
    notifyListeners();
  }

  /// Stable partition: pinned repos first, preserving relative order.
  static List<TrackedRepo> _pinnedFirst(List<TrackedRepo> list) =>
      [...list.where((r) => r.pinned), ...list.where((r) => !r.pinned)];

  void select(String id) {
    selectedRepoID = id;
    selectedMessageID = null;
    notifyListeners();
  }

  /// Notifies UI of direct selection-field mutations (used by nav back).
  void notifySelection() => notifyListeners();

  /// The right column inspects a message (also selects its repo).
  void selectMessage(String? id) {
    selectedMessageID = id;
    if (id != null) {
      for (final m in messages) {
        if (m.id == id) {
          selectedRepoID = m.repoID;
          break;
        }
      }
    }
    notifyListeners();
  }

  void prefillAddRepo(String owner, String name) {
    pendingOwner = owner;
    pendingName = name;
    showAddRepo = true;
    notifyListeners();
  }

  void openRepo(String owner, String name) {
    final key = '${owner.toLowerCase()}/${name.toLowerCase()}';
    for (final r in repos) {
      if (r.id.toLowerCase() == key) {
        select(r.id);
        return;
      }
    }
    prefillAddRepo(owner, name);
  }

  Future<void> openRelease(String owner, String name, String tag) async {
    openRepo(owner, name);
    await _refreshRepoNamed(owner, name);
    final key = '${owner.toLowerCase()}/${name.toLowerCase()}';
    for (final m in messages) {
      if (m.repoID.toLowerCase() == key &&
          m.kind == MessageKind.release &&
          m.releaseTag == tag) {
        selectMessage(m.id);
        return;
      }
    }
  }

  Future<void> openAction(String owner, String name, int runId) async {
    openRepo(owner, name);
    await _refreshRepoNamed(owner, name);
    final key = '${owner.toLowerCase()}/${name.toLowerCase()}';
    for (final m in messages) {
      if (m.repoID.toLowerCase() == key &&
          m.kind == MessageKind.action &&
          m.runID == runId) {
        selectMessage(m.id);
        return;
      }
    }
  }

  Future<void> _refreshRepoNamed(String owner, String name) async {
    final key = '${owner.toLowerCase()}/${name.toLowerCase()}';
    for (final r in repos) {
      if (r.id.toLowerCase() == key) {
        await refreshRepo(r);
        return;
      }
    }
  }

  Future<void> resetAll() async {
    for (final m in messages) {
      await Storage.i.deleteMessage(m);
    }
    messages = [];
    _cursors.clear();
    repos = [];
    await Storage.i.saveRepos(repos);
    selectedRepoID = null;
    selectedMessageID = null;
    pendingOwner = null;
    pendingName = null;
    await logout();
  }

  Future<void> refreshAll() async {
    if (isRefreshing) return;
    isRefreshing = true;
    notifyListeners();
    for (final repo in List.of(repos)) {
      await refreshRepo(repo);
    }
    isRefreshing = false;
    notifyListeners();
  }

  Future<void> refreshRepo(TrackedRepo repo) async {
    var updated = repo;
    int? releaseCount;
    int? runCount;
    try {
      if (repo.watchRelease) {
        final rels = await api.fetchReleases(repo.owner, repo.name,
            page: 1, perPage: trackerPageSize);
        releaseCount = rels.length;
        updated.lastSeenRelease = _processReleases(rels, repo);
      }
      if (repo.watchAction) {
        final runs = await api.fetchRuns(repo.owner, repo.name,
            page: 1, perPage: trackerPageSize);
        runCount = runs.length;
        updated.lastSeenRun = _processRuns(runs, repo);
      }
      // Seed the pagination cursor once; later refreshes must not reset it
      // (that would re-walk already loaded pages).
      if (_cursors[repo.id] == null) {
        _cursors[repo.id] = _PageCursor(
          releaseDone: !repo.watchRelease ||
              (releaseCount ?? 0) < trackerPageSize,
          runsDone: !repo.watchAction || (runCount ?? 0) < trackerPageSize,
        );
      }
      await _trimPersisted(repo.id);
      final i = repos.indexWhere((r) => r.id == repo.id);
      if (i >= 0) {
        repos[i] = updated;
        await Storage.i.saveRepos(repos);
      }
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Fetch the next page of older releases/runs for the selected repo. These
  /// messages are shown but deliberately not written to disk.
  Future<void> loadOlder() async {
    final repo = selectedRepo;
    if (repo == null || olderLoading) return;
    // Make sure page 1 is in memory so pagination continues without gaps.
    if (_cursors[repo.id] == null) {
      await refreshRepo(repo);
      if (_cursors[repo.id] == null) return;
    }
    olderLoading = true;
    notifyListeners();
    try {
      final cursor = _cursors[repo.id]!;
      if (repo.watchRelease && !cursor.releaseDone) {
        final next = cursor.releasePage + 1;
        try {
          final rels = await api.fetchReleases(repo.owner, repo.name,
              page: next, perPage: trackerPageSize);
          cursor.releasePage = next;
          if (rels.length < trackerPageSize) cursor.releaseDone = true;
          for (final rel in rels) {
            _insertTransient(_releaseMessage(rel, repo));
          }
        } catch (_) {}
      }
      if (repo.watchAction && !cursor.runsDone) {
        final next = cursor.runsPage + 1;
        try {
          final runs = await api.fetchRuns(repo.owner, repo.name,
              page: next, perPage: trackerPageSize);
          cursor.runsPage = next;
          if (runs.length < trackerPageSize) cursor.runsDone = true;
          for (final run in runs) {
            _insertTransient(_runMessage(run, repo));
          }
        } catch (_) {}
      }
    } finally {
      olderLoading = false;
      notifyListeners();
    }
  }

  /// Delete persisted files beyond the newest `persistedPerRepo` for a repo.
  Future<void> _trimPersisted(String repoID) async {
    final sorted = messages.where((m) => m.repoID == repoID).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (sorted.length <= persistedPerRepo) return;
    for (final m in sorted.skip(persistedPerRepo)) {
      await Storage.i.deleteMessage(m);
    }
  }

  int? _processReleases(List<GhRelease> releases, TrackedRepo repo) {
    var maxId = repo.lastSeenRelease;
    for (final rel in releases) {
      if (_insertMessageIfNew(_releaseMessage(rel, repo))) {
        maxId = maxId == null ? rel.id : (rel.id > maxId ? rel.id : maxId);
      }
    }
    return maxId;
  }

  int? _processRuns(List<GhRun> runs, TrackedRepo repo) {
    var maxId = repo.lastSeenRun;
    for (final run in runs) {
      if (_insertMessageIfNew(_runMessage(run, repo))) {
        maxId = maxId == null ? run.id : (run.id > maxId ? run.id : maxId);
      }
    }
    return maxId;
  }

  GHMessage _releaseMessage(GhRelease rel, TrackedRepo repo) {
    final base = 'https://github.com/${repo.owner}/${repo.name}';
    final title =
        (rel.name?.isNotEmpty ?? false) ? rel.name! : rel.tagName ?? 'Release';
    return GHMessage(
      id: 'r-${repo.owner.toLowerCase()}-${repo.name.toLowerCase()}-${rel.id}',
      repoID: repo.id,
      kind: MessageKind.release,
      createdAt: ghDate(rel.publishedAt) ?? DateTime.now(),
      releaseTitle: title,
      releaseTag: rel.tagName,
      releaseBody: rel.body,
      isPrerelease: rel.prerelease ?? false,
      releaseURL: rel.htmlUrl ?? '$base/releases',
    );
  }

  GHMessage _runMessage(GhRun run, TrackedRepo repo) {
    final base = 'https://github.com/${repo.owner}/${repo.name}';
    final start =
        ghDate(run.runStartedAt) ?? ghDate(run.createdAt) ?? DateTime.now();
    Duration? dur;
    if (run.status == 'completed') {
      final end = ghDate(run.updatedAt);
      if (end != null) {
        dur = end.difference(start);
        if (dur.isNegative) dur = Duration.zero;
      }
    }
    final actor = (run.triggeringActor?.isNotEmpty ?? false)
        ? run.triggeringActor!
        : (run.actor ?? '');
    final title = (run.displayTitle?.isNotEmpty ?? false)
        ? run.displayTitle!
        : 'Workflow run';
    return GHMessage(
      id: 'a-${repo.owner.toLowerCase()}-${repo.name.toLowerCase()}-${run.id}',
      repoID: repo.id,
      kind: MessageKind.action,
      createdAt: start,
      actionTitle: title,
      runNumber: run.runNumber,
      runID: run.id,
      commitID: run.headSha,
      actor: actor.isEmpty ? null : actor,
      branch: run.headBranch,
      runStatus: run.status,
      runConclusion: run.conclusion,
      duration: dur,
      actionsURL: run.htmlUrl ?? '$base/actions/runs/${run.id}',
    );
  }

  bool _insertMessageIfNew(GHMessage msg) {
    if (messages.any((m) => m.id == msg.id)) return false;
    messages.add(msg);
    Storage.i.saveMessage(msg);
    return true;
  }

  /// Append a message to the in-memory list only — used for older history
  /// loaded on demand, which must never touch disk.
  void _insertTransient(GHMessage msg) {
    if (messages.any((m) => m.id == msg.id)) return;
    messages.add(msg);
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      refreshAll();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Per-repo pagination cursor for the on-demand "load older" path.
class _PageCursor {
  int releasePage = 1;
  int runsPage = 1;
  bool releaseDone;
  bool runsDone;
  _PageCursor({this.releaseDone = false, this.runsDone = false});
}