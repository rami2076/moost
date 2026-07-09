import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late SummaryCache cache;

  setUp(() => cache = SummaryCache());

  test('returns null on miss', () {
    expect(cache.get('s1', SummaryScope.full, 1), isNull);
  });

  test('stores and retrieves by session and scope', () {
    cache.put('s1', SummaryScope.full, 1, 'full summary');
    cache.put('s1', SummaryScope.recent, 3, 'recent-3 summary');

    expect(cache.get('s1', SummaryScope.full, 1), 'full summary');
    expect(cache.get('s1', SummaryScope.recent, 3), 'recent-3 summary');
  });

  test('rally count is part of the key for recent scope', () {
    cache.put('s1', SummaryScope.recent, 1, 'one');
    expect(cache.get('s1', SummaryScope.recent, 1), 'one');
    // 別のラリー数は別キー
    expect(cache.get('s1', SummaryScope.recent, 5), isNull);
  });

  test('rally count is ignored for full scope', () {
    cache.put('s1', SummaryScope.full, 1, 'full');
    // full はラリー数に依存しない
    expect(cache.get('s1', SummaryScope.full, 99), 'full');
  });

  test('sessions are isolated', () {
    cache.put('s1', SummaryScope.full, 1, 'a');
    expect(cache.get('s2', SummaryScope.full, 1), isNull);
  });

  test('clear empties the cache', () {
    cache.put('s1', SummaryScope.full, 1, 'a');
    cache.clear();
    expect(cache.get('s1', SummaryScope.full, 1), isNull);
  });
}
