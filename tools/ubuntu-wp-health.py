#!/usr/bin/env python3
"""Read-only Ubuntu / LiteSpeed / WordPress / MariaDB health sampler."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def read(path):
    try:
        return Path(path).read_text()
    except (OSError, UnicodeError):
        return ""


def command(args, timeout=8):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def memory():
    return {line.split(':')[0]: int(line.split()[1]) * 1024
            for line in read('/proc/meminfo').splitlines()}


def cpu():
    return list(map(int, read('/proc/stat').splitlines()[0].split()[1:9]))


def disks():
    result = {}
    for line in read('/proc/diskstats').splitlines():
        fields = line.split()
        name = fields[2]
        # Only whole devices; exclude loop, RAM, and partition devices.
        if not Path('/sys/block', name).exists() or name.startswith(('loop', 'ram', 'zram')):
            continue
        result[name] = list(map(int, fields[3:]))
    return result


def processes():
    result = {}
    for directory in Path('/proc').glob('[0-9]*'):
        try:
            stat = (directory / 'stat').read_text().rsplit(')', 1)[1].split()
            values = dict(line.split(':', 1) for line in (directory / 'io').read_text().splitlines())
            result[directory.name] = {
                'name': (directory / 'comm').read_text().strip(),
                'start': stat[19],
                'state': stat[0],
                'read': int(values['read_bytes']),
                'write': int(values['write_bytes']),
            }
        except (OSError, ValueError, IndexError, KeyError):
            continue
    return result


def vm():
    return dict(line.split() for line in read('/proc/vmstat').splitlines())


def database(client, defaults):
    if not client:
        return None
    args = [client]
    if defaults:
        args.append('--defaults-extra-file=' + defaults)
    args += ['--batch', '--skip-column-names', '--connect-timeout=3', '-e', """
