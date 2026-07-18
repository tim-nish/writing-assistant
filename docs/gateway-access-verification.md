# Verifying gateway-only access

Since the 2026-07-18 gateway-only amendment (SPEC-policy-source-seam CAP-2,
#366), writing-assistant never touches the Tsurezure recall surface as files:
every policy byte is served by tsurezure-gateway (consumer
`writing-assistant`), and the gateway's **server-side access log is the
canonical record of access**. The consumer's `consulted:` lines in run
artifacts are receipts, not the record.

## The doctor

```sh
python3 scripts/gateway-access-doctor.py \
  --consumer writing-assistant \
  --since 2026-07-18T00:00:00Z \
  --receipts <run-artifact-with-consulted-lines> --strict
```

Read-only, stdlib-only, zero tokens. The log path resolves exactly like the
gateway's own `resolveLogPath`: `statePath` from `~/.tsurezure/gateway.json`,
else `$TSUREZURE_STATE_DIR`, else `~/.tsurezure` — file `access.jsonl`
(override with `--log`). Without `--receipts` it just prints the windowed
entries (ts, tool, decision, files served, pin, config version).

## The two-direction check

With `--receipts`, the doctor extracts the artifact's `consulted:` lines and
cross-checks at pin level:

- **receipt → log**: every receipt pin (`<policy-source>@<commit>`) appears
  in a windowed log entry for the consumer — a receipt nothing served is a
  fabricated citation;
- **log → receipt**: every windowed log entry for the consumer carries a pin
  some receipt names — a served read no receipt admits is an unaccounted
  access.

`consulted: none (…)` is a generic-mode receipt: it names no pin and expects
no log entry. Mismatches print in both directions; `--strict` turns any
mismatch into exit 1.

## The regression suite

`sh scripts/check-gateway-only.sh` enforces the rest of the CAP-2 success
clause mechanically: a static scan proving no code path under `scripts/` or
`skills/` reads a recall-surface file directly (with a seeded-violation
self-test), a scan proving no onboarded repo's config carries a hub path,
and a stopped-gateway run that completes generic with exit 11 and zero hub
reads (unreadable canary hubs would surface any attempted open).
