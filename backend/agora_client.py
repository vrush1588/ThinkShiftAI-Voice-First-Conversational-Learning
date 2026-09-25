"""Agora client: tokens, Agent SDK sessions, and REST stop fallback."""

import time
import base64
import asyncio
import threading

import httpx
import requests
from agora_token_builder import RtcTokenBuilder, RtmTokenBuilder
from agora_token_builder.RtmTokenBuilder import Role_Rtm_User
from agora_agent import Agent, AsyncAgora, DeepgramSTT, MiniMaxTTS, OpenAI

from constants import (
    AGORA_APP_ID, AGORA_APP_CERT, AGORA_CUSTOMER_ID, AGORA_CUSTOMER_SECRET,
    AGORA_AREA, AREA_BY_NAME, AGORA_API_BASE_URL,
    ASR_MODEL, ASR_LANGUAGE, LLM_MODEL, TTS_MODEL, TTS_VOICE_ID,
    AGENT_UID, TOKEN_EXPIRY_SECONDS, RTC_ROLE_PUBLISHER, AGENT_IDLE_TIMEOUT_SECONDS,
    SDK_CALL_TIMEOUT_SECONDS, HTTPX_TIMEOUT_SECONDS, REST_STOP_TIMEOUT_SECONDS,
    VAD_SPEECH_THRESHOLD, VAD_INTERRUPT_DURATION_MS, VAD_PREFIX_PADDING_MS,
    VAD_SILENCE_DURATION_MS,
    LLM_MAX_HISTORY, LLM_MAX_TOKENS, LLM_TEMPERATURE, LLM_TOP_P,
    SYSTEM_PROMPT, GREETING, FAILURE,
    AUDIO_SCENARIO, FILLER_WAIT_MS, FILLER_PHRASES, FILLER_PROMPT,
)


# ── One background event loop for the async SDK ──────────────────────────
# Flask is sync; the SDK is async. All SDK calls run on this single loop so
# the httpx client and stored sessions always live on the same loop.
_loop = asyncio.new_event_loop()
threading.Thread(target=_loop.run_forever, daemon=True).start()


def _run(coro, timeout=SDK_CALL_TIMEOUT_SECONDS):
    return asyncio.run_coroutine_threadsafe(coro, _loop).result(timeout=timeout)


async def _make_client():
    return AsyncAgora(
        area=AREA_BY_NAME[AGORA_AREA],
        app_id=AGORA_APP_ID,
        app_certificate=AGORA_APP_CERT,
        httpx_client=httpx.AsyncClient(timeout=httpx.Timeout(HTTPX_TIMEOUT_SECONDS)),
    )

_client = _run(_make_client())
_sessions = {}  # agent_id -> session


def _build_agent():
    return (
        Agent(
            client=_client,
            turn_detection={
                "config": {
                    "speech_threshold": VAD_SPEECH_THRESHOLD,
                    "start_of_speech": {
                        "mode": "vad",
                        "vad_config": {
                            "interrupt_duration_ms": VAD_INTERRUPT_DURATION_MS,
                            "prefix_padding_ms": VAD_PREFIX_PADDING_MS,
                        },
                    },
                    "end_of_speech": {
                        "mode": "vad",
                        "vad_config": {"silence_duration_ms": VAD_SILENCE_DURATION_MS},
                    },
                },
            },
            interruption={"enable": True, "mode": "start_of_speech"},
            filler_words={
                "enable": True,
                "trigger": {
                    "mode": "fixed_time",
                    "fixed_time_config": {"response_wait_ms": FILLER_WAIT_MS},
                },
                "content": {
                    "mode": "generated",
                    "static_config": {
                        "phrases": FILLER_PHRASES,
                        "selection_rule": "shuffle",
                    },
                    "generated_config": {
                        "prompt": FILLER_PROMPT,
                        "fallback_strategy": "static",
                    },
                },
            },
            advanced_features={"enable_rtm": True},
            parameters={
                "audio_scenario": AUDIO_SCENARIO,
                "data_channel": "rtm",
                "enable_error_message": True,
                "enable_metrics": True,
            },
        )
        .with_stt(DeepgramSTT(model=ASR_MODEL, language=ASR_LANGUAGE))
        .with_llm(
            OpenAI(
                model=LLM_MODEL,
                system_messages=[{"role": "system", "content": SYSTEM_PROMPT}],
                greeting_message=GREETING,
                failure_message=FAILURE,
                max_history=LLM_MAX_HISTORY,
                max_tokens=LLM_MAX_TOKENS,
                temperature=LLM_TEMPERATURE,
                top_p=LLM_TOP_P,
            )
        )
        .with_tts(MiniMaxTTS(model=TTS_MODEL, voice_id=TTS_VOICE_ID))
    )


def _basic_auth_header():
    raw = f"{AGORA_CUSTOMER_ID}:{AGORA_CUSTOMER_SECRET}"
    encoded = base64.b64encode(raw.encode()).decode()
    return {"Authorization": f"Basic {encoded}", "Content-Type": "application/json"}


def build_tokens(channel_name, uid):
    """Return (rtc_token, rtm_token) for the given channel and uid."""
    privilege_expire_ts = int(time.time()) + TOKEN_EXPIRY_SECONDS
    token = RtcTokenBuilder.buildTokenWithUid(
        AGORA_APP_ID, AGORA_APP_CERT, channel_name, uid,
        RTC_ROLE_PUBLISHER, privilege_expire_ts,
    )
    rtm_token = RtmTokenBuilder.buildToken(
        AGORA_APP_ID, AGORA_APP_CERT, str(uid), Role_Rtm_User, privilege_expire_ts,
    )
    return token, rtm_token


def start_agent(channel_name, remote_uids):
    """Start an agent in the channel and return its agent_id (or None)."""
    async def _start():
        session = _build_agent().create_async_session(
            channel=channel_name,
            agent_uid=str(AGENT_UID),
            remote_uids=remote_uids,
            name=f"{channel_name}-{int(time.time())}",
            idle_timeout=AGENT_IDLE_TIMEOUT_SECONDS,
            expires_in=TOKEN_EXPIRY_SECONDS,
            debug=False,
        )
        agent_id = await session.start()
        return session, agent_id

    session, agent_id = _run(_start())
    if agent_id:
        _sessions[agent_id] = session
    return agent_id


def interrupt_agent(agent_id):
    """Stop the agent's current speech (it keeps listening).
    Returns the requests.Response from Agora."""
    # REST instead of session.interrupt(): agora-agents 2.8.1 sends that
    # request with no body and Agora rejects it (400 InvalidRequestBody).
    url = f"{AGORA_API_BASE_URL}/projects/{AGORA_APP_ID}/agents/{agent_id}/interrupt"
    return requests.post(url, headers=_basic_auth_header(), json={},
                         timeout=REST_STOP_TIMEOUT_SECONDS)


def stop_agent(agent_id):
    """Stop the agent. Returns True if stopped via the in-memory session,
    otherwise returns the REST fallback's requests.Response."""
    session = _sessions.pop(agent_id, None)
    if session is not None:
        try:
            _run(session.stop())
            return True
        except Exception as e:
            print("[agora_client] session.stop failed, trying REST:", repr(e), flush=True)

    # Fallback: session not in memory (e.g. server restarted).
    url = f"{AGORA_API_BASE_URL}/projects/{AGORA_APP_ID}/agents/{agent_id}/leave"
    return requests.post(url, headers=_basic_auth_header(), timeout=REST_STOP_TIMEOUT_SECONDS)
