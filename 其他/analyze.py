import os
base = r'C:\Users\12983\github_dev\smartvision2\04-middleware\中间件列表'
total = 0
for dirpath, dirnames, filenames in os.walk(base):
    for fn in filenames:
        if fn.endswith('.md'):
            fpath = os.path.join(dirpath, fn)
            with open(fpath, 'rb') as f:
                data = f.read()
            idx = 0
            count_fffd = 0
            count_3f = 0
            while idx < len(data):
                if idx + 2 < len(data) and data[idx:idx+3] == b'\xef\xbf\xbd':
                    count_fffd += 1
                    idx += 3
                elif data[idx] == 0x3f:
                    count_3f += 1
                    idx += 1
                else:
                    idx += 1
            if count_fffd + count_3f > 0:
                total += 1
                print(f'{fn}: {count_fffd} U+FFFD + {count_3f} 0x3F = {count_fffd+count_3f} total')
print(f'Total files with issues: {total}')
