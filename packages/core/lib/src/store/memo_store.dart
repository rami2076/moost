import 'dart:io';

import '../model/memo.dart';
import 'json_file_store.dart';

/// `~/.moost/v1/memos.json` の CRUD。
///
/// エンベロープ形式は `{"schemaVersion": 1, "memos": [...]}`。
/// update で変更できるのは title / tags / body（+ updatedAt）のみ（ADR-003）。
class MemoStore {
  static const schemaVersion = 1;

  final JsonFileStore _store;

  MemoStore(File file) : _store = JsonFileStore(file);

  /// デフォルトの保存先（`~/.moost/v1/memos.json`）を使う。
  factory MemoStore.defaultLocation() {
    final home = Platform.environment['HOME'] ?? '';
    return MemoStore(File('$home/.moost/v1/memos.json'));
  }

  Future<List<Memo>> load() async {
    final json = await _store.read();
    if (json == null) {
      return [];
    }
    final rawMemos = json['memos'];
    if (rawMemos is! List<Object?>) {
      return [];
    }
    final memos = <Memo>[];
    for (final raw in rawMemos) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      try {
        memos.add(Memo.fromJson(raw));
      } on Object {
        // 壊れた 1 件のためにストア全体を捨てない
        continue;
      }
    }
    return memos;
  }

  Future<void> add(Memo memo) async {
    final memos = await load();
    memos.add(memo);
    await _save(memos);
  }

  /// 可変フィールドだけを更新する。対象が見つからなければ false。
  Future<bool> update(
    String id, {
    String? title,
    List<String>? tags,
    String? body,
  }) async {
    final memos = await load();
    final index = memos.indexWhere((memo) => memo.id == id);
    if (index < 0) {
      return false;
    }
    memos[index] = memos[index].updateUserFields(
      title: title,
      tags: tags,
      body: body,
      updatedAt: DateTime.now().toUtc(),
    );
    await _save(memos);
    return true;
  }

  Future<bool> delete(String id) async {
    final memos = await load();
    final before = memos.length;
    memos.removeWhere((memo) => memo.id == id);
    if (memos.length == before) {
      return false;
    }
    await _save(memos);
    return true;
  }

  Future<void> _save(List<Memo> memos) => _store.write({
        'schemaVersion': schemaVersion,
        'memos': memos.map((memo) => memo.toJson()).toList(),
      });
}
