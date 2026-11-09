# is_path_confinement

Whether a filesystem path stays inside a directory tree. No runtime package
dependencies; uses `dart:io` to resolve existing paths and symbolic links.

```dart
import 'dart:io';

import 'package:is_path_confinement/is_path_confinement.dart';

void main() {
  final root = Directory.systemTemp.createTempSync('paths-');
  try {
    print(isInsideTree(root, '${root.path}/new/file.txt')); // true
    print(isInsideTree(root, '${root.path}/../outside.txt')); // false
  } finally {
    root.deleteSync(recursive: true);
  }
}
```

## API

- `isInsideTree(Directory root, String path)` resolves the root and candidate
  and checks containment. A filesystem exception while judging the path
  produces `false`.
- `canonicaliseExisting(String path)` resolves the longest existing prefix,
  follows symbolic links (including dangling links), and appends a lexically
  normalized missing tail. It throws `FileSystemException` when following
  too many links.

Pass absolute candidate paths. A missing tail can contain `.` and `..`;
normalizing it prevents a not-yet-created directory from disguising an escape.
Existing symlinks are resolved before comparing paths, so an existing link
inside the tree that points outside it is not considered inside.

## Limits

This is a path check, **not a sandbox** or an atomic checked file operation.
The filesystem can change between checking a path and using it. It does not
constrain what a program can do, nor defend against concurrent symlink changes.

The initial implementation uses POSIX `/` path syntax and is checked on macOS.
Windows support is a gap, not a claim of this release. It uses `dart:io` and
cannot run in a browser.

A known inherited edge case: a root of `/` incorrectly refuses descendants
(although `/` itself is accepted). Use an ordinary directory as the root.
Tracked as enspyrco/intersyntactic#1102; this extraction does not fix it.

## Origin

Extracted from `enspyrco/intersyntactic` at `4ba9a675`, from
`packages/path_confinement`. The path-checking implementation is unchanged;
the library comment no longer names its original consumers.

Apache-2.0. Copyright 2026 Enspyr Pty Ltd.
