#!/usr/bin/env python3

import sys

with open(sys.argv[1], "rt") as f:
    text = f.readlines()

matches = 2
skip_next = False
result = []
for l in text:
    if skip_next:
        skip_next = False
        continue
    if matches and ("pool compile_job_pool" in l or "pool link_job_pool" in l):
        matches -= 1
        skip_next = True
    else:
        result.append(l)

with open(sys.argv[1], "wt") as f:
    f.write("".join(result))
