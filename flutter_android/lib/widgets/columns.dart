import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_store.dart';
import '../download_manager.dart';
import '../github_api.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'acceleration_view.dart';
import 'components.dart';
import 'markdown_view.dart';
import 'sheets.dart';

/// ============================== Left column ==============================
/// The two sections of the repo list. Pinned repos sit above the boundary,
/// plain repos below it; dragging a row across the "仓库列表" header re-parents
/// it (see [_LeftColumnState._onReorder]).
enum _RepoGroup { pinned, list }

/// A flattened list row: either a group header or a repo. Headers are rendered
/// but are not draggable; they only mark the pinned/list boundary.
class _Entry {
  const _Entry.header(this.group) : repo = null;
  const _Entry.repo(this.group, this.repo);
  final _RepoGroup group;
  final TrackedRepo? repo;
  bool get isHeader => repo == null;
  Key get key => ValueKey(isHeader ? 'h-${group.name}' : 'r-${repo!.id}');
}

class LeftColumn extends StatefulWidget {
  const LeftColumn({super.key});

  @override
  State<LeftColumn> createState() => _LeftColumnState();
}

class _LeftColumnState extends State<LeftColumn> {
  bool _pinnedCollapsed = false;
  bool _listCollapsed = false;

  /// Index the current drag started at, used to tell a real reorder (which
  /// lands elsewhere) apart from a stationary long press (release opens the
  /// row menu). `onReorderEnd` fires before `onReorder`, so we decide here.
  int? _dragStartIndex;

  List<_Entry> get _entries {
    final out = <_Entry>[_Entry.header(_RepoGroup.pinned)];
    if (!_pinnedCollapsed) {
      out.addAll(store.repos
          .where((r) => r.pinned)
          .map((r) => _Entry.repo(_RepoGroup.pinned, r)));
    }
    out.add(const _Entry.header(_RepoGroup.list));
    if (!_listCollapsed) {
      out.addAll(store.repos
          .where((r) => !r.pinned)
          .map((r) => _Entry.repo(_RepoGroup.list, r)));
    }
    return out;
  }

  void _onReorder(int oldIndex, int newIndex) {
    final items = List<_Entry>.of(_entries);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final boundary =
        items.indexWhere((e) => e.isHeader && e.group == _RepoGroup.list);
    if (boundary < 0) return;
    final pinned = <String>[];
    final normal = <String>[];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      if (e.isHeader) continue;
      (i < boundary ? pinned : normal).add(e.repo!.id);
    }
    // Re-attach rows hidden by a collapsed header so nothing is dropped.
    if (_pinnedCollapsed) {
      pinned.insertAll(0, store.repos.where((r) => r.pinned).map((r) => r.id));
    }
    if (_listCollapsed) {
      normal.insertAll(
          0, store.repos.where((r) => !r.pinned).map((r) => r.id));
    }
    store.applyRepoOrder(pinned, normal);
  }

  void _onReorderEnd(int index) {
    final start = _dragStartIndex;
    _dragStartIndex = null;
    if (start == null) return;
    // Dropped back where it started => treat the gesture as "long press" and
    // open that row's menu instead of reordering.
    if (index != start && index != start + 1) return;
    final items = _entries;
    if (start < 0 || start >= items.length) return;
    final repo = items[start].repo;
    if (repo == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRepoMenu(context, repo);
    });
  }

  void _toggle(_RepoGroup group) {
    setState(() {
      if (group == _RepoGroup.pinned) {
        _pinnedCollapsed = !_pinnedCollapsed;
      } else {
        _listCollapsed = !_listCollapsed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: T.column,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final entries = _entries;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Text('ghnew',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: T.text)),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.all(6),
                  itemCount: entries.length,
                  onReorder: _onReorder,
                  onReorderStart: (i) => _dragStartIndex = i,
                  onReorderEnd: _onReorderEnd,
                  footer: _AddRepoRow(onTap: () => showAddRepo(context)),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    if (e.isHeader) {
                      return _RepoGroupHeader(
                        key: e.key,
                        group: e.group,
                        collapsed: e.group == _RepoGroup.pinned
                            ? _pinnedCollapsed
                            : _listCollapsed,
                        onTap: () => _toggle(e.group),
                      );
                    }
                    return ReorderableDelayedDragStartListener(
                      key: e.key,
                      index: i,
                      child: _RepoRow(
                          repo: e.repo!,
                          selected: store.selectedRepoID == e.repo!.id),
                    );
                  },
                ),
              ),
              Divider(height: 1, color: T.border),
              _LoginFooter(
                onSettings: () => showSettings(context),
                onLogin: () => showLogin(context),
                onAccel: () => showAcceleration(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RepoGroupHeader extends StatelessWidget {
  const _RepoGroupHeader(
      {super.key,
      required this.group,
      required this.collapsed,
      required this.onTap});
  final _RepoGroup group;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
        child: Row(
          children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 14, color: T.textMuted),
            const SizedBox(width: 4),
            Text(
              L.str(group == _RepoGroup.pinned ? 'pinnedRepos' : 'repoList'),
              style: TextStyle(fontSize: 11, color: T.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo, required this.selected});
  final TrackedRepo repo;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => store.select(repo.id),
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? T.rowSelected : T.rowNormal,
          borderRadius: BorderRadius.circular(9),
          border: selected ? Border.all(color: Colors.transparent) : Border.all(color: T.border),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  border: Border.all(color: T.textMuted, width: 1),
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.code, size: 13, color: T.text2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${repo.owner}/${repo.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: T.text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row action sheet. Opened by a stationary long press on a repo row.
Future<void> _showRepoMenu(BuildContext context, TrackedRepo repo) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: T.card,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(repo.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: T.blue),
            title: Text(L.str(repo.pinned ? 'unpinRepo' : 'pinRepo'),
                style: TextStyle(color: T.text)),
            onTap: () {
              Navigator.of(ctx).pop();
              store.togglePinned(repo.id);
            },
          ),
          ListTile(
            leading: Icon(Icons.tune, color: T.blue),
            title: Text(L.str('repoSettings'),
                style: TextStyle(color: T.text)),
            onTap: () {
              Navigator.of(ctx).pop();
              showRepoSettings(context, repo);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: T.red),
            title: Text(L.str('remove'),
                style: TextStyle(color: T.red)),
            onTap: () {
              Navigator.of(ctx).pop();
              store.removeRepo(repo);
            },
          ),
        ],
      ),
    ),
  );
}

