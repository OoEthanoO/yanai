#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\AI\yanai',
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ConfigPath) { $ConfigPath = Join-Path $InstallRoot '.secrets\webui.json' }
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($field in @('WebuiSecretKey', 'OpenAIBaseUrl', 'OpenAIApiKey', 'DefaultModel', 'WebuiUrl', 'Port', 'DataDir')) {
    if (-not $config.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$config.$field)) {
        throw "Missing WebUI configuration field: $field"
    }
}
if ([string]$config.WebuiSecretKey -eq 'changeme' -or ([string]$config.WebuiSecretKey).Length -lt 32) {
    throw 'WebuiSecretKey must contain at least 32 random characters.'
}
$apiUri = [Uri]$config.OpenAIBaseUrl
# Either the local llama server (plain HTTP on loopback) or a hosted API over HTTPS (e.g. NVIDIA).
$remoteApi = -not $apiUri.IsLoopback
if ($remoteApi -and $apiUri.Scheme -ne 'https') { throw 'A hosted model API must use HTTPS.' }
$apiKey = [string]$config.OpenAIApiKey
if ($config.PSObject.Properties['OpenAIApiKeyFile'] -and $config.OpenAIApiKeyFile) {
    # DPAPI (LocalMachine) encrypted key written by set-nvidia-key.ps1.
    Add-Type -AssemblyName System.Security
    $cipher = [Convert]::FromBase64String([IO.File]::ReadAllText([string]$config.OpenAIApiKeyFile))
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($cipher, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $apiKey = [Text.Encoding]::UTF8.GetString($plain)
    [Array]::Clear($plain, 0, $plain.Length)
}
$port = [int]$config.Port
if ($port -lt 1024 -or $port -gt 65535) { throw 'Invalid WebUI listen port.' }
$venvPython = Join-Path $InstallRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) { throw 'Run install-webui.ps1 first.' }
$logDirectory = Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDirectory, $config.DataDir | Out-Null

