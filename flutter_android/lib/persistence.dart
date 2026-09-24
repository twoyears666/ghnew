import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// File persistence: repos live in documents/repos.json; each message is its
/// own JSON file under documents/messages/<id>.json.
class Storage {
  Storage._();
  static final Storage i = Storage._();

  static const _userKey = 'ghUser';
  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<String> _reposPath() async =>
      p.join((await _dir()).path, 'repos.json');
  Future<String> _messagesDir() async =>
      p.join((await _dir()).path, 'messages');

  // Login user (SharedPreferences, plain — not secret).
  Future<GitHubUser?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_userKey);
    if (s == null || s.isEmpty) return null;
    try {
      return GitHubUser.fromStored(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(GitHubUser? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      await prefs.remove(_userKey);
    } else {
      await prefs.setString(_userKey, user.toStored());
    }
  }

  Future<List<TrackedRepo>> loadRepos() async {
    try {
      final f = File(await _reposPath());
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list
          .map((e) => TrackedRepo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRepos(List<TrackedRepo> repos) async {
    final f = File(await _reposPath());
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(repos.map((e) => e.toJson()).toList()));
  }

  Future<void> saveMessage(GHMessage msg) async {
    final dir = await _messagesDir();
    await Directory(dir).create(recursive: true);
    final f = File(p.join(dir, '${msg.id}.json'));
    await f.writeAsString(jsonEncode(msg.toJson()));
  }

  Future<void> deleteMessage(GHMessage msg) async {
    final dir = await _messagesDir();
    final f = File(p.join(dir, '${msg.id}.json'));
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  Future<List<GHMessage>> loadMessages() async {
    final dirPath = await _messagesDir();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final out = <GHMessage>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(GHMessage.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }
}