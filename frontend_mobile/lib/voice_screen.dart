import 'dart:async';
import 'dart:math' as math;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'thinkshift_api.dart';

enum VoiceState { idle, connecting, joining, startingAgent, listening, ending, error }

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with TickerProviderStateMixin {
  final _api = ThinkShiftApi(kBackendBaseUrl);

  late final AnimationController _floatController =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _waveController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController _rippleController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();

  String? _suggestedPrompt;

  VoiceState _state = VoiceState.idle;
  String _status = "Tap the button to start a conversation with ThinkShift.";
  RtcEngine? _engine;
  String? _agentId;
  Timer? _joinTimeoutTimer;

  bool get _buttonEnabled =>
      _state == VoiceState.idle || _state == VoiceState.listening || _state == VoiceState.error;

  bool get _isBusy =>
      _state == VoiceState.connecting ||
      _state == VoiceState.joining ||
      _state == VoiceState.startingAgent ||
      _state == VoiceState.ending;

  String get _buttonLabel => switch (_state) {
        VoiceState.listening => "Listening · Tap to end",
        VoiceState.connecting || VoiceState.joining || VoiceState.startingAgent => "Connecting...",
        VoiceState.ending => "Ending...",
        VoiceState.error => "Tap to retry",
        VoiceState.idle => "Tap to talk",
      };

  @override
  void dispose() {
    _floatController.dispose();
    _waveController.dispose();
    _rippleController.dispose();
    _joinTimeoutTimer?.cancel();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  void _setState(VoiceState state, String status) {
    _log("state -> $state ($status)");
    if (!mounted) return;
    setState(() {
      _state = state;
      _status = status;
    });
  }

  void _log(String message) {
    debugPrint("[ThinkShift] $message");
  }

  Future<void> _onButtonPressed() async {
    if (_state == VoiceState.listening) {
      await _end();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (permission.isPermanentlyDenied) {
        _setState(VoiceState.error,
            "Microphone permission is needed to talk. Please enable it in Settings.");
      } else {
        _setState(VoiceState.error, "Microphone permission is needed to talk.");
      }
      return;
    }

    _setState(VoiceState.connecting, "Connecting...");
    _log("getToken(channel=$kChannelName, uid=$kLocalUid) from $kBackendBaseUrl");
    final TokenResult tokenResult;
    try {
      tokenResult = await _api.getToken(kChannelName, kLocalUid);
      _log("getToken ok: app_id=${tokenResult.appId}, uid=${tokenResult.uid}");
    } catch (e) {
      _log("getToken FAILED: $e");
      _setState(VoiceState.error, "Could not connect. Check backend URL and Wi-Fi.\n$e");
      return;
    }

    try {
      await _initEngineIfNeeded(tokenResult.appId);
    } catch (e) {
      _setState(VoiceState.error, "Voice engine failed to start.\n$e");
      return;
    }

    _setState(VoiceState.joining, "Joining channel...");
    _log("joinChannel(channel=$kChannelName, uid=$kLocalUid)");
    try {
      await _engine!.joinChannel(
        token: tokenResult.token,
        channelId: kChannelName,
        uid: kLocalUid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      _log("joinChannel FAILED: $e");
      _setState(VoiceState.error, "Could not join the voice channel.\n$e");
      return;
    }

    _joinTimeoutTimer?.cancel();
    _joinTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_state == VoiceState.joining) {
        _engine?.leaveChannel();
        _setState(VoiceState.error, "Timed out joining the channel. Check your connection.");
      }
    });
  }

  Future<void> _initEngineIfNeeded(String appId) async {
    if (_engine != null) return;

    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        _log("onJoinChannelSuccess: localUid=${connection.localUid} elapsed=${elapsed}ms");
        _onJoinChannelSuccess();
      },
      onLeaveChannel: (connection, stats) => _log("onLeaveChannel: stats=${stats.toJson()}"),
      onUserJoined: (connection, remoteUid, elapsed) {
        _log("onUserJoined: remoteUid=$remoteUid elapsed=${elapsed}ms (this should be the agent, uid 999)");
        _onRemoteUserJoined(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) =>
          _log("onUserOffline: remoteUid=$remoteUid reason=$reason (agent left the channel)"),
      onConnectionStateChanged: (connection, state, reason) =>
          _log("onConnectionStateChanged: state=$state reason=$reason"),
      onRemoteAudioStateChanged: (connection, remoteUid, state, reason, elapsed) => _log(
          "onRemoteAudioStateChanged: remoteUid=$remoteUid state=$state reason=$reason (state=decoding means the agent's audio is actually arriving)"),
      onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
        if (speakers.isEmpty) return;
        final summary = speakers.map((s) => "uid=${s.uid ?? 0}:vol=${s.volume ?? 0}").join(", ");
        _log("onAudioVolumeIndication: $summary (uid=0 is you; non-zero means mic/agent audio is flowing)");
      },
      onError: (err, msg) => _onEngineError(err, msg),
    ));

    await engine.enableAudio();
    try {
      await engine.enableAudioVolumeIndication(interval: 1000, smooth: 3, reportVad: true);
    } catch (e) {
      _log("enableAudioVolumeIndication failed (non-fatal): $e");
    }
    try {
      await engine.setEnableSpeakerphone(true);
    } catch (e) {
      // Some devices/emulators don't support explicit speaker routing and
      // throw here even though audio still plays fine on the default route.
      // Non-fatal: don't let this block the rest of the session.
      _log("setEnableSpeakerphone failed (non-fatal): $e");
    }

    _engine = engine;
  }

  void _onJoinChannelSuccess() {
    _joinTimeoutTimer?.cancel();
    _setState(VoiceState.startingAgent, "Joined. Bringing in the assistant...");

    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted || _state != VoiceState.startingAgent) return;

      _log("startAgent(channel=$kChannelName)");
      final StartAgentResult result;
      try {
        result = await _api.startAgent(kChannelName);
        _log("startAgent response: httpOk=${result.httpOk} status=${result.status} agentId=${result.agentId} body=${result.rawBody}");
      } catch (e) {
        _log("startAgent FAILED: $e");
        await _engine?.leaveChannel();
        _setState(VoiceState.error, "Assistant could not join.\n$e");
        return;
      }

      if (result.httpOk && result.agentId != null) {
        _agentId = result.agentId;
        _setState(VoiceState.listening, "Listening... you can start speaking.");
      } else {
        await _engine?.leaveChannel();
        _setState(VoiceState.error,
            "Assistant could not join (status ${result.status}).\n${result.rawBody.substring(0, result.rawBody.length > 200 ? 200 : result.rawBody.length)}");
      }
    });
  }

  void _onRemoteUserJoined(int remoteUid) {
    _engine?.adjustUserPlaybackSignalVolume(uid: remoteUid, volume: 400);
    _log("REMOTE USER JOINED: uid=$remoteUid");
    if (_state == VoiceState.startingAgent) {
      _setState(VoiceState.startingAgent, "Assistant connected. Listening...");
    }
  }

  void _onEngineError(ErrorCodeType err, String msg) {
    _log("onError: err=$err msg=$msg");
    _engine?.leaveChannel();
    _setState(VoiceState.error, "Agora error: $err\n$msg");
  }

  Future<void> _end() async {
    _setState(VoiceState.ending, "Ending...");
    final agentId = _agentId;
    if (agentId != null) {
      _log("stopAgent(agentId=$agentId)");
      await _api.stopAgent(agentId);
    }
    await _engine?.leaveChannel();
    _agentId = null;
    _setState(VoiceState.idle, "Conversation ended.");
  }

  void _onSuggestionTapped(String prompt) {
    setState(() => _suggestedPrompt = prompt);
    if (_state == VoiceState.idle || _state == VoiceState.error) {
      _start();
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text("$feature coming soon")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildGreetingCard(),
                  Expanded(child: _buildOrbVisualizer()),
                  _buildSuggestions(),
                  const SizedBox(height: 12),
                  _buildVoiceControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _CircleIconButton(
          icon: Icons.menu_rounded,
          tooltip: "Menu",
          onPressed: () => _showComingSoon("Menu"),
        ),
        Expanded(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "ThinkShift",
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: _Palette.slate900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _Palette.indigo500,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: _Palette.indigo500.withValues(alpha: 0.8), blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
              const Text(
                "Think. Explore. Discover.",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  color: _Palette.slate400,
                ),
              ),
            ],
          ),
        ),
        _CircleIconButton(
          icon: Icons.light_mode_outlined,
          tooltip: "Settings",
          onPressed: () => _showComingSoon("Settings"),
        ),
      ],
    );
  }

  Widget _buildGreetingCard() {
    final String subtitle;
    if (_state == VoiceState.listening && _suggestedPrompt != null) {
      subtitle = "Try asking: “$_suggestedPrompt”";
    } else if (_state == VoiceState.idle && _agentId == null && !_status.startsWith("Conversation ended")) {
      subtitle = "Ask me any question!";
    } else {
      subtitle = _status;
    }

    return _GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  "Hi! I’m ThinkShift",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: _Palette.slate800,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text("\u{1F44B}", style: TextStyle(fontSize: 24)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Ready to explore something interesting?",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: _Palette.slate700,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              subtitle,
              key: ValueKey(subtitle),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: _state == VoiceState.error ? _Palette.error : _Palette.slate500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrbVisualizer() {
    final active = _state == VoiceState.listening;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 300,
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ambient back glow
              Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFA5B4FC).withValues(alpha: active ? 0.45 : 0.3),
                      const Color(0xFFFDA4AF).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              // Soft floor shadow
              Positioned(
                bottom: 42,
                child: Container(
                  width: 96,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: _Palette.slate900.withValues(alpha: 0.12),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WaveBars(animation: _waveController, active: active, mirrored: false),
                  const SizedBox(width: 12),
                  AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, child) {
                      final t = math.sin(_floatController.value * 2 * math.pi);
                      return Transform.translate(
                        offset: Offset(0, -4 - 4 * t),
                        child: Transform.scale(scale: 1.01 + 0.01 * t, child: child),
                      );
                    },
                    child: GestureDetector(
                      onTap: _buttonEnabled ? _onButtonPressed : null,
                      child: const _AiOrb(size: 128),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _WaveBars(animation: _waveController, active: active, mirrored: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SuggestionPill(
                emoji: "✨",
                label: "Why is the sky blue?",
                onTap: () => _onSuggestionTapped("Why is the sky blue?"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SuggestionPill(
                emoji: "\u{1FA90}",
                label: "Tell me about space",
                onTap: () => _onSuggestionTapped("Tell me about space"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SuggestionPill(
          emoji: "\u{1F312}",
          label: "Why do eclipses happen?",
          onTap: () => _onSuggestionTapped("Why do eclipses happen?"),
        ),
      ],
    );
  }

  Widget _buildVoiceControls() {
    final listening = _state == VoiceState.listening;
    return Column(
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radiating ripple ring
              AnimatedBuilder(
                animation: _rippleController,
                builder: (context, _) {
                  final v = Curves.easeOut.transform(_rippleController.value);
                  return Transform.scale(
                    scale: 0.85 + 0.55 * v,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _Palette.indigo400.withValues(alpha: (listening ? 0.9 : 0.5) * (1 - v)),
                          width: listening ? 2 : 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFC7D2FE).withValues(alpha: 0.3),
                  border: Border.all(color: _Palette.indigo300.withValues(alpha: 0.35)),
                ),
              ),
              AnimatedScale(
                scale: listening ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: _MicButton(
                  listening: listening,
                  busy: _isBusy,
                  onPressed: _buttonEnabled ? _onButtonPressed : null,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: "Keyboard input",
                onPressed: () => _showComingSoon("Keyboard input"),
                icon: const Icon(Icons.keyboard_outlined, color: _Palette.slate400),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    final pulse = listening
                        ? 0.6 + 0.4 * (0.5 + 0.5 * math.cos(_waveController.value * 2 * math.pi))
                        : 1.0;
                    return Opacity(opacity: pulse, child: child);
                  },
                  child: Text(
                    _buttonLabel.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: listening ? _Palette.indigo600 : _Palette.slate500,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: "History",
                onPressed: () => _showComingSoon("History"),
                icon: const Icon(Icons.access_time_rounded, color: _Palette.slate400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: const Color(0xFFE2E8F0).withValues(alpha: 0.6))),
          ),
          child: const _BrandMantra(),
        ),
      ],
    );
  }
}

class _Palette {
  static const background = Color(0xFFF6F8FD);
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const brand500 = Color(0xFF4379EE);
  static const blue400 = Color(0xFF60A5FA);
  static const error = Color(0xFFDC2626);
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  Widget _blob(Alignment center, Color color, double radius) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFF), Color(0xFFF4F7FF), Color(0xFFEBF2FF)],
              ),
            ),
          ),
        ),
        _blob(const Alignment(-0.7, -0.76), const Color(0xCCFEF0DE), 0.9),
        _blob(const Alignment(0.7, -0.64), const Color(0xBFD7E9FF), 1.0),
        _blob(const Alignment(0, 0.1), const Color(0x80E2DBFF), 1.1),
        _blob(const Alignment(0.6, 0.7), const Color(0x99C8E8FF), 0.9),
      ],
    );
  }
}

