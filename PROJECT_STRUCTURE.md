# Project Structure

```text
ThinkShiftAI/
├── README.md                     Project overview and setup
├── ARCHITECTURE.md               How the pieces talk to each other
├── PROJECT_STRUCTURE.md          This file
│
├── backend/                      Python backend (Flask + Agora Agent SDK)
│   ├── thinkshift_app_sdk.py     Entry point: Flask app and HTTP routes only
│   ├── agora_client.py           Everything Agora: tokens, agent config, sessions, REST calls
│   ├── constants.py              All config and constants (reads .env), including the system prompt
│   ├── .env.example              Template for required environment variables
│   ├── .env                      Your local secrets (git-ignored)
│   └── .gitignore
│
└── frontend_mobile/              Flutter app (Android target)
    ├── pubspec.yaml              Dependencies: agora_rtc_engine, http, permission_handler
    ├── lib/
    │   ├── main.dart             App entry: MaterialApp → VoiceScreen
    │   ├── config.example.dart   Template for config.dart (committed)
    │   ├── config.dart           Backend URL, channel name, local uid (git-ignored, copy from the template)
    │   ├── thinkshift_api.dart   HTTP client for /token, /start-agent, /stop-agent
    │   └── voice_screen.dart     Main screen: voice state machine, Agora RTC engine, UI
    ├── android/                  Android host project (permissions in AndroidManifest.xml)
    └── test/                     Widget tests
```

## Backend

The backend is split so each file has one job:

| File | Responsibility | Depends on |
|---|---|---|
| [constants.py](backend/constants.py) | Loads `.env`, then defines every setting: credentials, region, models, uids, timeouts, voice-detection timings, filler words, LLM settings, prompts | `python-dotenv`, `agora_agent.Area` |
| [agora_client.py](backend/agora_client.py) | Runs a background asyncio loop for the async SDK, builds the agent, starts/stops/interrupts agents, generates tokens | `constants`, `agora-agents`, `agora-token-builder`, `httpx`, `requests` |
| [thinkshift_app_sdk.py](backend/thinkshift_app_sdk.py) | Flask routes: checks input, calls `agora_client`, logs, formats JSON responses | `agora_client`, `constants`, `flask`, `flask-cors` |

**What to change where:**

* The companion's personality or rules → `SYSTEM_PROMPT`, `GREETING`, `FAILURE` in `constants.py`
* Voices, models or language → `.env` (`SDK_*`, `ASR_LANGUAGE`), with defaults in `constants.py`
* How fast the agent decides you've stopped talking → `VAD_*` in `constants.py`
* What the agent says while thinking → `FILLER_*` in `constants.py`
* A new endpoint → add a function in `agora_client.py` and a route in `thinkshift_app_sdk.py`

## Mobile app

| File | Responsibility |
|---|---|
| [config.dart](frontend_mobile/lib/config.dart) | `kBackendBaseUrl`, `kChannelName` (`thinkshift_room_1`), `kLocalUid` (`12345`, must not be `0` or the agent's `999`) |
| [thinkshift_api.dart](frontend_mobile/lib/thinkshift_api.dart) | `getToken`, `startAgent`, `stopAgent` wrappers with timeouts |
| [voice_screen.dart](frontend_mobile/lib/voice_screen.dart) | `VoiceState` machine (`idle → connecting → joining → startingAgent → listening → ending`), RTC engine setup and events, and the UI (AI orb, wave bars, suggestion pills, mic button) |
