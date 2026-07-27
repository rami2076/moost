import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:moost_mcp_server/moost_mcp_server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// [MoostMcpServer] を実プロセスなしでテストするための、
/// メモリ上で完結するクライアント・サーバー間チャネル。
class TestEnvironment {
  final _clientController = StreamController<String>();
  final _serverController = StreamController<String>();

  late final StreamChannel<String> _clientChannel =
      StreamChannel<String>.withCloseGuarantee(
    _serverController.stream,
    _clientController.sink,
  );
  late final StreamChannel<String> _serverChannel =
      StreamChannel<String>.withCloseGuarantee(
    _clientController.stream,
    _serverController.sink,
  );

  final TestMCPClient client = TestMCPClient();
  late final MoostMcpServer server;
  late final ServerConnection connection;

  TestEnvironment(MoostMcpServer Function(StreamChannel<String>) createServer) {
    server = createServer(_serverChannel);
    connection = client.connectServer(_clientChannel);
    addTearDown(shutdown);
  }

  Future<void> initialize() async {
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized(InitializedNotification());
    await server.initialized;
  }

  Future<void> shutdown() async {
    await client.shutdown();
    await server.shutdown();
  }
}

base class TestMCPClient extends MCPClient {
  TestMCPClient() : super(Implementation(name: 'test client', version: '0.1.0'));
}
