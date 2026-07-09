# Changelog

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### Added

- packages/core: フェーズ 1 の初期実装
  - 直近セッション一覧の取得（history.jsonl 集約 + ai-title 末尾走査）
  - メモ CRUD（`~/.moost/v1/memos.json`、アトミック書き込み・破損時退避）
  - 復帰コマンドの組み立て（シェルエスケープ込み）
  - セッション要約（`claude -p`、直近 N ラリー抜粋 / 全体 fork の 2 モード）
  - CLI サンプル（一覧表示・メモ登録・復帰コマンド出力）
