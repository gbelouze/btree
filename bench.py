import subprocess
import re
import matplotlib.pyplot as plt

F = 20
N = 6_000_000

sizes = []
tops = []
X = range(100, 2_000, 100)
for cache in X:
    res = subprocess.run(
        f"dune exec -- ./bench/bench.exe --minimal --clear --fanout {F} --page 5000 -n {N} -vv --cache {cache}",
        capture_output=True,
        shell=True)
    size_match = re.search(r"\[\+\d+ms\]  Cache size is (\d+) Mb",
                           res.stdout.decode())
    top_match = re.search(r" *Max memory usage : (\d+) Mb",
                          res.stdout.decode())
    size = int(size_match.group(1))
    top = int(top_match.group(1))
    print(f"[{cache=}] {size}/{top}")
    sizes.append(size)
    tops.append(top)

plt.plot(X, sizes)
plt.plot(X, tops)

plt.show()