class _AddRepoRow extends StatelessWidget {
  const _AddRepoRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: T.rowNormal,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: T.border),
        ),
        child: Center(child: Icon(Icons.add, size: 16, color: T.blue)),
      ),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter(
      {required this.onSettings, required this.onLogin, required this.onAccel});
  final VoidCallback onSettings;
  final VoidCallback onLogin;
  final VoidCallback onAccel;

  @override
  Widget build(BuildContext context) {
    final working = store.currentUser;
    final isLoggedIn = store.isLoggedIn;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: InkWell(
        onTap: isLoggedIn ? () => _signOut(context) : onLogin,
        child: Row(
          children: [
            _avatar(isLoggedIn, store.currentUser?.avatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isLoggedIn
                    ? (store.currentUser?.login ?? L.str('login'))
                    : L.str('login'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: T.text),
              ),
            ),
            IconButton(
              onPressed: onAccel,
              icon: Icon(Icons.rocket_launch, size: 18, color: T.text2),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onSettings,
              icon: Icon(Icons.settings, size: 16, color: T.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(bool loggedIn, String? url) {
    if (loggedIn && url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: T.rowSelected,
        backgroundImage: NetworkImage(url),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: T.rowSelected, shape: BoxShape.circle),
      child: Icon(Icons.person, size: 20, color: T.text2),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.card,
        title: Text(L.str('signOutTitle'), style: TextStyle(color: T.text)),
        content: Text(L.str('signOutConfirm'),
            style: TextStyle(color: T.text2, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L.str('cancel'), style: TextStyle(color: T.text2))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L.str('logOut'), style: TextStyle(color: T.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await store.logout();
    }
  }
}

/// ============================== Middle column ==============================
class MiddleColumn extends StatelessWidget {
  const MiddleColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: T.bg,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final repo = store.selectedRepo;
          final msgs = store.messagesForSelected;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(repo?.id ?? L.str('messages'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold, color: T.text)),
                    ),
                    if (repo != null)
                      IconButton(
                        onPressed: () => Share.share(
                            'https://github.com/${repo.owner}/${repo.name}'),
                        icon: Icon(Icons.share, size: 16, color: T.blue),
                        visualDensity: VisualDensity.compact,
                      ),
                    InkWell(
                      onTap: () => store.refreshAll(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (store.isRefreshing)
                            SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: T.blue))
                          else
                            Icon(Icons.refresh, size: 15, color: T.blue),
                          const SizedBox(width: 4),
                          Text(L.str('refresh'),
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600, color: T.blue)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 2, thickness: 1, color: T.border),
              Expanded(
                child: msgs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.move_to_inbox, size: 26, color: T.textMuted),
                            const SizedBox(height: 8),
                            Text(L.str('noMessages'),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: T.textMuted)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: store.refreshAll,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                          children: [
                            for (final m in msgs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: m.kind == MessageKind.release
                                    ? ReleaseCard(message: m)
                                    : ActionCard(message: m),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.message});
  final GHMessage message;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => store.selectMessage(message.id),
      child: GhCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.releaseTitle ?? 'Release',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: T.text)),
            const SizedBox(height: 8),
            Row(
              children: [
                PillBadge(
                    text: message.releaseBadge,
                    color: message.isReleaseBadgeGreen ? T.release : T.brown),
                const Spacer(),
                GestureDetector(
                  onTap: () => launchExternal(message.releaseURL ?? ''),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new, size: 11, color: T.blue),
                      const SizedBox(width: 4),
                      Text(L.str('open'),
                          style: TextStyle(fontSize: 11, color: T.blue)),
                    ],
                  ),
                ),
              ],
            ),
            if (message.releaseBody != null && message.releaseBody!.isNotEmpty) ...[
              const SizedBox(height: 10),
              MarkdownView(markdown: message.releaseBody!),
            ],
          ],
        ),
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  const ActionCard({super.key, required this.message});
  final GHMessage message;

  @override
  Widget build(BuildContext context) {
    final shortSha =
        (message.commitID ?? '').isNotEmpty ? message.commitID!.substring(0, message.commitID!.length < 7 ? message.commitID!.length : 7) : '';
    return InkWell(
      onTap: () => store.selectMessage(message.id),
      child: GhCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(message.actionTitle ?? 'Workflow run',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold, color: T.text)),
                ),
                const SizedBox(width: 16),
                RunStatusView(message: message),
              ],
            ),
            const SizedBox(height: 6),
            Text.rich(TextSpan(
              style: TextStyle(fontSize: 12, color: T.text2),
              children: [
                TextSpan(text: 'development build #${message.runNumber ?? 0}: commit ',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (shortSha.isNotEmpty)
                  TextSpan(text: shortSha, style: const TextStyle(decoration: TextDecoration.underline)),
                const TextSpan(text: ' pushed by '),
                if ((message.actor ?? '').isNotEmpty)
                  TextSpan(text: message.actor!, style: const TextStyle(decoration: TextDecoration.underline)),
              ],
            )),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 11, color: T.text2),
                const SizedBox(width: 4),
                Text(Fmt.relative(message.createdAt),
                    style: TextStyle(fontSize: 12, color: T.text2)),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 11, color: T.text2),
                const SizedBox(width: 4),
                Text(Fmt.duration(message.duration),
                    style: TextStyle(fontSize: 12, color: T.text2)),
                const SizedBox(width: 8),
                BranchBadge(name: message.branch),
                const Spacer(),
                GestureDetector(
                  onTap: () => launchExternal(message.actionsURL ?? ''),
                  child: Icon(Icons.open_in_new, size: 11, color: T.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================== Right column ==============================
class RightColumn extends StatelessWidget {
  const RightColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: T.column,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final msg = store.selectedMessage;
          if (msg == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.article_outlined, size: 28, color: T.textMuted),
                  const SizedBox(height: 10),
                  Text(L.str('selectReleaseOrRun'),
                      style: TextStyle(fontSize: 13, color: T.textMuted)),
                ],
              ),
            );
          }
          return _RightDetail(key: ValueKey(msg.id), message: msg);
        },
      ),
    );
  }
}

