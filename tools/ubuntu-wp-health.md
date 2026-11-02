# Ubuntu WordPress / LiteSpeed health checker

Copy `ubuntu-wp-health.py` to your Ubuntu server and run:

```bash
sudo python3 ubuntu-wp-health.py --seconds 30
```

Browse the slow pages while it samples. Repeat during peak traffic.
Requires Python 3, with no pip packages, sysstat, or iotop dependency.
Read-only: no configuration edits, restarts, package installation, or database
writes. No application query contents or passwords are printed.

## Options

```bash
# Structured output for comparison or monitoring.
sudo python3 ubuntu-wp-health.py --seconds 30 --json > health.json

# Skip database checks.
sudo python3 ubuntu-wp-health.py --skip-db

# Use an existing, permission-restricted MariaDB client credentials file.
sudo python3 ubuntu-wp-health.py --defaults-extra-file=/root/.my.cnf
```

MariaDB checks use the existing `mariadb` or `mysql` client and local
authentication. On many Ubuntu installations, sudo permits root socket login.
If login fails, database checks are explicitly marked unavailable; OS checks
still run. Never put passwords on the command line or share credentials files.
Report files may contain local process names and PIDs.

## Reading the report

The script samples `/proc` counters equivalent to the key measurements from
`free`, `vmstat`, `iostat`, and process I/O monitoring. Rates cover the actual
sample interval, not time since boot. Load still covers 1/5/15 minutes.

- **NO PRESSURE DETECTED IN THIS SAMPLE:** no warning threshold crossed; not a
  guarantee of peak capacity or proof that every dependency was checked.
- **CHECK WARNINGS:** investigate the accompanying recommendations.
- **INFO:** context or unavailable checks, not necessarily a fault.
- Exit code `0`: no warnings; `1`: warnings; `2`: invalid invocation. Unexpected
  runtime failures also exit nonzero.

| Signal | Approximate warning threshold |
| --- | --- |
| CPU busy | 85%, averaged across vCPUs |
| I/O wait | 10% |
| CPU steal | 5% |
| One-minute load | Greater than vCPU count |
| Available RAM | Below 10% |
| Swapping | Any activity; investigate whether sustained |
| Disk latency | 20 ms, with at least 20 reads or writes |
| InnoDB cache reads | Physical/logical reads above 1%, at least 100 physical reads |
| InnoDB free-page waits | Any increase |

These are heuristics, not universal targets. Cold caches and batch scans can
cause cache misses without user-facing problems. Disk utilization alone is not
used to diagnose saturation. No swap is informational when RAM is plentiful.

## Next actions

- **High disk latency + MariaDB reads:** inspect cache sizing, query plans,
  indexes, and volume limits. More CPU is not the first remedy.
- **High CPU + PHP work:** inspect slow requests/plugins and caching.
- **Memory pressure:** inspect consumers before increasing caches or workers.
- **Healthy metrics but slow pages:** investigate query locks, external APIs,
  application errors, and PHP/web-server logs. No HTTP requests are made here.
- **EC2 T3:** check CloudWatch `CPUCreditBalance` and, in Unlimited mode,
  `CPUSurplusCreditsCharged`. Check EBS metrics and limits for your volume type.
  The script does not query AWS or prove throttling from a flat I/O rate.

Our earlier fix increased the buffer pool from 128 MiB to 1 GiB because of
measured database reads and available RAM. This is not a universal setting.
The checker verifies the live value, not restart persistence.

## Limitations

- Root is recommended for process I/O visibility. Processes that exit during
  sampling cannot be attributed. Cached I/O and writeback mean process totals
  need not match device totals.
- D-state tasks are a point-in-time snapshot, not a blocked-time measurement.
- Device-mapper/RAID and underlying disks may describe the same I/O: do not sum
  every row. Device names do not guarantee dedicated physical NVMe performance.
- Service status is informational. LiteSpeed unit names can differ; MariaDB
  may use either `mariadb` or `mysql`, not both.
- Averages may hide short spikes or single-core saturation. Database sampling
  spans slightly longer than OS sampling. Run on the host, not in a restricted
  container.

Additional raw evidence, if these tools are installed:

```bash
uptime
free -h
vmstat 1 10
iostat -y -xz 1 10
sudo iotop -oP
```

Ignore the first `vmstat` row (since-boot averages). With `iotop -a`, process
values are accumulated bytes rather than instantaneous rates.
