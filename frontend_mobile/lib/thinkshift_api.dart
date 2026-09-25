import 'dart:convert';
import 'package:http/http.dart' as http;

class TokenResult {
  final String token;
  final String appId;
  final int uid;
  final String? rtmToken;

  TokenResult({required this.token, required this.appId, required this.uid, this.rtmToken});
}

class StartAgentResult {
  final bool httpOk;
  final int status;
  final String? agentId;
  final String rawBody;

  StartAgentResult({
    required this.httpOk,
    required this.status,
    required this.agentId,
    required this.rawBody,
  });
}

class ThinkShiftApi {
  final String baseUrl;

  ThinkShiftApi(this.baseUrl);

  Future<TokenResult> getToken(String channel, int uid) async {
    final uri = Uri.parse("$baseUrl/token?channel=$channel&uid=$uid");
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception("Token request failed (${resp.statusCode}): ${resp.body}");
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final token = json['token'] as String?;
    final appId = json['app_id'] as String?;
    if (token == null || appId == null) {
      throw Exception("Token response missing 'token' or 'app_id': ${resp.body}");
    }

    return TokenResult(token: token, appId: appId, uid: uid, rtmToken: json['rtm_token'] as String?);
  }

  Future<StartAgentResult> startAgent(String channel) async {
    final uri = Uri.parse("$baseUrl/start-agent");
    final resp = await http
        .post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"channel": channel}),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> root;
    try {
      root = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return StartAgentResult(
        httpOk: false,
        status: resp.statusCode,
        agentId: null,
        rawBody: resp.body,
      );
    }

    final status = (root['status'] as num?)?.toInt() ?? resp.statusCode;
    final agora = root['agora_response'] as Map<String, dynamic>?;
    final agentId = agora?['agent_id'] as String? ??
        agora?['agentId'] as String? ??
        agora?['id'] as String?;

    final httpOk = resp.statusCode == 200 && status >= 200 && status < 300 && agentId != null;

    return StartAgentResult(
      httpOk: httpOk,
      status: status,
      agentId: agentId,
      rawBody: resp.body,
    );
  }

  Future<void> stopAgent(String agentId) async {
    try {
      final uri = Uri.parse("$baseUrl/stop-agent");
      await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"agent_id": agentId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort cleanup — ignore failures, mirrors the reference app.
    }
  }
}
