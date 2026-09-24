import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'github_api.dart';

enum DlState { idle, downloading, done, failed, authRequired }

class DownloadItem extends ChangeNotifier {
  final String id;
  final String name;
  final int? size;
  final String url;
  final bool needsAuth;

  DlState state = DlState.idle;
  double progress = 0;
  String? error;
  String? filePath;

  DownloadItem({
    required this.id,
    required this.name,
    this.size,
    required this.url,
    this.needsAuth = false,
  });
}

/// Central download manager (port of DownloadManager.swift). Uses http's
/// streaming send to report byte-level progress.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager shared = DownloadManager._();

  final Map<String, DownloadItem> _items = {};
  DownloadItem? itemFor(String key) => _items[key];

  void download({
    required String key,
    required String name,
    int? size,
    required String url,
    required bool needsAuth,
  }) {
    final t = GitHubApi.shared.token;
    final loggedIn = t != null && t.isNotEmpty;
    if (needsAuth && !loggedIn) {
      final item = DownloadItem(
          id: key, name: name, size: size, url: url, needsAuth: needsAuth);
      item.state = DlState.authRequired;
      _items[key] = item;
      notifyListeners();
      return;
    }
    _start(key, name, size, url, needsAuth);
  }

  Future<void> _start(
      String key, String name, int? size, String url, bool needsAuth) async {
    final prior = _items[key];
    final item = prior ?? DownloadItem(
        id: key, name: name, size: size, url: url, needsAuth: needsAuth);
    item.state = DlState.downloading;
    item.progress = 0;
    item.error = null;
    _items[key] = item;
    notifyListeners();

    try {
      final uri = Uri.parse(url);
      final headers = <String, String>{
        'User-Agent': 'ghnew/1.0',
        'Accept': 'application/vnd.github+json',
      };
      final t = GitHubApi.shared.token;
      if (t != null && t.isNotEmpty) {
        headers['Authorization'] = 'Bearer $t';
      }
      final req = http.Request('GET', uri);
      req.headers.addAll(headers);
      final client = http.Client();
      final resp = await client.send(req).timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        resp.drain<void>();
        item.state = DlState.failed;
        item.error = 'HTTP ${resp.statusCode}';
        notifyListeners();
        return;
      }
      final total = resp.contentLength ?? 0;
      int received = 0;
      final dir = Directory(p.join(
          (await getApplicationDocumentsDirectory()).path, 'Downloads'));
      await dir.create(recursive: true);
      final file = await _targetFile(dir, item.name);
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            item.progress = (received / total).clamp(0.0, 1.0).toDouble();
          }
          notifyListeners();
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        rethrow;
      }
      item.filePath = file.path;
      item.state = DlState.done;
      item.progress = 1;
      notifyListeners();
    } catch (e) {
      item.state = DlState.failed;
      item.error = e.toString();
      notifyListeners();
    }
  }

  Future<File> _targetFile(Directory dir, String rawName) async {
    final safe = rawName.replaceAll('/', '_');
    final ext = p.extension(safe);
    final base = p.basenameWithoutExtension(safe);
    var target = p.join(dir.path, safe);
    var counter = 1;
    while (await File(target).exists()) {
      target = p.join(dir.path, '$base (${counter++})$ext');
    }
    return File(target);
  }

  Future<void> reveal(DownloadItem item) async {
    final path = item.filePath;
    if (path == null) return;
    final f = File(path);
    if (!await f.exists()) return;
    final x = XFile(path);
    await Share.shareXFiles([x]);
  }

  static String bytesString(int? bytes) {
    if (bytes == null || bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}