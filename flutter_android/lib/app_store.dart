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
    repos = await Storage.i.loadRepos();
    messages = (await Storage.i.loadMessages())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    currentUser = await Storage.i.loadUser();
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
    try {
      if (repo.watchRelease) {
        final rels = await api.fetchReleases(repo.owner, repo.name);
        updated.lastSeenRelease = _processReleases(rels, repo);
      }
      if (repo.watchAction) {
        final runs = await api.fetchRuns(repo.owner, repo.name);
        updated.lastSeenRun = _processRuns(runs, repo);
      }
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

  int? _processReleases(List<GhRelease> releases, TrackedRepo repo) {
    var maxId = repo.lastSeenRelease;
    final base = 'https://github.com/${repo.owner}/${repo.name}';
    for (final rel in releases) {
      final msgId =
          'r-${repo.owner.toLowerCase()}-${repo.name.toLowerCase()}-${rel.id}';
      final title = (rel.name?.isNotEmpty ?? false) ? rel.name! : rel.tagName ?? 'Release';
      final msg = GHMessage(
        id: msgId,
        repoID: repo.id,
        kind: MessageKind.release,
        createdAt: ghDate(rel.publishedAt) ?? DateTime.now(),
        releaseTitle: title,
        releaseTag: rel.tagName,
        releaseBody: rel.body,
        isPrerelease: rel.prerelease ?? false,
        releaseURL: rel.htmlUrl ?? '$base/releases',
      );
      if (_insertMessageIfNew(msg)) {
        maxId = maxId == null ? rel.id : (rel.id > maxId ? rel.id : maxId);
      }
    }
    return maxId;
  }

  int? _processRuns(List<GhRun> runs, TrackedRepo repo) {
    var maxId = repo.lastSeenRun;
    final base = 'https://github.com/${repo.owner}/${repo.name}';
    for (final run in runs) {
      final msgId =
          'a-${repo.owner.toLowerCase()}-${repo.name.toLowerCase()}-${run.id}';
      final start = ghDate(run.runStartedAt) ?? ghDate(run.createdAt) ?? DateTime.now();
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
      final msg = GHMessage(
        id: msgId,
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
      if (_insertMessageIfNew(msg)) {
        maxId = maxId == null ? run.id : (run.id > maxId ? run.id : maxId);
      }
    }
    return maxId;
  }

  bool _insertMessageIfNew(GHMessage msg) {
    if (messages.any((m) => m.id == msg.id)) return false;
    messages.add(msg);
    Storage.i.saveMessage(msg);
    return true;
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