class _RightDetail extends StatefulWidget {
  const _RightDetail({super.key, required this.message});
  final GHMessage message;
  @override
  State<_RightDetail> createState() => _RightDetailState();
}

class _RightDetailState extends State<_RightDetail> {
  List<GhAsset> _assets = [];
  List<GhArtifact> _artifacts = [];
  List<GhAnnotation> _warnings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_RightDetail old) {
    super.didUpdateWidget(old);
    if (old.message.id != widget.message.id) _load();
  }

  Future<void> _load() async {
    final msg = widget.message;
    setState(() {
      _assets = [];
      _artifacts = [];
      _warnings = [];
    });
    final repo = store.selectedRepo;
    if (repo == null) return;
    final api = GitHubApi.shared;
    if (msg.kind == MessageKind.release) {
      final tag = msg.releaseTag;
      if (tag != null) {
        final rid = await api.findRelease(repo.owner, repo.name, tag);
        if (rid != null) {
          final a = await api.fetchReleaseAssets(repo.owner, repo.name, rid);
          if (mounted) setState(() => _assets = a);
        }
      }
    } else {
      final runId = msg.runID;
      if (runId != null) {
        final all = await api.fetchArtifacts(repo.owner, repo.name);
        final mine =
            all.where((a) => a.workflowRunId == runId).toList();
        if (mounted) setState(() => _artifacts = mine);
      }
      final sha = msg.commitID ?? '';
      if (sha.isNotEmpty) {
        final warns = <GhAnnotation>[];
        final checks = await api.fetchCheckRuns(repo.owner, repo.name, sha);
        for (final c in checks) {
          final url = c.annotationsUrl;
          if (url != null) {
            final anns = await api.fetchAnnotations(url);
            warns.addAll(anns.where((a) => a.annotationLevel == 'warning'));
          }
        }
        if (mounted) setState(() => _warnings = warns);
      }
    }
  }

  String get _repoKey =>
      widget.message.repoID.toLowerCase().replaceAll('/', '-');

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.kind == MessageKind.release)
              _releaseHeader(msg)
            else
              _actionHeader(msg),
            const SizedBox(height: 16),
            if (msg.kind == MessageKind.release) ...[
              SectionHeader(title: L.str('changelog')),
              if (msg.releaseBody != null && msg.releaseBody!.isNotEmpty)
                MarkdownView(markdown: msg.releaseBody!)
              else
                _hint(L.str('noBody')),
              const SizedBox(height: 16),
              SectionHeader(title: L.str('assets')),
              if (_assets.isEmpty)
                _hint(L.str('noArtifacts'))
              else
                _assetList(),
            ] else ...[
              SectionHeader(title: L.str('progress')),
              ActionProgressView(message: msg),
              const SizedBox(height: 16),
              SectionHeader(title: L.str('warnings')),
              if (_warnings.isEmpty)
                _hint(L.str('noWarnings'))
              else
                for (final w in _warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber, size: 12, color: T.brown),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(w.message ?? w.title ?? '',
                              style: TextStyle(fontSize: 12, color: T.text2)),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 16),
              SectionHeader(title: L.str('artifacts')),
              if (_artifacts.isEmpty)
                _hint(L.str('noArtifacts'))
              else
                _artifactList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _assetList() => Column(
        children: [
          for (final a in _assets)
            DownloadRow(
              keyValue: 'rel-$_repoKey-${a.id}',
              name: a.name ?? 'asset',
              size: a.size,
              url: a.browserDownloadUrl,
              needsAuth: false,
            ),
        ],
      );

  Widget _artifactList() => Column(
        children: [
          for (final a in _artifacts)
            DownloadRow(
              keyValue: 'act-$_repoKey-${a.id}',
              name: a.name ?? 'artifact',
              size: a.sizeInBytes,
              url: a.archiveDownloadUrl,
              needsAuth: true,
              onLogin: () => showLogin(context),
            ),
        ],
      );

  Widget _hint(String s) =>
      Text(s, style: TextStyle(fontSize: 13, color: T.textMuted));

  Widget _releaseHeader(GHMessage msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(msg.releaseTitle ?? 'Release',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: T.text)),
            ),
            IconButton(
              onPressed: () => launchExternal(msg.releaseURL ?? ''),
              icon: Icon(Icons.open_in_new, size: 14, color: T.blue),
              visualDensity: VisualDensity.compact,
            ),
            if (msg.releaseURL != null)
              IconButton(
                onPressed: () => Share.share(msg.releaseURL!),
                icon: Icon(Icons.share, size: 14, color: T.blue),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            PillBadge(
                text: msg.releaseBadge,
                color: msg.isReleaseBadgeGreen ? T.release : T.brown),
            if (msg.releaseTag != null) ...[
              const SizedBox(width: 6),
              Text(msg.releaseTag!,
                  style: TextStyle(fontSize: 12, color: T.text2)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _actionHeader(GHMessage msg) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunStatusView(message: msg),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(msg.actionTitle ?? 'Workflow run',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: T.text)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${msg.runNumber ?? 0}',
                      style: TextStyle(fontSize: 12, color: T.text2)),
                  const SizedBox(width: 6),
                  BranchBadge(name: msg.branch),
                ],
              ),
            ],
          ),
        ),
        if (msg.actionsURL != null)
          IconButton(
            onPressed: () => Share.share(msg.actionsURL!),
            icon: Icon(Icons.share, size: 14, color: T.blue),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}