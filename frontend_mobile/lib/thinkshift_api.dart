import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

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

  /// Sends a homework photo; the backend describes it and the agent talks about it.
  /// Returns the backend's description of the photo.
  Future<String> analyzeHomework(String agentId, XFile image) async {
    final uri = Uri.parse("$baseUrl/analyze-homework");
    final request = http.MultipartRequest("POST", uri)
      ..fields['agent_id'] = agentId
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        await image.readAsBytes(),
        filename: image.name,
        contentType: MediaType.parse(image.mimeType ?? _mimeFromName(image.name)),
      ));
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception("Homework upload failed (${resp.statusCode}): ${resp.body}");
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['description'] as String? ?? "";
  }

  static String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith(".png")) return "image/png";
    if (lower.endsWith(".webp")) return "image/webp";
    if (lower.endsWith(".heic")) return "image/heic";
    return "image/jpeg";
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
