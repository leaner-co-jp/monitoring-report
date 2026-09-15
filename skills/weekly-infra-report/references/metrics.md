# インフラ指標の週次値（手順5）

**取得する前に [docs/datadog-mcp-tips.md](../../../docs/datadog-mcp-tips.md) を必ず読む。** 数値を誤らせる罠が集約されている。

ECS / RDS / ALB の **状態（色）は手順1の monitor から**取る。ここで取るのは先週比の数値と方向を添えるためだけ。

**取得した値は、発火の有無に関わらず毎週テンプレート §3.1 の台帳に記録する**（§2 は発火したものだけを書くので、静かな週の数値の唯一の住所が台帳になる）。

## 共通の取得式と罠

### ECS

- **メモリ %** = `max:ecs.fargate.mem.rss{ecs_service:<svc>}.rollup(avg, 3600)` / `max:ecs.fargate.mem.task.limit{...}.rollup(avg, 3600)` × 100 を `aggregator="max"`（= 1時間平均の週内最大 = 持続的なピーク）。
- **CPU %** は **monitor と同じ vCPU 正規化式**で取得する → `max:ecs.fargate.cpu.percent{ecs_service:<svc>}.rollup(avg, 3600)` / ( `max:ecs.fargate.cpu.task.limit{ecs_service:<svc>}` / 1000000000 )。

⚠️ 2点に注意:

1. 生の `ecs.fargate.cpu.percent` は**単一 vCPU 基準**で、複数 vCPU 割当のタスク（API 等）は 100% 超になり誤読を招くため使わない。
2. **rollup なしの素の `aggregator="max"` は1分粒度の瞬間生値ピーク（API CPU 197% 等）を拾い、閾値（90 / 95）と整合しない** → 持続的なピーク評価には必ず `.rollup(avg, 3600)` をクエリ文字列に埋める。

### RDS

タグ `{env:production, dbclusteridentifier:{{P.db_cluster}}, role:<role>}` で `aws.rds.cpuutilization`（max / avg）/ `aws.rds.database_connections`（max / avg）/ `aws.rds.freeable_memory`（avg）/ `aws.rds.read_iops`・`aws.rds.write_iops`（avg）。

⚠️ **max（週内ピーク）を取る指標（CPU・コネクション）は `.rollup(avg, 3600)` をクエリに埋めて `aggregator="max"`** とする。素の `aggregator="max"` は瞬間生値スパイク（RDS Writer CPU 99% 等）を拾い、閾値（75 / 90）と乖離する（scalar:max アーティファクト）。

### ALB

タグ `{service:{{P.api_service}}, env:production}` で `httpcode_target_2xx` + `httpcode_elb_3xx` / `elb_4xx` / `elb_5xx`（`aggregator="sum"`, `.as_count()`）、`healthy_host_count` / `un_healthy_host_count`（`avg`）。

### 共通のルール

- 発火の事実は手順1・2 の monitor から拾う（色は付けない → `references/evaluate.md`）。取得した数値には先週比と方向（上昇／下降）を添える。
- **台帳の「校正メモ」列は毎週埋める**（記法はテンプレート §3.1 のガイド参照）。monitor の校正不良——鈍くて鳴らない／鳴りすぎて非事象——を可視化する唯一の場所なので、空のまま出さない。

## このプロダクトで取る対象

{{P:metric-queries}}
