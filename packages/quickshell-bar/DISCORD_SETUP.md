# Discord Control Center integration

1. Create an application in the [Discord Developer Portal](https://discord.com/developers/applications).
2. In **OAuth2 → General**, add this redirect URI exactly: `http://127.0.0.1:8765/callback`.
3. Leave Discord Desktop running, then run:

   ```sh
   python3 ~/.config/quickshell/bar/scripts/discord_rpc.py authorize
   ```

4. Enter the application's Client ID and Client Secret in the terminal. Approve the RPC request in the Discord client. Keep the Client Secret in the local prompt; do not paste it into chat.

The integration stores its OAuth credentials under `~/.config/quickshell/discord-rpc.json` with mode `0600`. Quickshell is already watching for this file and will connect automatically after setup. Its Discord daemon keeps one local RPC connection open so voice mute/deafen changes remain applied. Reopen Control Center while connected; the `DISCORD` section appears immediately below `CODEX` and disappears after leaving the call.

To remove the integration, stop/restart Quickshell and delete `~/.config/quickshell/discord-rpc.json`.
