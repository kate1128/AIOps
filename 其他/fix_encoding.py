import os
import glob

base = os.path.join("04-中间件", "中间件列表")
files = glob.glob(f"{base}/**/*.md", recursive=True)

for fp in sorted(files):
    with open(fp, "rb") as f:
        data = f.read()
    
    # Count U+FFFD (EF BF BD)
    count_fffd = data.count(b'\xef\xbf\xbd')
    # Count ASCII '?' - but we only want those that look suspicious
    count_qm = data.count(b'\x3f')
    
    print(f"{count_fffd:3d} FFFD + ??? = in {fp}")
