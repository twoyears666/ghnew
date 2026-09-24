import 'package:flutter/material.dart';

import '../app_store.dart';
import '../github_api.dart';
import '../l10n.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';
import '../util.dart';
import 'markdown_view.dart';

/// ============================== Login ==============================
Future<void> showLogin(BuildContext context) {
  return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginSheet()));
}

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key});
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final _ctrl = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await store.login(_ctrl.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('ghnew',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: T.text)),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(L.str('cancel'),
                          style: TextStyle(color: T.red))),
                ],
              ),
              const SizedBox(height: 8),
              Text(L.str('tokenPrompt'),
                  style: TextStyle(fontSize: 13, color: T.text2)),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(color: T.text),
                decoration: InputDecoration(
                  labelText: L.str('tokenLabel'),
                  hintText: L.str('tokenPlaceholder'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: T.border)),
                  filled: true,
                  fillColor: T.card,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => launchExternal(
                    'https://github.com/settings/tokens/new?scopes=repo&description=ghnew&type=classic'),
                child: Text(L.str('createToken'),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: T.blue)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(fontSize: 13, color: T.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed:
                      (_working || _ctrl.text.trim().isEmpty) ? null : _login,
                  style: FilledButton.styleFrom(backgroundColor: T.blue),
                  child: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(L.str('login')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================== Settings ==============================
Future<void> showSettings(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SettingsSheet()));
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(L.str('settings'),
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: T.text)),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(L.str('done'),
                          style: TextStyle(
                              color: T.blue, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: SettingsStore.i,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _sectionTitle(L.str('appearance')),
                    _card([
                      SwitchListTile(
                        title: Text(L.str('darkMode'),
                            style: TextStyle(color: T.text)),
                        value: SettingsStore.i.isDark,
                        activeThumbColor: T.blue,
                        onChanged: (v) => SettingsStore.i.isDark = v,
                      ),
                      Divider(height: 1, color: T.border),
                      ListTile(
                        title: Text(L.str('language'),
                            style: TextStyle(color: T.text)),
                        trailing: DropdownButton<String>(
                          value: SettingsStore.i.lang,
                          underline: const SizedBox.shrink(),
                          dropdownColor: T.card,
                          items: const [
                            DropdownMenuItem(value: 'zh', child: Text('中文')),
                            DropdownMenuItem(value: 'en', child: Text('English')),
                          ],
                          onChanged: (v) {
                            if (v != null) SettingsStore.i.lang = v;
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _sectionTitle(L.str('support')),
                    _card([
                      _row(Icons.bug_report_outlined, L.str('openIssue'),
                          () => launchExternal(
                              'https://github.com/twoyears666/ghnew/issues/new')),
                      Divider(height: 1, color: T.border),
                      _row(Icons.code, L.str('ghnewRepo'),
                          () => launchExternal('https://github.com/twoyears666/ghnew')),
                    ]),
                    const SizedBox(height: 16),
                    _sectionTitle(L.str('dangerZone')),
                    _card([
                      ListTile(
                        title: Center(
                          child: Text(L.str('reset'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: T.red)),
                        ),
                        onTap: () => _confirmReset(context),
                      ),
                    ]),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.card,
        title: Text(L.str('reset'), style: TextStyle(color: T.text)),
        content: Text(L.str('resetPrompt'),
            style: TextStyle(color: T.text2, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L.str('cancel'),
                  style: TextStyle(color: T.text2))),
          TextButton(
              onPressed: () async {
                await store.resetAll();
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: Text(L.str('reset'), style: TextStyle(color: T.red))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: T.text2)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: T.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.border),
        ),
        child: Column(children: children),
      );

  Widget _row(IconData icon, String title, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: T.blue, size: 20),
        title: Text(title, style: TextStyle(color: T.text)),
        trailing: Icon(Icons.chevron_right, color: T.textMuted, size: 18),
        onTap: onTap,
      );
}

/// ============================== Repo settings ==============================
Future<void> showRepoSettings(BuildContext context, TrackedRepo repo) {
  return Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RepoSettingsSheet(repo: repo)));
}

class RepoSettingsSheet extends StatefulWidget {
  const RepoSettingsSheet({super.key, required this.repo});
  final TrackedRepo repo;
  @override
  State<RepoSettingsSheet> createState() => _RepoSettingsSheetState();
}

class _RepoSettingsSheetState extends State<RepoSettingsSheet> {
  late bool _release = widget.repo.watchRelease;
  late bool _action = widget.repo.watchAction;
  late bool _notify = widget.repo.notify;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_ios_new, color: T.blue, size: 18)),
                  const SizedBox(width: 8),
                  Text(L.str('repoSettings'),
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: T.text)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _rowCard(Text(widget.repo.id,
                      style: TextStyle(fontSize: 13, color: T.text2))),
                  const SizedBox(height: 16),
                  _rowCard(Column(
                    children: [
                      CheckboxListTile(
                        title: Text(L.str('trackReleases'),
                            style: TextStyle(color: T.text)),
                        value: _release,
                        activeColor: T.blue,
                        onChanged: (v) => setState(() => _release = v ?? false),
                      ),
                      Divider(height: 1, color: T.border),
                      CheckboxListTile(
                        title: Text(L.str('trackActions'),
                            style: TextStyle(color: T.text)),
                        value: _action,
                        activeColor: T.blue,
                        onChanged: (v) => setState(() => _action = v ?? false),
                      ),
                      Divider(height: 1, color: T.border),
                      CheckboxListTile(
                        title: Text(L.str('sendNotifications'),
                            style: TextStyle(color: T.text)),
                        value: _notify,
                        activeColor: T.blue,
                        onChanged: (v) => setState(() => _notify = v ?? false),
                      ),
                    ],
                  )),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: T.blue),
                      onPressed: () {
                        final r = widget.repo;
                        r.watchRelease = _release;
                        r.watchAction = _action;
                        r.notify = _notify;
                        store.updateRepo(r);
                        Navigator.of(context).pop();
                      },
                      child: Text(L.str('save')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowCard(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: T.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.border),
        ),
        child: child,
      );
}

