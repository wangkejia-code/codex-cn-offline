# Codex CN Offline

Make the OpenAI Codex desktop app sidebar use Simplified Chinese without
access to `chatgpt.com`.

## Why this exists

Codex bundles Simplified Chinese translations, but the left navigation,
conversation list and feature sidebar only load them when an OpenAI
server-side feature flag (`Statsig layer 72216192.enable_i18n`) is enabled.
The app fetches that flag from `chatgpt.com`, which is unreachable on some
networks. When the fetch fails, the flag defaults to `false` and the sidebar
stays English even though the app language is set to Chinese
(`localeOverride = "zh-CN"`).

This tool launches Codex with Chromium's remote debugging port and injects a
small patch that forces the flag to `true`, so the app loads its own bundled
Chinese translations. Everything runs locally; no network access is required.

## Requirements

- Windows 10/11
- Codex desktop (MSIX package `OpenAI.Codex`) installed
- Node.js available on `PATH`

## Usage

1. Double-click `启动中文版Codex.bat`.
2. Select `1` to start Codex in Chinese mode.
3. The tool closes any running Codex, relaunches it with the patch and prints
   the result.

Menu option `2` registers an auto-start entry so Codex opens in Chinese mode
after you log in to Windows. Menu option `3` removes it.

> The sidebar stays Chinese only when Codex is launched through this tool.
> If you open Codex from the Start menu or taskbar icon directly, the sidebar
> returns to English.

## Files

- `Codex-CN-Offline.ps1` - launcher: closes Codex, starts it with the remote
  debugging port, waits for the port, runs the injector
- `inject.js` - Chrome DevTools Protocol client that applies the patch
- `启动中文版Codex.bat` - double-click entry point
- `使用说明.md` - Chinese usage notes

## How the patch works

The injector connects to the app shell renderer over the DevTools protocol and
monkey-patches the Statsig client's `getLayer` so layer `72216192` reports
`enable_i18n = true`, then emits `values_updated` to trigger a re-render. The
app shell then loads the bundled `zh-CN` message catalogs.

## Limitations

- Unofficial workaround, not affiliated with OpenAI.
- Requires launching Codex through this tool each session.
- App updates may change the flag logic and break the patch.
- Review OpenAI's terms of service before using or redistributing this tool.

No secrets are included. The Statsig client key in `inject.js` is a public
client key embedded in the installed app.

## License

MIT, see [LICENSE](LICENSE).
