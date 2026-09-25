"""ThinkShift AI backend server — Agora Agent SDK version (for testing).

Endpoints: /token, /start-agent, /stop-agent, /interrupt-agent.
The agent is started the way Agora's agent-quickstart-android template does it:

  - uses the `agora-agents` SDK instead of a hand-built REST payload
  - Agora-managed ASR/LLM/TTS (SDK generates a `preset`) — no pipeline_id,
    no resource_id, no vendor API keys
  - the SDK generates the agent's own token from App ID + certificate
    (same as the template — we don't build it by hand)

Layout:
  constants.py     — all config and constants
  agora_client.py  — Agora tokens, SDK sessions, REST stop fallback
  this file        — Flask routes only

Install:  pip install agora-agents==2.8.1
"""

import time
import functools

from flask import Flask, request, jsonify
from flask_cors import CORS

import agora_client
from constants import (
    AGORA_APP_ID, AGORA_AREA, SERVER_HOST, SERVER_PORT,
    ASR_MODEL, LLM_MODEL, TTS_MODEL, TTS_VOICE_ID,
)

print = functools.partial(print, flush=True)

app = Flask(__name__)
CORS(app)


# ── 1) Token endpoint (same response shape as thinkshift_app.py) ─────────
@app.route("/token", methods=["GET"])
def get_token():
    channel_name = request.args.get("channel")
    if not channel_name:
        return jsonify({"error": "channel is required"}), 400
    try:
        uid = int(request.args.get("uid", 0))
    except ValueError:
        return jsonify({"error": "uid must be an integer"}), 400

    token, rtm_token = agora_client.build_tokens(channel_name, uid)
    print(f"[/token] channel={channel_name} uid={uid} token_prefix={token[:10]}")
    return jsonify({
        "token": token, "app_id": AGORA_APP_ID,
        "channel": channel_name, "uid": uid,
        "rtm_token": rtm_token,
    })


# ── 2) Start agent via SDK ───────────────────────────────────────────────
@app.route("/start-agent", methods=["POST"])
def start_agent():
    data = request.get_json() or {}
    channel_name = data.get("channel")
    if not channel_name:
        return jsonify({"error": "channel is required"}), 400
    user_uid = data.get("uid")
    remote_uids = [str(user_uid)] if user_uid is not None else ["*"]

    print("\n" + "=" * 55)
    print("[/start-agent SDK] STARTING AGENT")
    print("  channel     :", channel_name)
    print("  remote_uids :", remote_uids)
    print("  models      :", ASR_MODEL, "/", LLM_MODEL, "/", TTS_MODEL, TTS_VOICE_ID)

    try:
        agent_id = agora_client.start_agent(channel_name, remote_uids)
    except Exception as e:
        print("[/start-agent SDK] FAILED:", repr(e))
        print("=" * 55 + "\n")
        return jsonify({"status": 502, "agora_response": {"error": str(e)}}), 502

    if not agent_id:
        print("[/start-agent SDK] no agent_id in response")
        print("=" * 55 + "\n")
        return jsonify({"status": 502, "agora_response": {"error": "no agent_id"}}), 502

    print("[/start-agent SDK] STARTED agent_id =", agent_id)
    print("=" * 55 + "\n")
    return jsonify({
        "status": 200,
        "agora_response": {
            "agent_id": agent_id,
            "create_ts": int(time.time()),
            "status": "RUNNING",
        },
    }), 200


# ── 3) Stop agent ────────────────────────────────────────────────────────
@app.route("/stop-agent", methods=["POST"])
def stop_agent():
    data = request.get_json() or {}
    agent_id = data.get("agent_id")
    if not agent_id:
        return jsonify({"error": "agent_id is required"}), 400

    print(f"[/stop-agent SDK] agent_id={agent_id}")
    try:
        result = agora_client.stop_agent(agent_id)
    except Exception as e:
        print("[/stop-agent SDK] EXCEPTION:", str(e))
        return jsonify({"error": str(e)}), 500

    if result is True:
        return jsonify({"status": 200}), 200
    print(f"[/stop-agent SDK] REST leave http={result.status_code} body={result.text}")
    return jsonify({"status": result.status_code}), result.status_code


# ── 4) Interrupt agent (stop it talking, keep the session) ──────────────
@app.route("/interrupt-agent", methods=["POST"])
def interrupt_agent():
    data = request.get_json() or {}
    agent_id = data.get("agent_id")
    if not agent_id:
        return jsonify({"error": "agent_id is required"}), 400

    print(f"[/interrupt-agent SDK] agent_id={agent_id}")
    try:
        resp = agora_client.interrupt_agent(agent_id)
    except Exception as e:
        print("[/interrupt-agent SDK] EXCEPTION:", repr(e))
        return jsonify({"error": str(e)}), 502
    print(f"[/interrupt-agent SDK] http={resp.status_code} body={resp.text}")
    return jsonify({"status": resp.status_code}), resp.status_code


@app.route("/", methods=["GET"])
def health():
    return jsonify({"status": "ThinkShift backend (SDK) is running"})


if __name__ == "__main__":
    print("=" * 55)
    print("ThinkShift backend (SDK) — area:", AGORA_AREA)
    print("=" * 55)
    # use_reloader=False: the reloader would start a second process with its
    # own event loop/sessions.
    app.run(host=SERVER_HOST, port=SERVER_PORT, debug=True, use_reloader=False)
