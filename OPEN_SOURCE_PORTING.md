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

## Compatibility gates before claiming online gameplay

1. Identify the original Windows client protocol **version, serialization changes, handshakes and negotiated encryption**, preferably from the authorized ThanhThan operator or approved technical documentation. Observed TCP connections to 160.22.161.124 on 1993, 44404 and 55920 are **observations**, not a verified protocol definition.
2. Implement connect-server state, game-server hand-off, authentication and character list against an **authorized staging endpoint** with test credentials. Never hardcode real credentials or publish session tokens.
3. Receive and display the **real PC character** and world state from the server; replace simulated HP, XP, inventory and movement authority.
4. Port or license a full MU rendering/gameplay engine (BMD animation, terrain, equipment, combat, menus), build for iPhone arm64, and test against the live server only with permission.
5. Sign and test the IPA on an actual iPhone before declaring completion.

**Never replace or modify the existing account database.** A different server or locally simulated character cannot satisfy the user's goal.
