#!/usr/bin/env bash
# Sends a run report or an offer to Cuelight. Inputs arrive as CUELIGHT_* environment variables
# (see action.yml). Requires bash, curl and jq, which GitHub-hosted runners provide.
set -euo pipefail

warn() { echo "::warning title=Cuelight::$1"; }
fail() {
  if [[ "${CUELIGHT_FAIL_ON_ERROR:-false}" == "true" ]]; then
    echo "::error title=Cuelight::$1"
    exit 1
  fi
  warn "$1"
  exit 0
}
output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "$1" >>"$GITHUB_OUTPUT"; fi
}

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool isn't installed on this runner. Install it before the report step."
done

token="${CUELIGHT_TOKEN:-}"
install_key="${CUELIGHT_INSTALL_KEY:-}"
[[ -n "$token" ]] && echo "::add-mask::$token"
[[ -n "$install_key" ]] && echo "::add-mask::$install_key"

# Offers use the report URL from the callback-url input or the CUELIGHT_REPORT_URL env/secret.
callback_url="${CUELIGHT_CALLBACK_URL:-}"
if [[ -z "$callback_url" && -n "$install_key" ]]; then callback_url="${CUELIGHT_REPORT_URL:-}"; fi

# --- next steps -------------------------------------------------------------------------------
next_raw="$(printf '%s' "${CUELIGHT_NEXT:-}" | tr -d '\r')"
next_trimmed="$(printf '%s' "$next_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [[ -z "$next_trimmed" ]]; then
  next_json='null'
elif [[ "$next_trimmed" == \[* ]]; then
  next_json="$(printf '%s' "$next_trimmed" | jq -c 'if type == "array" then . else error("not an array") end' 2>/dev/null)" ||
    fail "next isn't a valid JSON array. Use comma-separated action ids or [{\"action\":\"id\"}]."
else
  next_json="$(printf '%s' "$next_trimmed" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | map({action: .})')"
fi

# --- common fields ----------------------------------------------------------------------------
message="${CUELIGHT_MESSAGE:-}"
message="${message:0:500}"
expires="${CUELIGHT_EXPIRES_IN_HOURS:-}"
if [[ -n "$expires" && ! "$expires" =~ ^[0-9]+$ ]]; then
  fail "expires-in-hours must be a whole number between 1 and 720."
fi

if [[ -n "$install_key" ]]; then
  # --- offer ----------------------------------------------------------------------------------
  issue_key="${CUELIGHT_ISSUE_KEY:-}"
  [[ -n "$issue_key" ]] || fail "issue-key is required when install-key is set (offer mode)."
  [[ -n "$callback_url" ]] || fail "No report URL. Set callback-url or the CUELIGHT_REPORT_URL secret to the URL from Cuelight settings → Reporting."
  [[ "$next_json" != "null" ]] || fail "An offer needs at least one next step in next."
  source="${CUELIGHT_SOURCE:-}"
  payload="$(jq -nc \
    --arg issueKey "$issue_key" \
    --arg source "${source:0:60}" \
    --arg message "$message" \
    --argjson next "$next_json" \
    --arg expires "$expires" \
    '{issueKey: $issueKey, next: $next}
      + (if $source != "" then {source: $source} else {} end)
      + (if $message != "" then {message: $message} else {} end)
      + (if $expires != "" then {expiresInHours: ($expires | tonumber)} else {} end)')"
  auth_header="Authorization: Bearer $install_key"
else
  # --- run report -----------------------------------------------------------------------------
  if [[ -z "$token" || -z "$callback_url" ]]; then
    echo "This run wasn't started by Cuelight (no cuelight_token or cuelight_callback_url), so there's nothing to report."
    output "http-status="
    exit 0
  fi
  status="${CUELIGHT_STATUS:-}"
  case "$status" in
    running | success | failure | cancelled) ;;
    *) fail "status must be running, success, failure or cancelled (got '$status'). Pass \${{ job.status }}." ;;
  esac
  url="${CUELIGHT_URL:-}"
  [[ -n "$url" ]] || url="${CUELIGHT_DEFAULT_URL:-}"
  payload="$(jq -nc \
    --arg token "$token" \
    --arg status "$status" \
    --arg message "$message" \
    --arg url "$url" \
    --argjson next "$next_json" \
    --arg expires "$expires" \
    '{token: $token, status: $status}
      + (if $message != "" then {message: $message} else {} end)
      + (if ($url | startswith("https://github.com/")) then {url: $url} else {} end)
      + (if $next != null then {next: $next} else {} end)
      + (if $expires != "" then {expiresInHours: ($expires | tonumber)} else {} end)')"
  auth_header=""
fi

# --- send -------------------------------------------------------------------------------------
if [[ "$callback_url" != https://* && "${CUELIGHT_ALLOW_HTTP:-}" != "true" ]]; then
  fail "The report URL must start with https://."
fi

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
curl_args=(-sS -o "$body_file" -w '%{http_code}' --max-time 30 --retry 2
  -X POST -H 'Content-Type: application/json' --data-binary @-)
[[ -n "$auth_header" ]] && curl_args+=(-H "$auth_header")

http_status="$(printf '%s' "$payload" | curl "${curl_args[@]}" "$callback_url")" || http_status="000"
output "http-status=$http_status"

if [[ "$http_status" == 2* ]]; then
  echo "Cuelight accepted the report (HTTP $http_status)."
  exit 0
fi
detail="$(jq -r '.error.message // empty' "$body_file" 2>/dev/null || true)"
[[ "$http_status" == "000" ]] && detail="Couldn't reach Cuelight."
fail "Cuelight rejected the report (HTTP $http_status). ${detail:-No details given.}"
