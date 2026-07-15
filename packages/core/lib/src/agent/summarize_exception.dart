/// 要約実行に失敗したときに投げる。ユーザーに見せられるメッセージを持つ。
class SummarizeException implements Exception {
  final String message;

  const SummarizeException(this.message);

  @override
  String toString() => 'SummarizeException: $message';
}
