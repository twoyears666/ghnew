import 'package:flutter/material.dart';

import '../app_store.dart';
import '../theme.dart';
import 'widgets/columns.dart';
import 'widgets/markdown_view.dart';
import 'widgets/sheets.dart';

/// Portrait drill-down level (prevents the three panes squeezing together).
enum Level { left, middle, right }

class ContentView extends StatefulWidget {
  const ContentView({super.key});
  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  bool _pickerShown = false;
  bool _addShown = false;
  bool _errorShown = false;

  @override
  void initState() {
    super.initState();
    store.addListener(_onChange);
  }

  @override
  void dispose() {
    store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    // First-login repo picker.
    if (store.showRepoPicker && !_pickerShown) {
      _pickerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showRepoPicker(context).then((_) {
          _pickerShown = false;
        });
      });
    } else if (!store.showRepoPicker) {
      _pickerShown = false;
    }
    // Add-repo sheet.
    if (store.showAddRepo && !_addShown) {
      _addShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAddRepo(context).then((_) {
          _addShown = false;
          store.showAddRepo = false;
        });
      });
    } else if (!store.showAddRepo) {
      _addShown = false;
    }
    // Error banner.
    final err = store.errorMessage;
    if (err != null && !_errorShown) {
      _errorShown = true;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
            content: Text(err, maxLines: 1, overflow: TextOverflow.ellipsis),
            backgroundColor: T.red,
          ))
          .closed
          .then((_) {
        _errorShown = false;
        store.clearError();
      });
    } else if (err == null) {
      _errorShown = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= constraints.maxHeight;
      if (wide) return _landscape(constraints.maxWidth);
      return _portrait();
    });
  }

  Widget _landscape(double width) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: width * 0.24, child: const LeftColumn()),
        const Expanded(child: MiddleColumn()),
        SizedBox(width: width * 0.20, child: const RightColumn()),
      ],
    );
  }

  Widget _portrait() {
    final level = _currentLevel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (level != Level.left)
          SizedBox(
            height: 40,
            child: Row(
              children: [
                IconButton(
                  onPressed: _goBack,
                  icon: Icon(Icons.arrow_back_ios_new, size: 16, color: T.blue),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        Expanded(
          child: switch (level) {
            Level.left => const LeftColumn(),
            Level.middle => const MiddleColumn(),
            Level.right => const RightColumn(),
          },
        ),
      ],
    );
  }

  Level get _currentLevel {
    if (store.selectedRepoID == null) return Level.left;
    final msg = store.selectedMessage;
    if (msg != null && msg.repoID == store.selectedRepoID) return Level.right;
    return Level.middle;
  }

  void _goBack() {
    if (store.selectedMessageID != null) {
      // right -> middle: keep repo, clear message
      store.selectedMessageID = null;
    } else {
      // middle -> left: clear message and repo
      store.selectedMessageID = null;
      store.selectedRepoID = null;
    }
    store.notifySelection();
  }
}

/// Opens an external URL (shim kept here for UI call sites).
void openInBrowser(String url) => launchExternal(url);