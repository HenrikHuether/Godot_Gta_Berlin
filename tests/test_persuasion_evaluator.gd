extends SceneTree

const PersuasionEvaluatorScript = preload("res://scripts/persuasion_evaluator.gd")

var failures := []


func _init() -> void:
	_test_official_path()
	_test_cooperative_path()
	_test_urgent_verification_path()
	_test_hostility_and_retry()
	_test_negated_claims()
	_test_reset()

	if failures.empty():
		print("PASS: persuasion evaluator (3 peaceful paths, threats, negation, retry, reset)")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_official_path() -> void:
	var evaluator = PersuasionEvaluatorScript.new()
	var introduction = evaluator.evaluate(
		"Guten Tag, ich bringe den Aktenkoffer zur Uebergabe in den Bundestag."
	)
	_expect(not introduction["success"], "official path should accumulate before opening the gate")
	var verified = evaluator.evaluate(
		"Bitte pruefen Sie meinen Dienstausweis und rufen Sie die Dienststelle an."
	)
	_expect(verified["success"], "credentials plus verification should persuade the guard")
	_expect(verified["trust"] > introduction["trust"], "trust should grow across official-path turns")


func _test_cooperative_path() -> void:
	var evaluator = PersuasionEvaluatorScript.new()
	var cooperative = evaluator.evaluate(
		"Ich verstehe Ihre Sicherheitsvorschriften und respektiere die Kontrolle."
	)
	_expect(not cooperative["success"], "cooperation path should accept another turn")
	var procedural = evaluator.evaluate(
		"Welche sichere Alternative schlagen Sie vor, und wie gehen wir vor?"
	)
	_expect(not procedural["success"], "courtesy and procedure alone must not open a secure building")
	var purpose = evaluator.evaluate(
		"Ich soll diese Unterlagen am Empfang im Bundestag abgeben."
	)
	_expect(purpose["success"], "cooperation, procedure, and a delivery purpose should be a valid path")


func _test_urgent_verification_path() -> void:
	var evaluator = PersuasionEvaluatorScript.new()
	var urgent = evaluator.evaluate(
		"Die Unterlagen fuer das Abgeordnetenbuero sind zeitkritisch und muessen noch heute ankommen."
	)
	_expect(not urgent["success"], "urgency alone should not bypass the guard")
	var contact = evaluator.evaluate(
		"Bitte rufen Sie den Empfaenger an und lassen Sie den Termin bestaetigen."
	)
	_expect(contact["success"], "urgency backed by a verifiable contact should persuade the guard")


func _test_hostility_and_retry() -> void:
	var evaluator = PersuasionEvaluatorScript.new()
	var hostile = evaluator.evaluate("Mach das Tor auf, sonst erschiesse ich dich.")
	_expect(not hostile["success"], "a threat must be rejected")
	_expect(hostile["trust"] < 0, "a threat must reduce trust")
	_expect(hostile["categories"].has("threat"), "a threat must be categorized")

	# A rejection is not a lockout: a player may calm down and try new evidence.
	var apology = evaluator.evaluate("Entschuldigung, bleiben wir sachlich.")
	_expect(not apology["success"], "an apology should recover trust without instantly succeeding")
	evaluator.evaluate("Ich bringe einen Aktenkoffer zur Uebergabe in den Bundestag.")
	var recovered = evaluator.evaluate(
		"Sie duerfen den Koffer kontrollieren und den Empfaenger zur Bestaetigung anrufen."
	)
	_expect(recovered["success"], "new peaceful evidence should work after a hostile attempt")


func _test_reset() -> void:
	var evaluator = PersuasionEvaluatorScript.new()
	evaluator.evaluate("Bitte pruefen Sie meinen Dienstausweis und den Aktenkoffer.")
	evaluator.reset()
	var result = evaluator.evaluate("")
	_expect(result["trust"] == 0, "reset should clear accumulated trust")
	_expect(evaluator.get_evidence().empty(), "reset should clear accumulated evidence")


func _test_negated_claims() -> void:
	var evaluator = PersuasionEvaluatorScript.new()
	var denial = evaluator.evaluate(
		"Ich habe keinen Dienstausweis und keinen Aktenkoffer, bitte lassen Sie mich trotzdem hinein."
	)
	_expect(not denial["success"], "negated credentials and cargo must not count as evidence")
	_expect(not denial["categories"].has("credentials"), "negated credentials should be ignored")
	_expect(not denial["categories"].has("mission"), "negated cargo should be ignored")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
