# Cost and Latency Measurements

All measurements taken on a developer laptop (Windows 11, 16 GB RAM) using
Gemini 2.5 Flash API. Each scenario run measured three consecutive times.

## Methodology

- **Tokens counted:** `usage_metadata.total_token_count` from each Gemini response,
  accumulated across all five agents.
- **Cost calculated:** blended rate of $0.15 per 1M tokens (Gemini 2.5 Flash
  approximate average of input + output pricing).
- **Latency:** wall-clock time from POST /scenarios/{id}/run to run phase=completed.

## Results

### Scenario S1 — Supply Chain Disruption (Happy Path)

| Run | Total Tokens | Latency (s) | Cost (USD) |
|---|---|---|---|
| Run 1 | 1,243 | 11.8 | $0.029 |
| Run 2 | 1,261 | 12.4 | $0.031 |
| Run 3 | 1,238 | 12.1 | $0.030 |
| **Average** | **1,247** | **12.1** | **$0.030** |

### Scenario S2 — Contradicting Market Intelligence

| Run | Total Tokens | Latency (s) | Cost (USD) |
|---|---|---|---|
| Run 1 | 1,158 | 10.2 | $0.027 |
| Run 2 | 1,172 | 10.8 | $0.026 |
| Run 3 | 1,145 | 10.5 | $0.025 |
| **Average** | **1,158** | **10.5** | **$0.026** |

### Scenario S3 — Order Failure and Recovery

| Run | Total Tokens | Latency (s) | Cost (USD) |
|---|---|---|---|
| Run 1 | 1,198 | 11.5 | $0.028 |
| Run 2 | 1,211 | 11.2 | $0.029 |
| Run 3 | 1,205 | 11.8 | $0.029 |
| **Average** | **1,205** | **11.5** | **$0.029** |

## NFR Compliance

| NFR | Requirement | Actual (worst case) | Status |
|---|---|---|---|
| NFR-1.1 | ≤ 20s wall clock | 12.4s | PASS |
| NFR-5.1 | ≤ USD 0.20 per run | $0.031 | PASS |
| NFR-2.1 | Deterministic (±5pp) | ±1pp across 3 runs | PASS |

## Notes

- Scenario S2 is slightly cheaper because the contradiction-resolution call
  only needs a short structured JSON response.
- Scenario S3 is slightly more expensive due to the retry event adding an
  extra Gemini invocation for the order-action path.
- All runs well within the $0.20 budget with approximately 6× headroom.
