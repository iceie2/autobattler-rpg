from pathlib import Path
p=Path('scripts/combat/auto_battle_manager.gd')
s=p.read_text(encoding='utf-8')
start=s.index('\t\t"tempest_arc":\n')
end=s.index('\n\t\t"tide_ward":',start)
old=s[start:end]
body=old[old.index('\t\t\tif not tar: return'):]
body='\n'.join(line[2:] if line.startswith('\t\t') else line for line in body.splitlines())
helper='\nfunc _resolve_tempest_chain(caster: UnitBase, tar: UnitBase, opponents: Array) -> void:\n'+body+'\n'
s=s[:start]+'\t\t"tempest_arc":\n\t\t\tif tar: _begin_tempest_cast(caster, tar, opponents)\n'+s[end:]
s+=helper
p.write_text(s,encoding='utf-8')
