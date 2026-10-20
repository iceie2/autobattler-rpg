"""One-time replacement of the backed-up chain/cage prototype."""
from pathlib import Path
p=Path('scripts/combat/auto_battle_manager.gd')
s=p.read_text(encoding='utf-8')
start=s.index('const TEMPEST_CHARGE :=')
s=s[:start]+'''func _begin_tempest_circuit(caster: UnitBase, opponents: Array) -> void:
	var id: int = caster.get_instance_id()
	if not _tempest_circuits.has(id):
		_tempest_circuits[id] = TempestCircuit.new(self, caster)
	_tempest_circuits[id].begin(opponents)

func _tick_tempest_circuits(dt: float) -> void:
	for id in _tempest_circuits.keys():
		var circuit: TempestCircuit = _tempest_circuits[id]
		circuit.tick(dt)
		if not _is_alive(circuit.caster): _tempest_circuits.erase(id)

func _clear_tempest_circuits() -> void:
	for circuit in _tempest_circuits.values(): circuit.clear()
	_tempest_circuits.clear()
'''
s=s.replace('\t\t"tempest_arc":\n\t\t\tif tar: _begin_tempest_cast(caster, tar, opponents)', '\t\t"tempest_circuit":\n\t\t\t_begin_tempest_circuit(caster, opponents)')
s=s.replace('const TEMPEST_ARC_RANGE := 2.0\nconst TEMPEST_ARC_FALLOFF := 0.75\nconst TEMPEST_ARC_MAX_JUMPS := 5\n','')
s=s.replace('\t\tu.set_meta("tempest_casts", 0)\n','')
p.write_text(s,encoding='utf-8')
