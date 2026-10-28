# ThanhThan native client: open-source foundation

Goal: a standalone iPhone client that can log in with the **existing ThanhThan PC account**, load the **same server-side character**, and interact with PC players. The existing SceneKit app still does **not** do this.

## Reviewed upstream projects (2026-10-28)

1. **[xulek/muonline](https://github.com/xulek/muonline)** — MonoGame/.NET 10 client with rendering, BMD models, animation, scenes, Season 6 network abstractions and a `MuIos/` project. The upstream iOS .csproj currently targets `iossimulator-x64`, so this does not establish a working arm64 iPhone IPA. The repository does **not** expose an OSI license file; README calls it educational/non-commercial. Use as a technical **reference**, not copy source into this repository without adequate licensing permission.
2. **[xulek/MuOnlineConsoleClient](https://github.com/xulek/MuOnlineConsoleClient)** — MIT-licensed login/character/state/network client in C# using OpenMU networking; no full iOS graphics engine. Reference for modular session state.
3. **[MUnique/OpenMU](https://github.com/MUnique/OpenMU)** — MIT-licensed open source MU server and network protocol documentation, especially `docs/Packets/PacketTypes.md`. It primarily describes Season 6 Episode 3 **ENG**; target ThanhThan's customizations are **not established**.
4. **[sven-n/MuMain](https://github.com/sven-n/MuMain)** — playable desktop MU client, with iOS not yet buildable according to its build documentation.

## Concrete code introduced

- `MUWireProtocol.swift`: native Swift parser/encoder for raw MU C1/C2/C3/C4 **packet framing**, including split/coalesced TCP reads and basic size validation. The implementation is independently written based on public packet format documentation.
- `Tests/Protocol/main.swift`: deterministic Swift smoke tests, run in GitHub Actions before an iOS IPA build.
- This is **packet framing only**. No cipher keys, encrypted payload decryption, version/serial negotiation, credentials, handshake, or server-specific commands are implemented.

### Read-only Season 6 server message decoder (2026-10-28)
- `MUServerPackets.swift` recognizes only documented unencrypted **OpenMU** messages: C1 00 01 hello; C2 F4 06 server list; C1 F4 03 game-server address; C1 F1 00 game server entered; C1 F1 01 login response.
- The fixture-based protocol checks exercise expected byte order, exact lengths, unknown codes, malformed responses, unsafe host rejection, and encrypted-frame opacity.
- This is NOT connected to the live ThanhThan server. No credentials are sent, no encryption/handshake has been reverse engineered, and the native game scene is still offline.
- Important: receiving a `loginResponse` in a test does not mean that login has been implemented; it is only a decoder for the documented reply **if** one is received from a compatible authenticated session.

## Compatibility gates before claiming online gameplay

1. Identify the original Windows client protocol **version, serialization changes, handshakes and negotiated encryption**, preferably from the authorized ThanhThan operator or approved technical documentation. Observed TCP connections to 160.22.161.124 on 1993, 44404 and 55920 are **observations**, not a verified protocol definition.
2. Implement connect-server state, game-server hand-off, authentication and character list against an **authorized staging endpoint** with test credentials. Never hardcode real credentials or publish session tokens.
3. Receive and display the **real PC character** and world state from the server; replace simulated HP, XP, inventory and movement authority.
4. Port or license a full MU rendering/gameplay engine (BMD animation, terrain, equipment, combat, menus), build for iPhone arm64, and test against the live server only with permission.
5. Sign and test the IPA on an actual iPhone before declaring completion.

**Never replace or modify the existing account database.** A different server or locally simulated character cannot satisfy the user's goal.

## Offline ConnectServer negotiation (synthetic fixtures only)
- `MUConnectServerFlow.swift` models the documented server-list negotiation as a strict state machine; it generates C1 F4 06 list and C1 F4 03 server-selection envelopes only when the expected preceding response has been received.
- Server selection is constrained to IDs returned by the server list. It preserves the game server address but NEVER connects to it or sends a password.
- This is the OpenMU protocol *candidate*, not evidence of actual ThanhThan handshake compatibility. It is not wired into the gameplay scene.


## Documented character-list decoding

- Added `MUCharacterList.swift` to decode two documented F3/00 server-to-client character-list record layouts (34 and 44 bytes) with strict size checks.
- The decoder retains equipment/appearance bytes verbatim rather than guessing class, model or equipment IDs.
- Only synthetic, local tests are used; this does **not** read anyone's ThanhThan characters.
- The actual game-server login, cipher negotiation, request sequencing, and server-variant compatibility are still missing.


## Game-server session progression

- `MUGameSession.swift` implements an independently testable server-hello → login-reply → character-list progression against **synthetic** MU Season 6 packets.
- It sends a documented F3/00 character-list request **only when the server confirms successful login**. It does not generate or send account credentials, negotiate ciphers or connect to the ThanhThan game server.
- Unknown encrypted responses and unknown character-list variants must remain unsupported until verified with an authorized server.
