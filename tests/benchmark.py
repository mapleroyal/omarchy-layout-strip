#!/usr/bin/env python3
"""Read-only transport benchmark; does not register regions or dispatch actions."""
import argparse
import json
from pathlib import Path
import resource
import statistics
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--monitor',required=True)
parser.add_argument('--route',choices=('helper','direct'),default='direct')
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
if args.route=='helper':
    command=[str(Path.home()/'.local/bin/hypr-tape-bar'),'snapshot','--monitor',args.monitor]
else:
    command=json.loads(subprocess.check_output(['node','-e',
        'process.stdout.write(JSON.stringify(require(process.argv[1]).snapshots([process.argv[2]])))',
        str(ROOT/'plugin/Protocol.js'),args.monitor],text=True))
walls=[]; cpus=[]; columns=[]
for index in range(35):
    before=resource.getrusage(resource.RUSAGE_CHILDREN)
    start=time.perf_counter()
    result=subprocess.run(command,check=True,capture_output=True,text=True,timeout=5)
    elapsed=(time.perf_counter()-start)*1000
    after=resource.getrusage(resource.RUSAGE_CHILDREN)
    response=json.loads(result.stdout)
    if response.get('ok') is not True:raise RuntimeError(response)
    snapshots=response.get('snapshots',[response])
    if not all(s.get('ok') is True for s in snapshots):raise RuntimeError(response)
    if index>=5:
        walls.append(elapsed)
        cpus.append((after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime)*1000)
        columns.append(sum(len(s['columns']) for s in snapshots))
summary={'route':args.route,'samples':len(walls),'warmups':5,
         'wall_median_ms':statistics.median(walls),'wall_p95_ms':sorted(walls)[28],
         'child_cpu_mean_ms':statistics.mean(cpus),'column_counts':sorted(set(columns)),
         'raw_wall_ms':walls,'raw_child_cpu_ms':cpus,
         'scope':'Completed child CPU only; excludes shell/compositor CPU and power. Sequential read-only requests under current desktop load.'}
args.output.write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({key:value for key,value in summary.items() if not key.startswith('raw_')},indent=2))