class _GlassContainer extends StatelessWidget {
  const _GlassContainer({required this.child, required this.borderRadius, required this.padding});

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(color: Color(0x14253C74), blurRadius: 36, offset: Offset(0, 12), spreadRadius: -8),
          BoxShadow(color: Color(0x0A253C74), blurRadius: 10, offset: Offset(0, 3), spreadRadius: -2),
        ],
      ),
      child: child,
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.7),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.8))),
        elevation: 1,
        shadowColor: const Color(0x33253C74),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: _Palette.slate600),
          ),
        ),
      ),
    );
  }
}

class _AiOrb extends StatelessWidget {
  const _AiOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.5),
          radius: 1.0,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFD1F1FF),
            Color(0xFFA6D5FF),
            Color(0xFFD6B8FF),
            Color(0xFFFEC7D7),
            Color(0xFFFFD7A8),
          ],
          stops: [0.0, 0.2, 0.4, 0.68, 0.88, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6385FF).withValues(alpha: 0.42),
            blurRadius: 45,
            offset: const Offset(0, 18),
            spreadRadius: -8,
          ),
          BoxShadow(
            color: const Color(0xFFEC8FCE).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner glow
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.65,
                    colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            // Bottom inner shade (Flutter has no inset shadows)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, const Color(0xFF5B7EF8).withValues(alpha: 0.18)],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
            ),
            // Top-left specular flare
            Positioned(
              top: -size * 0.05,
              left: -size * 0.05,
              child: Container(
                width: size * 0.5,
                height: size * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            // Bottom-right rose highlight
            Positioned(
              bottom: size * 0.04,
              right: size * 0.08,
              child: Container(
                width: size * 0.4,
                height: size * 0.26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size),
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFECDD3).withValues(alpha: 0.5),
                      const Color(0xFFFECDD3).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              "AI",
              style: TextStyle(
                fontSize: size * 0.19,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: _Palette.slate800.withValues(alpha: 0.85),
                shadows: [
                  Shadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveBars extends StatelessWidget {
  const _WaveBars({required this.animation, required this.active, required this.mirrored});

  final Animation<double> animation;
  final bool active;
  final bool mirrored;

  // (max height, phase delay, color). A null delay means the bar is static.
  static const _bars = <(double, double?, Color)>[
    (12, 0.07, Color(0xB3818CF8)),
    (20, 0.14, Color(0xB3818CF8)),
    (32, 0.21, Color(0xCC60A5FA)),
    (16, 0.29, Color(0xB3818CF8)),
    (24, 0.43, Color(0xCCA5B4FC)),
    (8, null, Color(0x99A5B4FC)),
  ];

  @override
  Widget build(BuildContext context) {
    final bars = mirrored ? _bars.reversed.toList() : _bars;
    return AnimatedOpacity(
      opacity: active ? 1.0 : 0.6,
      duration: const Duration(milliseconds: 300),
      child: SizedBox(
        height: 48,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (maxHeight, delay, color) in bars)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      width: 3,
                      height: delay == null ? maxHeight : _heightFor(maxHeight, delay),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _heightFor(double maxHeight, double delay) {
    final t = (animation.value + delay) % 1.0;
    final wave = 0.5 - 0.5 * math.cos(2 * math.pi * t);
    final peak = active ? maxHeight * 1.4 : maxHeight;
    return peak * (0.12 + 0.88 * wave);
  }
}

class _SuggestionPill extends StatelessWidget {
  const _SuggestionPill({required this.emoji, required this.label, required this.onTap});

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: const [
          BoxShadow(color: Color(0x1221386C), blurRadius: 14, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x0A21386C), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _Palette.slate700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.busy, required this.onPressed});

  final bool listening;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: listening ? "End conversation" : "Tap to talk",
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [_Palette.indigo600, _Palette.brand500, _Palette.blue400],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
            boxShadow: [
              BoxShadow(
                color: _Palette.brand500.withValues(alpha: listening ? 0.65 : 0.5),
                blurRadius: listening ? 28 : 25,
                offset: const Offset(0, 10),
                spreadRadius: -5,
              ),
              if (listening) BoxShadow(color: _Palette.indigo300.withValues(alpha: 0.6), spreadRadius: 4),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Icon(
                    listening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 28,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

class _BrandMantra extends StatelessWidget {
  const _BrandMantra();

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
      color: _Palette.slate400,
    );
    const arrow = TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _Palette.indigo400);
    return const FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: "VOICE FIRST"),
            TextSpan(text: "  →  ", style: arrow),
            TextSpan(text: "ASK"),
            TextSpan(text: "  →  ", style: arrow),
            TextSpan(text: "THINK"),
            TextSpan(text: "  →  ", style: arrow),
            TextSpan(
              text: "DISCOVER",
              style: TextStyle(fontWeight: FontWeight.w800, color: _Palette.slate600),
            ),
          ],
        ),
      ),
    );
  }
}