$environment = @{
    ENV = 'prod'
    PYTHONUTF8 = '1'
    PYTHONIOENCODING = 'utf-8'
    PYTHONUNBUFFERED = '1'
    DATA_DIR = [string]$config.DataDir
    WEBUI_SECRET_KEY = [string]$config.WebuiSecretKey
    WEBUI_URL = [string]$config.WebuiUrl
    WEBUI_AUTH = 'true'
    ENABLE_LOGIN_FORM = 'true'
    # Anyone can sign up, but new accounts stay pending (no model access) until an admin approves them.
    ENABLE_SIGNUP = 'true'
    ENABLE_SIGNUP_PASSWORD_CONFIRMATION = 'true'
    ENABLE_INITIAL_ADMIN_SIGNUP = 'false'
    DEFAULT_USER_ROLE = 'pending'
    # Bilingual (English / Simplified Chinese). Chinese is written as \u escapes because Windows PowerShell 5.1
    # reads BOM-less scripts in the ANSI code page and would mangle literal Chinese characters.
    PENDING_USER_OVERLAY_TITLE = [regex]::Unescape('Waiting for approval / \u7b49\u5f85\u5ba1\u6838')
    PENDING_USER_OVERLAY_CONTENT = [regex]::Unescape('Thanks for signing up! An admin needs to approve your account before you can start chatting. Check back soon. \u611f\u8c22\u6ce8\u518c\uff01\u7ba1\u7406\u5458\u6279\u51c6\u60a8\u7684\u8d26\u6237\u540e\uff0c\u60a8\u5c31\u53ef\u4ee5\u5f00\u59cb\u804a\u5929\u4e86\u3002\u8bf7\u7a0d\u540e\u518d\u6765\u67e5\u770b\u3002')
    # Models from the llama connection are admin-only unless shared; every approved user should see them.
    # Pending users stay locked out because the model endpoints require an approved account.
    BYPASS_MODEL_ACCESS_CONTROL = 'true'
    # Privacy: admins cannot open, list or export other users' chats, cannot browse their uploads or
    # workspace items, and get no per-user analytics. Message ratings are off because each rating stores a
    # copy of the conversation that admins can read.
    ENABLE_ADMIN_CHAT_ACCESS = 'false'
    ENABLE_ADMIN_EXPORT = 'false'
    ENABLE_ADMIN_ANALYTICS = 'false'
    ENABLE_ADMIN_WORKSPACE_CONTENT_ACCESS = 'false'
    BYPASS_ADMIN_ACCESS_CONTROL = 'false'
    ENABLE_MESSAGE_RATING = 'false'
    ENABLE_PERSISTENT_CONFIG = 'false'
    ENABLE_OLLAMA_API = 'false'
    ENABLE_OPENAI_API = 'true'
    OPENAI_API_BASE_URLS = [string]$config.OpenAIBaseUrl
    OPENAI_API_KEYS = $apiKey
    # Only offer the configured model (NVIDIA's endpoint lists dozens).
    OPENAI_API_CONFIGS = '{"0":{"model_ids":["' + [string]$config.DefaultModel + '"]}}'
    DEFAULT_MODELS = [string]$config.DefaultModel
    ENABLE_DIRECT_CONNECTIONS = 'false'
    OFFLINE_MODE = 'true'
    HF_HUB_OFFLINE = '1'
    HF_HUB_DISABLE_TELEMETRY = '1'
    DO_NOT_TRACK = 'true'
    ANONYMIZED_TELEMETRY = 'false'
    SCARF_NO_ANALYTICS = 'true'
    ENABLE_VERSION_UPDATE_CHECK = 'false'
    RAG_EMBEDDING_MODEL_AUTO_UPDATE = 'false'
    RAG_RERANKING_MODEL_AUTO_UPDATE = 'false'
    WHISPER_MODEL_AUTO_UPDATE = 'false'
    ENABLE_PIP_INSTALL_FRONTMATTER_REQUIREMENTS = 'false'
    ENABLE_COMMUNITY_SHARING = 'false'
    ENABLE_WEB_SEARCH = 'false'
    ENABLE_IMAGE_GENERATION = 'false'
    ENABLE_IMAGE_EDIT = 'false'
    ENABLE_MEMORIES = 'false'
    ENABLE_CODE_EXECUTION = 'false'
    ENABLE_CODE_INTERPRETER = 'false'
    ENABLE_EVALUATION_ARENA_MODELS = 'false'
    ENABLE_FOLLOW_UP_GENERATION = 'false'
    ENABLE_TAGS_GENERATION = 'false'
    ENABLE_AUTOCOMPLETE_GENERATION = 'false'
    USER_PERMISSIONS_CHAT_STT = 'false'
    USER_PERMISSIONS_CHAT_TTS = 'false'
    USER_PERMISSIONS_CHAT_CALL = 'false'
    # Uploads are on so people can attach images. There is no embedding model, so attached documents
    # go into the prompt whole instead of through retrieval.
    USER_PERMISSIONS_CHAT_FILE_UPLOAD = 'true'
    BYPASS_EMBEDDING_AND_RETRIEVAL = 'true'
    ENABLE_RETRIEVAL_QUERY_GENERATION = 'false'
    RAG_FILE_MAX_SIZE = '25'
    RAG_FILE_MAX_COUNT = '5'
    USER_PERMISSIONS_CHAT_WEB_UPLOAD = 'false'
    USER_PERMISSIONS_CHAT_ALLOW_PUBLIC_SHARING = 'false'
    USER_PERMISSIONS_CHAT_ALLOW_OPEN_SHARING = 'false'
    WEBUI_SESSION_COOKIE_SECURE = 'true'
    WEBUI_AUTH_COOKIE_SECURE = 'true'
    WEBUI_SESSION_COOKIE_SAME_SITE = 'lax'
    CORS_ALLOW_ORIGIN = ([string]$config.WebuiUrl).TrimEnd('/')
    SHOW_ADMIN_DETAILS = 'false'
    UVICORN_WORKERS = '1'
    AIOHTTP_CLIENT_TIMEOUT = '1800'
    AIOHTTP_CLIENT_TIMEOUT_MODEL_LIST = '15'
    ENABLE_OTEL = 'false'
}
# Always set banners explicitly: Open WebUI keeps the last value in its database otherwise.
$environment['WEBUI_BANNERS'] = '[]'
if ($remoteApi) {
    # Chats leave this server when a hosted API is used, so say so on every chat page (EN / zh-CN).
    $environment['WEBUI_BANNERS'] = '[{"id":"hosted-model-notice","type":"info","title":"","content":"Chats on this site are processed by the NVIDIA cloud service (Kimi K3). NVIDIA may log them and use them to improve its AI models, so please do not share sensitive personal information. \u672c\u7ad9\u7684\u5bf9\u8bdd\u7531 NVIDIA \u4e91\u670d\u52a1\uff08Kimi K3\uff09\u5904\u7406\u3002NVIDIA \u53ef\u80fd\u4f1a\u8bb0\u5f55\u8fd9\u4e9b\u5bf9\u8bdd\u5e76\u7528\u4e8e\u6539\u8fdb\u5176 AI \u6a21\u578b\uff0c\u8bf7\u4e0d\u8981\u5206\u4eab\u654f\u611f\u7684\u4e2a\u4eba\u4fe1\u606f\u3002","dismissible":false,"timestamp":1790294400}]'
}
foreach ($entry in $environment.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
}

# Windows PowerShell removes empty environment variables. Set these inside Python
# before importing WebUI so disabled embeddings/Whisper do not revert to defaults.
$bootstrap = "import os; os.environ['RAG_EMBEDDING_MODEL']=''; os.environ['RAG_RERANKING_MODEL']=''; os.environ['WHISPER_MODEL']=''; from open_webui import app; app()"
$arguments = '-c "{0}" serve --host 127.0.0.1 --port {1}' -f $bootstrap, $port
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logDirectory "webui-$stamp.stdout.log"
$stderr = Join-Path $logDirectory "webui-$stamp.stderr.log"
$process = Start-Process -FilePath $venvPython -ArgumentList $arguments -WorkingDirectory $InstallRoot -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
if ($process.ExitCode -eq 0) {
    # The web server is expected to stay running; let Task Scheduler restart it.
    exit 1
}
exit $process.ExitCode
