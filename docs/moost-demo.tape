# moost 開発工程デモ（VHS）
# 対象: macOS native 版（Swift/AppKit・MCP 内蔵）
Output "/tmp/moost-dev-demo.gif"
Output "/tmp/moost-dev-demo.mp4"
Set Width 1100
Set Height 560
Set FontSize 19
Set Padding 24
Set Margin 24
Set Framerate 15
Set Theme "Dracula"
Set TypingSpeed 25ms

# 0. リポジトリへ移動
Type `cd ~/IdeaProjects/moost`
Enter
Sleep 1s

# 1. 開発履歴
Type `git --no-pager log --oneline -8`
Enter
Sleep 2s

# 2. バージョン確認（プラットフォーム記号規約）
Type `moost --version`
Enter
Sleep 1s

# 3. アプリ内蔵 MCP サーバー（JSON-RPC 2.0 over stdio）
Type `moost mcp`
Enter
Sleep 1s

Type `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"vhs-demo","version":"1.0"}}}`
Enter
Sleep 1s

Type `{"jsonrpc":"2.0","method":"notifications/initialized"}`
Enter
Sleep 500ms

Type `{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}`
Enter
Sleep 1s

# EOF（Ctrl+D）でサーバー終了
Ctrl+D
Sleep 2s

# 4. ビルド（開発工程）
Type `cd apps/macos && swift build`
Enter
Sleep 6s
