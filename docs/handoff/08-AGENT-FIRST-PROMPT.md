# Paste into local development agent

You are implementing MeshHub, a privately developed, offline-first, cross-platform MeshCore + Meshtastic client. The authoritative requirements are in the adjacent `MeshHub-Agent-Handoff/` folder. Read `00-START-HERE.md` then all listed documents. Do not substitute your own product scope.

Start with **Milestone 0 only**. On this Omarchy Linux machine:
1. Inspect available development tooling safely; report Flutter/Dart, Linux, BlueZ, build dependencies and missing items.
2. Establish a private local Git repository and modular Flutter/Dart workspace using documented architecture ports.
3. Build a runnable Linux app with adaptive theme tokens, primary sidebar, unified sample inbox, mock radio status, and network filters. Mark everything simulated.
4. Implement adapter interfaces and fake transports, automated tests, lint/format checks, and a redacted diagnostic logger.
5. Research candidate BlueZ-compatible BLE integration and attempt a non-destructive discovery/notification feasibility test only with user consent for device pairing.
6. Record exact environment, build/run commands, test results, blockers, dependencies/licenses, and architecture decisions in README and PROGRESS.md.
7. Present the M0 acceptance checklist and **stop for owner approval** before M1.

Do not reflash/reset/configure the Heltec, send RF traffic, publish the repository, or add cloud synchronization. Do not claim hardware send/receive was tested until it has actually passed.
