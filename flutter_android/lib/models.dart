import 'dart:convert';

DateTime? ghDate(String? s) =>
    (s == null) ? null : DateTime.tryParse(s)?.toLocal();

class TrackedRepo {
  String owner;
  String name;
  bool watchRelease;
  bool watchAction;
  bool notify;
  String? defaultBranch;
  int? lastSeenRelease;
  int? lastSeenRun;
  DateTime addedAt;

  String get id => '$owner/$name';

  TrackedRepo({
    required this.owner,
    required this.name,
    this.watchRelease = true,
    this.watchAction = true,
    this.notify = true,
    this.defaultBranch,
    this.lastSeenRelease,
    this.lastSeenRun,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory TrackedRepo.fromJson(Map<String, dynamic> j) => TrackedRepo(
        owner: j['owner'] as String,
        name: j['name'] as String,
        watchRelease: j['watchRelease'] as bool? ?? true,
        watchAction: j['watchAction'] as bool? ?? true,
        notify: j['notify'] as bool? ?? true,
        defaultBranch: j['defaultBranch'] as String?,
        lastSeenRelease: j['lastSeenRelease'] as int?,
        lastSeenRun: j['lastSeenRun'] as int?,
        addedAt: j['addedAt'] != null
            ? DateTime.tryParse(j['addedAt'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'name': name,
        'watchRelease': watchRelease,
        'watchAction': watchAction,
        'notify': notify,
        'defaultBranch': defaultBranch,
        'lastSeenRelease': lastSeenRelease,
        'lastSeenRun': lastSeenRun,
        'addedAt': addedAt.toIso8601String(),
      };
}

enum MessageKind { release, action }

class GHMessage {
  final String id;
  final String repoID;
  final MessageKind kind;
  final DateTime createdAt;

  String? releaseTitle;
  String? releaseTag;
  String? releaseBody;
  bool isPrerelease;
  String? releaseURL;

  String? actionTitle;
  int? runNumber;
  int? runID;
  String? commitID;
  String? actor;
  String? branch;
  String? runStatus;
  String? runConclusion;
  Duration? duration;
  String? actionsURL;

  GHMessage({
    required this.id,
    required this.repoID,
    required this.kind,
    required this.createdAt,
    this.releaseTitle,
    this.releaseTag,
    this.releaseBody,
    this.isPrerelease = false,
    this.releaseURL,
    this.actionTitle,
    this.runNumber,
    this.runID,
    this.commitID,
    this.actor,
    this.branch,
    this.runStatus,
    this.runConclusion,
    this.duration,
    this.actionsURL,
  });

  String get releaseBadge {
    final t = (releaseTag ?? '').toLowerCase();
    if (t.contains('beta')) return 'beta release';
    if (t.contains('alpha')) return 'alpha release';
    if (t.contains('rc') || t.contains('preview')) return 'prerelease';
    if (isPrerelease) return 'prerelease';
    return 'release';
  }

  bool get isReleaseBadgeGreen =>
      releaseBadge == 'release' || releaseBadge.contains('stable');

  factory GHMessage.fromJson(Map<String, dynamic> j) => GHMessage(
        id: j['id'] as String,
        repoID: j['repoID'] as String,
        kind: j['kind'] == 'action' ? MessageKind.action : MessageKind.release,
        createdAt: DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now(),
        releaseTitle: j['releaseTitle'] as String?,
        releaseTag: j['releaseTag'] as String?,
        releaseBody: j['releaseBody'] as String?,
        isPrerelease: j['isPrerelease'] as bool? ?? false,
        releaseURL: j['releaseURL'] as String?,
        actionTitle: j['actionTitle'] as String?,
        runNumber: j['runNumber'] as int?,
        runID: j['runID'] as int?,
        commitID: j['commitID'] as String?,
        actor: j['actor'] as String?,
        branch: j['branch'] as String?,
        runStatus: j['runStatus'] as String?,
        runConclusion: j['runConclusion'] as String?,
        duration: j['duration'] != null
            ? Duration(milliseconds: j['duration'] as int)
            : null,
        actionsURL: j['actionsURL'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'repoID': repoID,
        'kind': kind == MessageKind.action ? 'action' : 'release',
        'createdAt': createdAt.toIso8601String(),
        'releaseTitle': releaseTitle,
        'releaseTag': releaseTag,
        'releaseBody': releaseBody,
        'isPrerelease': isPrerelease,
        'releaseURL': releaseURL,
        'actionTitle': actionTitle,
        'runNumber': runNumber,
        'runID': runID,
        'commitID': commitID,
        'actor': actor,
        'branch': branch,
        'runStatus': runStatus,
        'runConclusion': runConclusion,
        'duration': duration?.inMilliseconds,
        'actionsURL': actionsURL,
      };
}

class GhRepo {
  final String fullName;
  final String? defaultBranch;
  final bool isPrivate;

  GhRepo({
    required this.fullName,
    this.defaultBranch,
    required this.isPrivate,
  });

  factory GhRepo.fromJson(Map<String, dynamic> j) => GhRepo(
        fullName: j['full_name'] as String? ?? '',
        defaultBranch: j['default_branch'] as String?,
        isPrivate: j['private'] as bool? ?? false,
      );
}

class GhRelease {
  final int id;
  final String? tagName;
  final String? name;
  final String? body;
  final bool? prerelease;
  final String? htmlUrl;
  final String? publishedAt;

  GhRelease({
    required this.id,
    this.tagName,
    this.name,
    this.body,
    this.prerelease,
    this.htmlUrl,
    this.publishedAt,
  });

  factory GhRelease.fromJson(Map<String, dynamic> j) => GhRelease(
        id: j['id'] as int,
        tagName: j['tag_name'] as String?,
        name: j['name'] as String?,
        body: j['body'] as String?,
        prerelease: j['prerelease'] as bool?,
        htmlUrl: j['html_url'] as String?,
        publishedAt: j['published_at'] as String?,
      );
}

class GitHubUser {
  String? login;
  String? avatarUrl;

  GitHubUser({this.login, this.avatarUrl});

  factory GitHubUser.fromJson(Map<String, dynamic> j) => GitHubUser(
        login: j['login'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );

  Map<String, dynamic> toJson() => {'login': login, 'avatar_url': avatarUrl};

  factory GitHubUser.fromStored(String s) =>
      GitHubUser.fromJson(jsonDecode(s) as Map<String, dynamic>);
  String toStored() => jsonEncode(toJson());
}

class GhAuthor {
  final String? login;
  final String? avatarUrl;

  GhAuthor({this.login, this.avatarUrl});

  factory GhAuthor.fromJson(Map<String, dynamic> j) => GhAuthor(
        login: j['login'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );
}

class GhRun {
  final int id;
  final String? displayTitle;
  final int? runNumber;
  final String? status;
  final String? conclusion;
  final String? headSha;
  final String? headBranch;
  final String? createdAt;
  final String? updatedAt;
  final String? runStartedAt;
  final String? triggeringActor;
  final String? actor;
  final String? htmlUrl;

  GhRun({
    required this.id,
    this.displayTitle,
    this.runNumber,
    this.status,
    this.conclusion,
    this.headSha,
    this.headBranch,
    this.createdAt,
    this.updatedAt,
    this.runStartedAt,
    this.triggeringActor,
    this.actor,
    this.htmlUrl,
  });

  factory GhRun.fromJson(Map<String, dynamic> j) => GhRun(
        id: j['id'] as int,
        displayTitle: j['display_title'] as String?,
        runNumber: j['run_number'] as int?,
        status: j['status'] as String?,
        conclusion: j['conclusion'] as String?,
        headSha: j['head_sha'] as String?,
        headBranch: j['head_branch'] as String?,
        createdAt: j['created_at'] as String?,
        updatedAt: j['updated_at'] as String?,
        runStartedAt: j['run_started_at'] as String?,
        triggeringActor: _authorLogin(j['triggering_actor']),
        actor: _authorLogin(j['actor']),
        htmlUrl: j['html_url'] as String?,
      );

  static String? _authorLogin(dynamic a) {
    if (a is Map<String, dynamic>) return a['login'] as String?;
    return null;
  }
}

class GhArtifact {
  final int id;
  final String? name;
  final int? sizeInBytes;
  final String? archiveDownloadUrl;
  final bool? expired;
  final int? workflowRunId;

  GhArtifact({
    required this.id,
    this.name,
    this.sizeInBytes,
    this.archiveDownloadUrl,
    this.expired,
    this.workflowRunId,
  });

  factory GhArtifact.fromJson(Map<String, dynamic> j) => GhArtifact(
        id: j['id'] as int,
        name: j['name'] as String?,
        sizeInBytes: j['size_in_bytes'] as int?,
        archiveDownloadUrl: j['archive_download_url'] as String?,
        expired: j['expired'] as bool?,
        workflowRunId: ((j['workflow_run'] as Map?)?.isNotEmpty ?? false)
            ? (j['workflow_run']['id'] as int?)
            : null,
      );
}

class GhAsset {
  final int id;
  final String? name;
  final int? size;
  final String? browserDownloadUrl;
  final String? contentType;

  GhAsset({
    required this.id,
    this.name,
    this.size,
    this.browserDownloadUrl,
    this.contentType,
  });

  factory GhAsset.fromJson(Map<String, dynamic> j) => GhAsset(
        id: j['id'] as int,
        name: j['name'] as String?,
        size: j['size'] as int?,
        browserDownloadUrl: j['browser_download_url'] as String?,
        contentType: j['content_type'] as String?,
      );
}

class GhCheckRun {
  final int? id;
  final String? conclusion;
  final String? name;
  final String? annotationsUrl;

  GhCheckRun({
    this.id,
    this.conclusion,
    this.name,
    this.annotationsUrl,
  });

  factory GhCheckRun.fromJson(Map<String, dynamic> j) => GhCheckRun(
        id: j['id'] as int?,
        conclusion: j['conclusion'] as String?,
        name: j['name'] as String?,
        annotationsUrl: j['annotations_url'] as String?,
      );
}

class GhAnnotation {
  final String? message;
  final String? annotationLevel;
  final String? path;
  final String? title;

  GhAnnotation({
    this.message,
    this.annotationLevel,
    this.path,
    this.title,
  });

  factory GhAnnotation.fromJson(Map<String, dynamic> j) => GhAnnotation(
        message: j['message'] as String?,
        annotationLevel: j['annotation_level'] as String?,
        path: j['path'] as String?,
        title: j['title'] as String?,
      );
}

class GhRepoListItem {
  final int id;
  final String fullName;
  final String? defaultBranch;
  final String ownerLogin;
  final String repoName;

  GhRepoListItem({
    required this.id,
    required this.fullName,
    this.defaultBranch,
    required this.ownerLogin,
    required this.repoName,
  });

  factory GhRepoListItem.fromJson(Map<String, dynamic> j) {
    final full = j['full_name'] as String? ?? '';
    final parts = full.split('/');
    final owner = (j['owner'] as Map?)?.isNotEmpty ?? false
        ? j['owner']['login'] as String?
        : null;
    return GhRepoListItem(
      id: j['id'] as int,
      fullName: full,
      defaultBranch: j['default_branch'] as String?,
      ownerLogin: owner ?? (parts.isNotEmpty ? parts.first : ''),
      repoName: parts.length > 1 ? parts.last : '',
    );
  }
}