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
- The local model runner uses Qwen3.6-35B-A3B Q4_K_M with a Q8 vision projector,
  a 65,536-token context, and one generation slot.
- The downloader pins the GGUF revision, file size, and SHA-256 digest. The
  bundled llama.cpp download targets build `b10964` for Windows CUDA 12.4.
- Hosted NVIDIA support includes a hidden-input key setup script and
  machine-bound DPAPI storage. The WebUI runner shows a bilingual cloud-processing
  notice when a remote API is configured.
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
   local inference, create its `models` and `bin` directories, download and verify
   the model and projector, then register the `yanai-model` task with
   `scripts/install-model-task.ps1 -Start`.
4. Start `yanai-webui` and run `scripts/provision-admin.py` with the installation's
   Python interpreter while the service is reachable only over loopback. It saves
   the generated first-login credentials under `.secrets`. Change the password
   after signing in and remove the first-login files.
5. Verify local health, account approval, and model access before publishing the
   reverse proxy. Use `install-domain.ps1` and `install-proxy.ps1` only after
   adapting their existing-server assumptions.

The projector required by `run-model.ps1` can be fetched with the same downloader:

```powershell
.\scripts\download-model.ps1 `
    -FileName 'mmproj-Qwen3.6-35B-A3B-Q8_0.gguf' `
    -Uri 'https://huggingface.co/ggml-org/Qwen3.6-35B-A3B-GGUF/resolve/baec3ebee244827cda0f4557eafa8b28f7545fa6/mmproj-Qwen3.6-35B-A3B-Q8_0.gguf' `
    -Size 614194304 `
    -Sha256 '904cbf8c8e876220066ab3bf676c7efa40f3da372276fdaf8b01d2fb2a37a51d'
```

For a hosted API, the protected `.secrets/webui.json` supplies `OpenAIBaseUrl`,
`DefaultModel`, and the credential settings. `set-nvidia-key.ps1` only validates
and saves the key; it does not switch the backend configuration or restart WebUI.
Never commit this configuration or its encrypted credentials.

## Operations

| Script | Purpose |
| --- | --- |
| `Invoke-Home.ps1` | Run an encoded PowerShell command through the configured SSH alias. |
| `install-webui.ps1` / `run-webui.ps1` | Install and run Open WebUI with account and privacy settings. |
| `download-model.ps1` | Resume a model download and verify its size and hash. |
| `install-model-task.ps1` / `run-model.ps1` | Register and run the local model service. |
| `provision-admin.py` | Bootstrap the first administrator over loopback. |
| `install-proxy.ps1` | Validate and reload the existing Caddy config with the YanAI import. |
| `install-domain.ps1` / `update-vercel-dns.ps1` | Register and maintain the server's DNS A record. |
| `repin-ddns.ps1` | Interactively reconnect the updater after an external DNS record change. |
| `set-nvidia-key.ps1` | Validate and encrypt an NVIDIA API key without printing it. |

Keep BOM-less PowerShell 5.1 scripts ASCII-only; bilingual strings use Unicode
escapes. Parse-check changed scripts before restarting tasks. Regenerating the
parent Caddy configuration can remove its YanAI import; rerun the proxy installer
afterward if needed.

This repository does not redistribute Open WebUI, llama.cpp, Caddy, or model
weights. Their respective licenses and service terms still apply.
