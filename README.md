# YanAI

Native Windows deployment scripts for a ChatGPT-style service at
[ai.ethanyanxu.com](https://ai.ethanyanxu.com), using Open WebUI, Caddy, and an
OpenAI-compatible model API.

This repository contains the deployment code. Accounts, conversations, uploads,
credentials, model weights, and installed runtimes are not included.

## Architecture

```text
Browser -> Caddy (HTTPS) -> Open WebUI (127.0.0.1:8082)
                          |
                          +-> llama.cpp (127.0.0.1:8081), or
                          +-> a configured hosted HTTPS model API
```

- Open WebUI is pinned to `0.11.3` in `requirements-webui.txt`.
- The local model runner uses Gemma 4 12B with thinking enabled, original BF16
  weights and vision projector, an unquantized F16 attention cache, the full
  262,144-token context window, and one generation slot. GPU offloading adapts to
  available VRAM without reducing the configured context length.
- CPU weights use llama.cpp's `mmap+mlock` loading mode (Windows `VirtualLock`) and
  startup includes prompt/generation warm-up. `logs/model.pin.log` records warm-up
  and lock warnings. Auxiliary prompt caches are bounded to reduce memory pressure.
- Generated chat titles are disabled to avoid competing with user requests for
  the single model slot. WebUI forwards every reasoning/content delta immediately.
- Automatic built-in tool injection is disabled for ordinary chats: WebUI 0.11.3
  otherwise adds about 3,500 prompt tokens even to a simple question. Image and
  full-document inputs remain enabled, and automatic context compaction is off.
- The downloader pins the GGUF revision, file size, and SHA-256 digest. The
  bundled llama.cpp download targets build `b10964` for Windows CUDA 12.4.
- Hosted providers (OpenRouter or NVIDIA) use a hidden-input key setup script and
  machine-bound DPAPI storage. The WebUI runner shows a bilingual cloud-processing
  notice naming the provider when a remote API is configured.
- Windows scheduled tasks start the services at boot and restart them on failure.
- Caddy handles TLS and streaming. Both application ports bind to loopback.

The checked-in configuration supports both model backends; it is not a live
status report of which backend the server currently uses.

## Accounts and privacy

New accounts require administrator approval. Change a user's role from `pending`
to `user` in **Admin Panel -> Users** to allow chatting. Approved users can access
the configured model. Images and document attachments are enabled; documents are
included as full context without an embedding index.

The WebUI runner disables administrator chat access, bulk export, analytics,
workspace access overrides, and message ratings. Account approval remains
available. Public chat sharing is disabled. Settings are supplied at startup with
`ENABLE_PERSISTENT_CONFIG=false`.

These are application access controls, not end-to-end encryption. Server operators
can access the database, change the configuration, or reset account passwords.
With a hosted backend, conversation content also goes to the configured provider.

## Deployment

These scripts are tailored to an existing Windows home server, not a standalone
installer for an arbitrary machine. Review the paths and domain before running
them with administrator privileges.

The existing layout uses `C:\AI\yanai` as the installation root, `finprint-host`
as the SSH alias, an existing Caddy installation, and Vercel-managed DNS. The proxy
installer imports into `C:\Users\ethan\finprint\scripts\selfhost\Caddyfile`;
the domain installer reuses the protected DNS configuration at
`C:\ProgramData\yanvpn\ddns\vercel-ddns.json`.

For a new installation:

1. Review the server paths, domain, SSH alias, and first-admin name/email in the
   scripts. Install Caddy and configure DNS and forwarding for ports 80 and 443.
   Local inference also requires an NVIDIA GPU and compatible driver.
2. Copy the source to the server. Run `scripts/install-webui.ps1` from an elevated
   PowerShell session to create the protected installation directory, configuration,
   Python environment, and `yanai-webui` task. It accepts Python 3.11 or 3.12, or
   installs managed Python through its pinned uv runtime.
3. Copy the remaining scripts and `Caddyfile` into the installation root. For
   local inference, run `scripts/download-gemma.ps1` to create the download
   directories and verify the model and projector, then register the `yanai-model` task with
   `scripts/install-model-task.ps1 -Start`.
4. Start `yanai-webui` and run `scripts/provision-admin.py` with the installation's
   Python interpreter while the service is reachable only over loopback. It saves
   the generated first-login credentials under `.secrets`. Change the password
   after signing in and remove the first-login files.
5. Verify local health, account approval, and model access before publishing the
   reverse proxy. Use `install-domain.ps1` and `install-proxy.ps1` only after
   adapting their existing-server assumptions.

Download the BF16 model and BF16 projector together (about 24 GB):

```powershell
.\scripts\download-gemma.ps1
```

For a hosted API, the protected `.secrets/webui.json` supplies `OpenAIBaseUrl`,
`DefaultModel`, `OpenAIApiKeyFile`, and optionally `ProviderName` and
`ProviderMayTrain` for the notice banner (unknown providers are described as
possibly training on chats). `set-api-key.ps1 -Name openrouter|nvidia` only
validates and saves the key; it does not switch the backend configuration or
restart WebUI. Never commit this configuration or its encrypted credentials.

## Operations

| Script | Purpose |
| --- | --- |
| `Invoke-Home.ps1` | Run an encoded PowerShell command through the configured SSH alias. |
| `install-webui.ps1` / `run-webui.ps1` | Install and run Open WebUI with account and privacy settings. |
| `download-model.ps1` | Resume a model download and verify its size and hash. |
| `download-gemma.ps1` | Download the pinned, unquantized Gemma model and projector. |
| `inspect-gguf.py` | Verify metadata and tensor storage types without loading weights. |
| `benchmark-stream.py` | Measure time to first thinking/answer text with synthetic prompts. |
| `install-model-task.ps1` / `run-model.ps1` | Register and run the local model service. |
| `provision-admin.py` | Bootstrap the first administrator over loopback. |
| `install-proxy.ps1` | Validate and reload the existing Caddy config with the YanAI import. |
| `install-domain.ps1` / `update-vercel-dns.ps1` | Register and maintain the server's DNS A record. |
| `repin-ddns.ps1` | Interactively reconnect the updater after an external DNS record change. |
| `set-api-key.ps1` | Validate and encrypt an OpenRouter or NVIDIA API key without printing it. |

Keep BOM-less PowerShell 5.1 scripts ASCII-only; bilingual strings use Unicode
escapes. Parse-check changed scripts before restarting tasks. Regenerating the
parent Caddy configuration can remove its YanAI import; rerun the proxy installer
afterward if needed.

To measure inference startup delay on the server without logging chat text:

```powershell
C:\AI\yanai\.venv\Scripts\python.exe C:\AI\yanai\scripts\benchmark-stream.py --no-cache
```

The benchmark reports first nonempty reasoning and answer deltas separately from
HTTP headers. `--webui --ui-context --url https://ai.ethanyanxu.com/api/chat/completions` tests
the public path using saved bootstrap credentials, if those credentials still
exist and work. Long prompts must still be evaluated before the first output;
enabling 256K context does not make a full-length prompt fast on an 8 GB GPU.

This repository does not redistribute Open WebUI, llama.cpp, Caddy, or model
weights. Their respective licenses and service terms still apply.
