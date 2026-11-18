p = 'package/easyproxy/files/usr/lib/easyproxy/mihomo.sh'
s = open(p, encoding='utf-8').read()
old = "\t\tprintf 'unified-delay: true\\n'"
new = """\t\tprintf 'unified-delay: true\\n'
\t\t# Without this every manual selection (PROXY, a scene group, a single
\t\t# node) is lost on restart and silently falls back to the group's first
\t\t# entry - the panel would show "Netflix: 自动-日本" while traffic goes
\t\t# through 所有-自动.
\t\tprintf 'store-selected: true\\n'"""
assert old in s, 'anchor not found'
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('store-selected added')
