// Backend base URL for the ThinkShift Flask server (backend/thinkshift_app.py, port 8001).
//
// - Android emulator: 10.0.2.2 maps to the host machine's localhost automatically.
// - Physical device: use your dev machine's LAN IP (run `ipconfig`, look for the
//   Wi-Fi adapter's IPv4 address), and make sure both devices are on the same
//   network and port 8001 is allowed through the firewall.

const String kBackendBaseUrl = "http://10.0.2.2:8001";


// Fixed channel name for this single-tester MVP.
const String kChannelName = "thinkshift_room_1";

// Fixed, non-zero local uid. The RTC token is minted server-side for this exact
// uid, so it must never be 0 (Agora would assign a random uid that doesn't match
// the token, silently breaking mic publishing) and never 999 (that's reserved
// for the AI agent's own uid on the server side).
const int kLocalUid = 12345;
