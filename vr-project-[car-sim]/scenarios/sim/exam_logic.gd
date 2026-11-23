class_name ExamLogic
extends RefCounted
## One attempt at a scenario as a pure reducer: each tick it runs every rule on the tick's
## [RuleFrame], folds their results into the session (faults with their dedupe, steps, the end of
## the attempt), and returns the changes and events. Commands from the UI (begin, abort, restart)
## are reducers too, applied outside a tick.
##
## Events: [code]&"briefing"[/code], [code]&"started"[/code], [code]&"step_changed"[/code] (data:
## step, the index), [code]&"fault"[/code] (data: record), [code]&"finished"[/code] (data: result),
## and [code]&"restart"[/code].

const DEDUPE_WINDOW := 1.0


## The exam system: one tick of the attempt.
static func run(world: World, dt: float) -> Delta:
	var d := Delta.new()
	var id := Schema.single(world, Schema.SESSION)
	if id == 0 or world.get_value(Schema.SESSION, id, &"state") != ExamSession.State.RUNNING:
		return d
	var sess := _session(world, id)
	sess.elapsed += dt
	var definition: ScenarioDefinition = sess.definition
	var rules := _rules(world)
	if definition.time_limit > 0.0 and sess.elapsed >= definition.time_limit:
		_finish(world, sess, ScenarioResult.TIMEOUT, rules, dt, d)
		return _write(d, id, sess, rules)
	var eliminated := false
	var f := RuleFrame.build(world, dt, sess.elapsed, _current(sess))
	for k in rules.ids.size():
		if sess.state != ExamSession.State.RUNNING:
			break
		# A rule ending a step earlier in the tick moves the later ones on to the next step.
		f.current_step = _current(sess)
		var step: Callable = rules.step[k]
		var result: RuleResult = step.call(rules.params[k], rules.state[k], f,
			_live(rules.active_steps[k], sess))
		rules.state[k] = result.state
		eliminated = _fold(sess, rules.ids[k], result, d) or eliminated
		if result.complete and sess.state == ExamSession.State.RUNNING:
			_finish(world, sess, ScenarioResult.COMPLETED, rules, dt, d)
	if eliminated and sess.state == ExamSession.State.RUNNING:
		_finish(world, sess, ScenarioResult.ELIMINATED, rules, dt, d)
	return _write(d, id, sess, rules)


## Starts the attempt after the briefing.
static func begin(world: World) -> Delta:
	var d := Delta.new()
	var id := Schema.single(world, Schema.SESSION)
	if id == 0 or world.get_value(Schema.SESSION, id, &"state") != ExamSession.State.BRIEFING:
		return d
	d.write(Schema.SESSION, id, &"state", ExamSession.State.RUNNING)
	d.emit(WorldEvent.new(&"started", id))
	if world.get_value(Schema.SESSION, id, &"step_count") > 0:
		d.emit(WorldEvent.new(&"step_changed", id, {step = 0}))
	return d


## Ends the attempt as aborted; before it started, it just ends.
static func abort(world: World) -> Delta:
	var d := Delta.new()
	var id := Schema.single(world, Schema.SESSION)
	if id == 0:
		return d
	var state: int = world.get_value(Schema.SESSION, id, &"state")
	if state == ExamSession.State.BRIEFING:
		return d.write(Schema.SESSION, id, &"state", ExamSession.State.FINISHED)
	if state != ExamSession.State.RUNNING:
		return d
	var sess := _session(world, id)
	var rules := _rules(world)
	_finish(world, sess, ScenarioResult.ABORTED, rules, 0.0, d)
	return _write(d, id, sess, rules)


## Records a fault reported from outside the rules, such as by a UI or an instructor, from
## [param source] (any id; repeats from it within the dedupe window are one fault). An eliminating
## fault ends the attempt.
static func report(world: World, fault: FaultDef, at: Vector3, source := 0, key: Variant = null) -> Delta:
	var d := Delta.new()
	var id := Schema.single(world, Schema.SESSION)
	if id == 0 or world.get_value(Schema.SESSION, id, &"state") != ExamSession.State.RUNNING:
		return d
	var sess := _session(world, id)
	var rules := _rules(world)
	if _report(sess, source, fault, at, key, d):
		_finish(world, sess, ScenarioResult.ELIMINATED, rules, 0.0, d)
	return _write(d, id, sess, rules)


static func restart(world: World) -> Delta:
	return Delta.new().emit(WorldEvent.new(&"restart", Schema.single(world, Schema.SESSION)))


## Whether a rule with [param steps] as its active steps acts now: during them, or always when it
## has none.
static func _live(steps: PackedInt64Array, sess: Dictionary) -> bool:
	if sess.state != ExamSession.State.RUNNING:
		return false
	return steps.is_empty() or steps.has(_current(sess))


static func _current(sess: Dictionary) -> int:
	return sess.steps_completed if sess.steps_completed < sess.step_count else -1