/// ============================== Add repository ==============================
Future<void> showAddRepo(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddRepoSheet()));
}

class AddRepoSheet extends StatefulWidget {
  const AddRepoSheet({super.key});
  @override
  State<AddRepoSheet> createState() => _AddRepoSheetState();
}

class _AddRepoSheetState extends State<AddRepoSheet> {
  final _ctrl = TextEditingController();
  bool _release = true;
  bool _action = true;
  bool _notify = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (store.pendingOwner != null && store.pendingName != null) {
      _ctrl.text = '${store.pendingOwner}/${store.pendingName}';
    }
    store.pendingOwner = null;
    store.pendingName = null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _working = true;
    });
    final parts = _ctrl.text.split('/').map((e) => e.trim()).toList();
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      setState(() {
        _error = L.str('howToAdd');
        _working = false;
      });
      return;
    }
    try {
      await store.addRepo(
          owner: parts[0],
          name: parts[1],
          watchRelease: _release,
          watchAction: _action,
          notify: _notify);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_ios_new, color: T.blue, size: 18)),
                  const SizedBox(width: 8),
                  Text(L.str('addRepo'),
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: T.text)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: T.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: T.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Repository',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: T.text2)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _ctrl,
                          autocorrect: false,
                          style: TextStyle(color: T.text),
                          decoration: InputDecoration(
                            hintText: L.str('ownerRepoPlaceholder'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: T.border)),
                            filled: true,
                            fillColor: T.bg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: T.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: T.border),
                    ),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: Text(L.str('trackReleases'),
                              style: TextStyle(color: T.text)),
                          value: _release,
                          activeColor: T.blue,
                          onChanged: (v) => setState(() => _release = v ?? false),
                        ),
                        Divider(height: 1, color: T.border),
                        CheckboxListTile(
                          title: Text(L.str('trackActions'),
                              style: TextStyle(color: T.text)),
                          value: _action,
                          activeColor: T.blue,
                          onChanged: (v) => setState(() => _action = v ?? false),
                        ),
                        Divider(height: 1, color: T.border),
                        CheckboxListTile(
                          title: Text(L.str('sendNotifications'),
                              style: TextStyle(color: T.text)),
                          value: _notify,
                          activeColor: T.blue,
                          onChanged: (v) => setState(() => _notify = v ?? false),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(fontSize: 13, color: T.red)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: T.blue),
                      onPressed: _working ? null : _save,
                      child: _working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text('Add'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================== First-login repo picker ==============================
Future<void> showRepoPicker(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const RepoPickerSheet(), fullscreenDialog: true));
}

class RepoPickerSheet extends StatefulWidget {
  const RepoPickerSheet({super.key});
  @override
  State<RepoPickerSheet> createState() => _RepoPickerSheetState();
}

class _RepoPickerSheetState extends State<RepoPickerSheet> {
  List<GhRepoListItem> _repos = [];
  final Set<int> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<GhRepoListItem> items = [];
    try {
      items = await store.api.fetchUserRepos();
    } catch (_) {}
    setState(() {
      _repos = items;
      _loading = false;
    });
  }

  Future<void> _addSelected() async {
    for (final r in _repos) {
      if (!_selected.contains(r.id)) continue;
      final key = r.fullName.toLowerCase();
      if (store.repos.any((x) => x.id.toLowerCase() == key)) continue;
      try {
        await store.addRepo(
            owner: r.ownerLogin, name: r.repoName, watchRelease: true, watchAction: true);
      } catch (_) {}
    }
    store.showRepoPicker = false;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(L.str('addRepos'),
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: T.text)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                          onPressed: () {
                            store.showRepoPicker = false;
                            Navigator.of(context).pop();
                          },
                          child: Text(L.str('skip'),
                              style: TextStyle(color: T.text2))),
                      TextButton(
                          onPressed: _selected.isEmpty ? null : _addSelected,
                          child: Text(L.str('addSelected'),
                              style: TextStyle(
                                  color: _selected.isEmpty ? T.textMuted : T.blue,
                                  fontWeight: FontWeight.w600))),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _repos.isEmpty
                      ? Center(
                          child: Text(L.str('noRepos'),
                              style: TextStyle(color: T.text2)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _repos.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: T.border),
                          itemBuilder: (context, i) {
                            final r = _repos[i];
                            final on = _selected.contains(r.id);
                            return InkWell(
                              onTap: () => setState(() {
                                if (on) {
                                  _selected.remove(r.id);
                                } else {
                                  _selected.add(r.id);
                                }
                              }),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                child: Row(
                                  children: [
                                    Icon(on
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                        size: 20,
                                        color: on ? T.blue : T.textMuted),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(r.fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14, color: T.text)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}