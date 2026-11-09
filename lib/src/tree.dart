/// Whether a filesystem path lies inside a directory tree.
library;

import 'dart:io';

/// True when [path] is [root] or lies beneath it.
///
/// CORRECT FOR PATHS THAT DO NOT EXIST YET, which is the whole difficulty. The
/// naive version resolves symlinks on both sides and compares — and is wrong
/// in the direction that looks safe. On macOS `/var` is a symlink to
/// `/private/var`, so a root under a temp directory canonicalises while a
/// not-yet-created file beneath it does not, and the comparison fails. That
/// refuses every path you would want to CREATE, which is every path a write
/// tool exists for. A containment check that rejects the legitimate case reads
/// as cautious and is simply broken.
///
/// So: canonicalise the nearest ancestor that EXISTS, then re-attach the
/// remainder. The resolved part is where a symlink could hide; the
/// non-existent tail cannot contain one, because it contains nothing.
///
/// A symlink counts as existing even when its target does not. Writing to a
/// dangling link creates its target, wherever that is, so the link is
/// followed and the target is what gets judged. Read as "missing", it would
/// leave the link's own name in the tail as text and pass as inside.
///
/// It can, however, contain `..`, and that is a different hazard the sentence
/// above does not cover. A tail re-attached verbatim keeps its `..` as text,
/// so `<root>/missing/../../escape.txt` reads as a path under `<root>` and
/// passes — then the writer calls `create(recursive: true)`, the missing
/// component becomes a real directory, and the `..` the check never collapsed
/// walks out of the tree for real. The check and the write disagreed because
/// the write CHANGED THE DISK the check had reasoned about.
///
/// So the tail is collapsed lexically before comparison. That is sound for a
/// tail precisely because nothing in it exists: whatever creates those
/// components makes plain directories, never symlinks, so the kernel will walk
/// the `..` exactly the way this collapse predicts. Lexical collapse would NOT
/// be sound on the resolved head, where a `..` after a symlink means something
/// else entirely — which is why it is applied to the tail alone.
///
/// A path that cannot be judged (a loop of links) is outside.
bool isInsideTree(Directory root, String path) {
  try {
    final r = canonicaliseExisting(root.absolute.path);
    final t = canonicaliseExisting(path);
    return t == r || t.startsWith('$r/');
  } on FileSystemException {
    return false;
  }
}

/// How many links one path may pass through, as the kernel's own limit
/// (ELOOP): a loop of dangling links would otherwise be followed forever.
const _maxLinks = 40;

/// Resolves the longest existing prefix of [path] and re-attaches the rest.
/// A symlink on the way is followed, dangling or not. Throws a
/// [FileSystemException] for a path that passes through more than
/// [_maxLinks] links.
String canonicaliseExisting(String path) => _canonicalise(path, 0);

String _canonicalise(String path, int links) {
  final parts = path.split('/');
  final tail = <String>[];
  var head = path;
  while (head.isNotEmpty && head != '/') {
    if (FileSystemEntity.isLinkSync(head)) {
      if (links >= _maxLinks) {
        throw FileSystemException('too many levels of symbolic links', path);
      }
      final target = Link(head).targetSync();
      final dir = parts.sublist(0, parts.length - 1).join('/');
      final at = target.startsWith('/') ? target : '$dir/$target';
      return _canonicalise([at, ...tail].join('/'), links + 1);
    }
    try {
      final d = Directory(head);
      if (d.existsSync()) return _rejoin(d.resolveSymbolicLinksSync(), tail);
      final f = File(head);
      if (f.existsSync()) return _rejoin(f.resolveSymbolicLinksSync(), tail);
    } on FileSystemException {
      // It exists but cannot be resolved (its permissions, or it changed
      // since it was looked at): judge it by its parent.
    }
    if (parts.isEmpty) break;
    tail.insert(0, parts.removeLast());
    head = parts.join('/');
  }
  return path;
}

String _rejoin(String resolved, List<String> tail) {
  if (tail.isEmpty) return resolved;

  // The head is real and already resolved, so `..` in the tail can pop its
  // trailing segments. Clamped at `/`: walking above the root yields the root,
  // which is what the kernel does too.
  final segments = resolved.split('/')..removeWhere((s) => s.isEmpty);
  for (final part in tail) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
    } else {
      segments.add(part);
    }
  }
  return '/${segments.join('/')}';
}