SHOW GLOBAL VARIABLES WHERE Variable_name IN
('innodb_buffer_pool_size','innodb_page_size');
SHOW GLOBAL STATUS WHERE Variable_name IN
('Uptime','Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads',
'Innodb_buffer_pool_wait_free','Threads_running','Threads_connected');
"""]
    output = command(args)
    if not output:
        return None
    try:
        return {key.lower(): int(value) for key, value in
                (line.split('\t', 1) for line in output.splitlines())}
    except ValueError:
        return None


def snapshot():
    return {'cpu': cpu(), 'disk': disks(), 'vm': vm(), 'process': processes()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=15, help='Sample duration, 5–300 seconds (default: 15)')
    parser.add_argument('--defaults-extra-file', help='MariaDB client credentials file; never put passwords on the command line')
    parser.add_argument('--skip-db', action='store_true', help='Do not query MariaDB')
    parser.add_argument('--json', action='store_true', help='Print machine-readable JSON instead')
    args = parser.parse_args()
    if not 5 <= args.seconds <= 300:
        parser.error('--seconds must be between 5 and 300')
    if not Path('/proc/stat').exists():
        parser.error('Run this script on the Ubuntu/Linux server, not on your laptop.')

    client = None if args.skip_db else (shutil.which('mariadb') or shutil.which('mysql'))
    db1 = database(client, args.defaults_extra_file)
    db_start = time.monotonic()
    first = snapshot()
    started = time.monotonic()
    if not args.json:
        print('Sampling for {} seconds. Browse the slow pages now…'.format(args.seconds), flush=True)
    time.sleep(args.seconds)
    last = snapshot()
    elapsed = time.monotonic() - started
    db2 = database(client, args.defaults_extra_file)
    db_elapsed = time.monotonic() - db_start
    mem = memory()
    findings = []

    def note(level, text):
        findings.append({'level': level, 'message': text})

    delta = [max(0, b - a) for a, b in zip(first['cpu'], last['cpu'])]
    total = sum(delta) or 1
    percentages = {name: round(100 * delta[index] / total, 2) for name, index in
                   [('busy', 0), ('system', 2), ('idle', 3), ('iowait', 4), ('steal', 7)]}
    busy = 100 * sum(delta[i] for i in (0, 1, 2, 5, 6)) / total
    percentages['busy'] = round(busy, 2)
    cores = os.cpu_count() or 1
    loads = os.getloadavg()
    if busy >= 85:
        note('WARN', 'CPU busy {:.1f}%. Inspect top/htop; tune expensive PHP/database work before upgrading.'.format(busy))
    if percentages['iowait'] >= 10:
        note('WARN', 'High I/O wait. Inspect disk latency and top readers below; CPU upgrades may not help.')
    if percentages['steal'] >= 5:
        note('WARN', 'Elevated CPU steal. Check instance limits and hosting contention; steal alone does not identify the cause.')
    if loads[0] > cores:
        note('WARN', 'One-minute load exceeds vCPU count. Load includes runnable AND uninterruptible tasks; not necessarily CPU overload.')

    available = mem.get('MemAvailable', mem.get('MemFree', 0))
    available_pct = 100 * available / mem['MemTotal']
    if available_pct < 10:
        note('WARN', 'Less than 10% RAM available. Inspect process memory; avoid increasing the database cache now.')
    if mem.get('SwapTotal', 0) == 0:
        note('INFO', 'No swap configured. Not a fault with ample RAM, but memory spikes have less safety margin.')
    page_size = os.sysconf('SC_PAGE_SIZE')
    swap_rates = {key: max(0, int(last['vm'].get(key, 0)) - int(first['vm'].get(key, 0))) * page_size / elapsed
                  for key in ('pswpin', 'pswpout')}
    if sum(swap_rates.values()) > 0:
        note('WARN', 'Swap activity occurred during the sample. Check for sustained swapping and memory pressure.')

    disk_report = []
    for name, end in last['disk'].items():
        if name not in first['disk']:
            continue
        d = [b - a for a, b in zip(first['disk'][name], end)]
        if min(d[i] for i in (0, 2, 3, 4, 6, 7, 9, 10)) < 0:
            continue
        row = {'device': name, 'reads_s': round(d[0] / elapsed, 2),
               'writes_s': round(d[4] / elapsed, 2),
               'read_MiB_s': round(d[2] * 512 / elapsed / 1048576, 3),
               'write_MiB_s': round(d[6] * 512 / elapsed / 1048576, 3),
               'read_await_ms': round(d[3] / d[0], 2) if d[0] else None,
               'write_await_ms': round(d[7] / d[4], 2) if d[4] else None,
               'queue': round(d[10] / elapsed / 1000, 2),
               'util_pct': round(d[9] / elapsed / 10, 2)}
        disk_report.append(row)
        if (d[0] >= 20 and row['read_await_ms'] >= 20) or (d[4] >= 20 and row['write_await_ms'] >= 20):
            note('WARN', name + ': elevated disk latency (includes queueing). Inspect readers/writers, volume IOPS limits and cloud storage metrics.')

    io_processes = []
    for pid, end in last['process'].items():
        start = first['process'].get(pid)
        if not start or start['start'] != end['start']:
            continue
        r, w = max(0, end['read'] - start['read']), max(0, end['write'] - start['write'])
        if r or w:
            io_processes.append({'pid': pid, 'name': end['name'],
                                 'read_MiB_s': round(r / elapsed / 1048576, 4),
                                 'write_MiB_s': round(w / elapsed / 1048576, 4)})
    io_processes.sort(key=lambda p: p['read_MiB_s'] + p['write_MiB_s'], reverse=True)
    blocked = [{'pid': pid, 'name': p['name']} for pid, p in last['process'].items() if p['state'] == 'D']
    if blocked:
        note('INFO', 'Uninterruptible (D-state) tasks observed; commonly, but not always, waiting on storage.')
    if os.geteuid() != 0:
        note('INFO', 'Not root: process I/O visibility is incomplete. Rerun with sudo for all processes and local database socket authentication.')

    db_report = None
    if db1 and db2:
        db_report = {'buffer_pool_MiB': round(db2.get('innodb_buffer_pool_size', 0) / 1048576, 1),
                     'threads_running': db2.get('threads_running'),
                     'threads_connected': db2.get('threads_connected')}
        keys = ('innodb_buffer_pool_read_requests', 'innodb_buffer_pool_reads', 'innodb_buffer_pool_wait_free')
        if all(k in db1 and k in db2 and db2[k] >= db1[k] for k in keys) and db2.get('uptime', 0) >= db1.get('uptime', 0):
            logical, physical, waits = [db2[k] - db1[k] for k in keys]
            ratio = 100 * physical / logical if logical else None
            db_report.update({'logical_reads': logical, 'physical_reads': physical,
                              'physical_reads_s': round(physical / db_elapsed, 2),
                              'physical_to_logical_pct': round(ratio, 2) if ratio is not None else None,
                              'buffer_pool_wait_free_delta': waits})
            if waits:
                note('WARN', 'InnoDB waited for free buffer pages. Check flushing/storage pressure and cache sizing.')
            if physical >= 100 and ratio is not None and ratio > 1:
                note('WARN', 'Noticeable InnoDB cache misses. Correlate with latency; inspect cache size, query plans and workload. Cold caches can also cause this.')
        else:
            note('INFO', 'Database counters reset or were unavailable; cache-rate evaluation skipped.')
        if db_report['buffer_pool_MiB'] <= 128 and mem['MemTotal'] >= 4 * 1024**3:
            note('INFO', 'InnoDB cache is 128 MiB or smaller. If database reads cause delays and RAM allows, consider a larger cache; do not size it from total RAM alone.')
    elif not args.skip_db:
        note('INFO', 'MariaDB checks unavailable: install/use the existing client and verify local login, or supply --defaults-extra-file. No credentials were printed.')

    services = {}
    if shutil.which('systemctl'):
        for service in ('lsws', 'mariadb', 'mysql'):
            services[service] = command(['systemctl', 'is-active', service]) or 'inactive/unknown'
    note('INFO', 'T3/T-family EC2: check CloudWatch CPUCreditBalance and, in Unlimited mode, CPUSurplusCreditsCharged. Local samples cannot establish credit health.')
    report = {'sample_seconds': round(elapsed, 2), 'vcpus': cores, 'load_1_5_15': loads,
              'cpu_pct': percentages, 'memory_available_GiB': round(available / 1024**3, 2),
              'memory_total_GiB': round(mem['MemTotal'] / 1024**3, 2),
              'swap_total_GiB': round(mem.get('SwapTotal', 0) / 1024**3, 2),
              'swap_bytes_s': swap_rates, 'disks': disk_report, 'top_process_io': io_processes[:8],
              'blocked_tasks': blocked, 'database': db_report, 'services': services, 'findings': findings}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print('\nRESULT: ' + ('CHECK WARNINGS' if any(f['level'] == 'WARN' for f in findings) else 'NO PRESSURE DETECTED IN THIS SAMPLE'))
        print('CPU busy {busy}% | idle {idle}% | I/O wait {iowait}% | steal {steal}%'.format(**percentages))
        print('Load: {} | {} vCPUs | available RAM: {} / {} GiB'.format(
            ' / '.join('{:.2f}'.format(x) for x in loads), cores,
            report['memory_available_GiB'], report['memory_total_GiB']))
        for row in disk_report:
            print('DISK ' + json.dumps(row))
        print('DATABASE: ' + (json.dumps(db_report) if db_report else 'not checked / unavailable'))
        print('SERVICES: ' + json.dumps(services))
        print('TOP PROCESS I/O (MiB/s; excludes processes that exited during sampling):')
        for row in io_processes[:8]:
            print('  ' + json.dumps(row))
        for finding in findings:
            print('[{level}] {message}'.format(**finding))
        print('\nHeuristics, not a capacity guarantee. Repeat under representative peak traffic.')
        print('Disk layers (e.g. dm + NVMe) may represent the same I/O: do not add their totals.')
        print('Read-only: no config changes, restarts, query contents, or password output.')
    return 1 if any(f['level'] == 'WARN' for f in findings) else 0


if __name__ == '__main__':
    sys.exit(main())
