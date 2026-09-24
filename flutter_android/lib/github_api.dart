import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crypto.dart';
import 'models.dart';

class ApiException implements Exception {
  final int? code;
  final String detail;
  ApiException(this.code, this.detail);
  @override
  String toString() =>
      code == null ? 'Invalid server response.' : 'GitHub API error $code: $detail';
}

/// Minimal GitHub REST API client used by the tracker (port of GitHubAPI.swift).
class GitHubApi {
  GitHubApi._();
  static final GitHubApi shared = GitHubApi._();
  static const base = 'https://api.github.com';

  String? token;
  static const _ua = 'ghnew/1.0';

  /// Async load of a stored token (called at startup).
  Future<void> loadToken() async {
    final t = await SecretStore.loadToken();
    if (t != null && t.isNotEmpty) token = t;
  }

  Map<String, String> _headers({bool acceptJson = true}) {
    final h = <String, String>{
      'User-Agent': _ua,
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };
    final t = token;
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('$base$path');
    final resp = await http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 30));
    _throwIf(resp);
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<dynamic> _getAnyText(String url) async {
    final uri = Uri.parse(url);
    final resp =
        await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 30));
    _throwIf(resp, outOfBand: true);
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static void _throwIf(http.Response resp, {bool outOfBand = false}) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    final detail = utf8.decode(resp.bodyBytes, allowMalformed: true);
    throw ApiException(resp.statusCode, detail.length > 300
        ? detail.substring(0, 300)
        : detail);
  }

  Future<GhRepo> validateRepo(String owner, String name) async {
    final eo = Uri.encodeComponent(owner);
    final en = Uri.encodeComponent(name);
    final j = await _get('/repos/$eo/$en');
    return GhRepo.fromJson(j as Map<String, dynamic>);
  }

  Future<GitHubUser?> fetchUser() async {
    try {
      final j = await _get('/user');
      return GitHubUser.fromJson(j as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<List<GhRelease>> fetchReleases(String owner, String name) async {
    final j = await _get(
        '/repos/$owner/$name/releases?per_page=30');
    return (j as List)
        .map((e) => GhRelease.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GhRun>> fetchRuns(String owner, String name) async {
    final j = await _get(
        '/repos/$owner/$name/actions/runs?per_page=30');
    final list = (j as Map<String, dynamic>)['workflow_runs'] as List? ?? [];
    return list
        .map((e) => GhRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GhRepoListItem>> fetchUserRepos() async {
    final j = await _get('/user/repos?per_page=100&sort=updated');
    if (j is! List) return [];
    return j
        .map((e) => GhRepoListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GhArtifact>> fetchArtifacts(String owner, String name) async {
    final j = await _get('/repos/$owner/$name/actions/artifacts?per_page=50');
    final list = (j as Map<String, dynamic>)['artifacts'] as List? ?? [];
    return list
        .map((e) => GhArtifact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GhAsset>> fetchReleaseAssets(
      String owner, String name, int releaseId) async {
    final j = await _get('/repos/$owner/$name/releases/$releaseId/assets?per_page=50');
    return (j as List)
        .map((e) => GhAsset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GhCheckRun>> fetchCheckRuns(
      String owner, String name, String headSha) async {
    final j = await _get(
        '/repos/$owner/$name/commits/$headSha/check-runs?per_page=50');
    final list = (j as Map<String, dynamic>)['check_runs'] as List? ?? [];
    return list
        .map((e) => GhCheckRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GhAnnotation>> fetchAnnotations(String url) async {
    try {
      final j = await _getAnyText(url);
      return (j as List)
          .map((e) => GhAnnotation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<int?> findRelease(String owner, String name, String tag) async {
    final rels = await fetchReleases(owner, name);
    for (final r in rels) {
      if (r.tagName == tag) return r.id;
    }
    return null;
  }
}