## Folds [param result] into the session: faults (deduplicated) and step completion; the last
## step's completion marks the result complete. Returns whether a fault eliminates.
static func _fold(sess: Dictionary, rule: int, result: RuleResult, d: Delta) -> bool:
	var eliminated := false
	for fault: Array in result.faults:
		eliminated = _report(sess, rule, fault[0], fault[1], fault[2], d) or eliminated
	if result.complete_step >= 0 and result.complete_step == _current(sess):
		if sess.steps_completed + 1 >= sess.step_count:
			result.complete = true
		else:
			sess.steps_completed += 1
			d.emit(WorldEvent.new(&"step_changed", 0, {step = sess.steps_completed}))
	return eliminated


static func _report(sess: Dictionary, source: int, def: FaultDef, at: Vector3, key: Variant,
		d: Delta) -> bool:
	if sess.state != ExamSession.State.RUNNING:
		return false
	if def == null:
		push_error("Rule %d reported a fault with no FaultDef" % source)
		return false
	var dedupe := "%d:%s:%s" % [source, def.id, key]
	var last: Dictionary = sess.last_report
	if last.has(dedupe) and sess.elapsed - float(last[dedupe]) < DEDUPE_WINDOW:
		return false
	# The world's faults and dedupe table are copied only now, when a fault changes them; entries
	# past the window can no longer hold a report back, so they are left out of the copy.
	if not sess.get("reported", false):
		sess.reported = true
		var kept := {}
		for entry: String in last:
			if sess.elapsed - float(last[entry]) < DEDUPE_WINDOW:
				kept[entry] = last[entry]
		last = kept
		sess.last_report = kept
		sess.faults = (sess.faults as Array).duplicate()
	last[dedupe] = sess.elapsed
	var record := FaultRecord.new(def, sess.elapsed, at)
	sess.faults.append(record)
	d.emit(WorldEvent.new(&"fault", 0, {record = record}))
	return (sess.definition as ScenarioDefinition).policy.is_eliminating(def)


## Ends the attempt for [param reason]: every rule with a finish closes what it has open (its last
## faults still count), then the attempt is scored.
static func _finish(world: World, sess: Dictionary, reason: StringName, rules: Dictionary,
		dt: float, d: Delta) -> void:
	var f := RuleFrame.build(world, dt, sess.elapsed, _current(sess))
	for k in rules.ids.size():
		var finish: Callable = rules.finish[k]
		if not finish.is_valid():
			continue
		var result: RuleResult = finish.call(rules.params[k], rules.state[k], f,
			_live(rules.active_steps[k], sess))
		rules.state[k] = result.state
		for fault: Array in result.faults:
			_report(sess, rules.ids[k], fault[0], fault[1], fault[2], d)
	if reason == ScenarioResult.COMPLETED:
		sess.steps_completed = sess.step_count
	sess.state = ExamSession.State.FINISHED
	var definition: ScenarioDefinition = sess.definition
	var records: Array[FaultRecord] = []
	records.assign(sess.faults)
	var result := ScenarioResult.new()
	result.reason = reason
	result.faults = records
	result.duration = sess.elapsed
	result.steps_completed = sess.steps_completed
	result.step_count = sess.step_count
	result.scenario_id = definition.id
	result.scenario_title = definition.title
	result.policy = definition.policy
	var score := definition.policy.evaluate(records)
	result.passed = score.passed and reason == ScenarioResult.COMPLETED
	result.failing_tier = score.failing_tier
	sess.result = result
	d.emit(WorldEvent.new(&"finished", 0, {result = result}))


## The session's columns as values. Its faults and dedupe table are the world's own until a
## fault is reported (its [code]reported[/code] key), which copies them.
static func _session(world: World, id: int) -> Dictionary:
	var s := world.store(Schema.SESSION)
	var sess := {}
	for column: StringName in s.columns:
		sess[column] = s.get_value(id, column)
	sess.reported = false
	return sess


## The rules, read from their columns: [code]{ids, step, finish, params, state, active_steps,
## before}[/code], each an array by row. Rules are spawned in scene order and never removed, so
## row order is scene order. [code]state[/code] is a copy to fold this tick's states into;
## [code]before[/code] the world's, to write only those that changed.
static func _rules(world: World) -> Dictionary:
	var s := world.store(Schema.RULE)
	if s == null:
		return {ids = PackedInt64Array(), step = [], finish = [], params = [], state = [],
			active_steps = [], before = []}
	var states: Array = s.column(&"state")
	return {ids = s.ids, step = s.column(&"step"), finish = s.column(&"finish"),
		params = s.column(&"params"), state = states.duplicate(),
		active_steps = s.column(&"active_steps"), before = states}


static func _write(d: Delta, id: int, sess: Dictionary, rules: Dictionary) -> Delta:
	for k in rules.ids.size():
		if rules.state[k] != rules.before[k]:
			d.write(Schema.RULE, rules.ids[k], &"state", rules.state[k])
	var s := _changed_columns(sess)
	for column: StringName in s:
		d.write(Schema.SESSION, id, column, s[column])
	return d


## The session columns a tick may change, with their values: the faults and dedupe table only
## once a fault was reported.
static func _changed_columns(sess: Dictionary) -> Dictionary:
	var out := {state = sess.state, elapsed = sess.elapsed, steps_completed = sess.steps_completed,
		result = sess.result}
	if sess.reported:
		out.faults = sess.faults
		out.last_report = sess.last_report
	return out
