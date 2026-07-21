extends Reference
class_name PersuasionEvaluator

# A deterministic, local evaluator for the Bundestag guard dialogue.  It does
# not look for one magic sentence: different kinds of useful information build
# trust over any number of attempts.

const SUCCESS_TRUST := 5
const MIN_TRUST := -5
const MAX_TRUST := 10
const THREAT_PENALTY := 3
const REPEATED_EVIDENCE_GAIN := 1

const POSITIVE_CATEGORIES := [
	"credentials",
	"verification",
	"cooperation",
	"respect",
	"urgency",
	"procedure",
	"mission",
	"apology",
]

const CATEGORY_SCORES := {
	"credentials": 2,
	"verification": 2,
	"cooperation": 2,
	"respect": 1,
	"urgency": 1,
	"procedure": 2,
	"mission": 2,
	"apology": 2,
}

# Cues are deliberately stems and short phrases so natural German inflections
# are accepted.  Input is normalized to lower-case ASCII before matching.
const CATEGORY_CUES := {
	"credentials": [
		"dienstausweis", "ausweis", "bevollmaechtigt", "offizieller kurier",
		"dienstauftrag", "kurierauftrag", "regierungskurier", "termin",
		"angemeldet", "bundesministerium", "behoerde",
	],
	"verification": [
		"ueberpruef", "pruefen", "pruefung", "verifizier", "bestaetig",
		"rueckfrag", "rufen sie", "anrufen", "dienststelle", "leitstelle",
		"empfaenger", "begleitpapier", "auftragscode",
	],
	"cooperation": [
		"sie duerfen", "duerfen sie", "durchsuch", "kontrollier", "kontrolle",
		"scanner", "scannen", "koffer oeffnen", "inhalt zeigen", "begleiten",
		"sicherheitsvorschrift", "sicherheitskontrolle",
	],
	"respect": [
		"bitte", "danke", "guten tag", "verstehe", "respektier", "ruhig",
		"selbstverstaendlich", "kein problem", "in ordnung",
	],
	"urgency": [
		"dringend", "zeitkritisch", "frist", "sitzung beginnt", "beginnt gleich",
		"noch heute", "eilt", "sicherheitsrelevant",
	],
	"procedure": [
		"welcher weg", "welche alternative", "sichere alternative", "wie gehen wir vor",
		"wie koennen wir", "anmeldung", "zustandige stelle", "zustaendige stelle",
		"protokollier", "vorschlag", "vorgehensweise",
	],
	"mission": [
		"aktenkoffer", "unterlagen", "dokumente", "uebergabe", "ueberbringen",
		"abgeben", "bundestag", "regierungsviertel", "abgeordnetenbuero",
	],
	"apology": [
		"entschuldigung", "entschuldige", "tut mir leid", "war nicht so gemeint",
		"bleiben wir sachlich", "nehme ich zurueck",
	],
}

const THREAT_CUES := [
	"erschies", "toete", "toeten", "bring dich um", "bringe sie um", "umbringen",
	"spreng", "bedroh", "ich drohe", "gewalt", "zwing", "knall dich ab",
	"du wirst es bereuen", "sie werden es bereuen", "passiert etwas",
	"mach das tor auf", "mach die tuer auf", "oeffne das tor oder",
]

const NEGATION_WORDS := ["nicht", "kein", "keine", "keinen", "keinem", "keiner", "ohne", "nie"]

var _trust := 0
var _evidence := {}
var _seen_inputs := {}


func _init() -> void:
	reset()


func reset() -> void:
	_trust = 0
	_evidence.clear()
	_seen_inputs.clear()


func evaluate(text: String) -> Dictionary:
	var normalized := _normalize(text)
	if normalized.empty():
		return _result(
			"Ich habe nichts verstanden. Erklaeren Sie bitte, weshalb Sie passieren muessen.",
			false,
			["unclear"]
		)

	# A threat always overrides positive words in the same message.  It rejects
	# this attempt, but does not end the conversation, so de-escalation remains
	# possible on later attempts.
	if _matches_any(normalized, THREAT_CUES):
		_trust = max(MIN_TRUST, _trust - THREAT_PENALTY)
		_evidence["threat"] = int(_evidence.get("threat", 0)) + 1
		return _result(
			"Drohungen helfen Ihnen nicht. Treten Sie zurueck und bleiben Sie sachlich.",
			false,
			["threat"]
		)

	if normalized.split(" ", false).size() < 3:
		return _result(
			"Das ist zu wenig Kontext. Erklaeren Sie bitte Ihren Auftrag in einem vollstaendigen Satz.",
			false,
			["unclear"]
		)

	var matched := []
	for category in POSITIVE_CATEGORIES:
		if _matches_positive_cue(normalized, CATEGORY_CUES[category]):
			matched.append(category)

	if matched.empty():
		return _result(
			"Das reicht mir noch nicht. Nennen Sie Auftrag, Nachweis oder eine pruefbare Vorgehensweise.",
			false,
			["unclear"]
		)

	var is_new_wording := not _seen_inputs.has(normalized)
	_seen_inputs[normalized] = true
	var gained_trust := 0
	if is_new_wording:
		for category in matched:
			var previous_count := int(_evidence.get(category, 0))
			_evidence[category] = previous_count + 1
			if previous_count == 0:
				gained_trust += int(CATEGORY_SCORES[category])
			else:
				gained_trust += REPEATED_EVIDENCE_GAIN
		_trust = min(MAX_TRUST, _trust + gained_trust)

	var success := _trust >= SUCCESS_TRUST and _positive_category_count() >= 2 and _has_grounded_reason()
	if success:
		return _result(
			"In Ordnung. Ihre Angaben sind nachvollziehbar. Sie duerfen passieren.",
			true,
			matched
		)

	if not is_new_wording:
		return _result(
			"Diese Angaben habe ich bereits. Geben Sie mir bitte einen weiteren pruefbaren Grund.",
			false,
			matched
		)
	if matched.has("verification"):
		return _result(
			"Das kann ich pruefen. Fuer die Freigabe brauche ich noch etwas Kontext oder Kooperation.",
			false,
			matched
		)
	if matched.has("cooperation") or matched.has("procedure"):
		return _result(
			"Das ist konstruktiv. Erklaeren Sie mir noch, fuer wen die Uebergabe bestimmt ist.",
			false,
			matched
		)
	if matched.has("urgency"):
		return _result(
			"Dringlichkeit allein ersetzt keine Freigabe. Wie kann ich Ihren Auftrag pruefen?",
			false,
			matched
		)
	if not _has_grounded_reason():
		return _result(
			"Ihre Haltung ist vernuenftig. Was genau liefern Sie, oder welchen offiziellen Nachweis haben Sie?",
			false,
			matched
		)
	return _result(
		"Ich hoere Ihnen zu. Liefern Sie mir bitte noch einen unabhaengigen Nachweis.",
		false,
		matched
	)


func get_trust() -> int:
	return _trust


func get_evidence() -> Dictionary:
	return _evidence.duplicate(true)


func _positive_category_count() -> int:
	var count := 0
	for category in POSITIVE_CATEGORIES:
		if _evidence.has(category):
			count += 1
	return count


func _has_grounded_reason() -> bool:
	# Courtesy alone cannot open a government building. A valid route must be
	# anchored in the delivery itself or in official credentials, while the
	# second category may come from verification, cooperation, or procedure.
	var has_identity_or_purpose = _evidence.has("mission") or _evidence.has("credentials")
	var has_safe_process = _evidence.has("verification") or _evidence.has("cooperation") or _evidence.has("procedure")
	return has_identity_or_purpose and has_safe_process


func _matches_any(normalized: String, cues: Array) -> bool:
	for cue in cues:
		if normalized.find(String(cue)) != -1:
			return true
	return false


func _matches_positive_cue(normalized: String, cues: Array) -> bool:
	for cue_value in cues:
		var cue = String(cue_value)
		var search_from = 0
		while search_from < normalized.length():
			var position = normalized.find(cue, search_from)
			if position == -1:
				break
			if cue == "kein problem" or not _is_negated(normalized, position):
				return true
			search_from = position + max(1, cue.length())
	return false


func _is_negated(normalized: String, cue_position: int) -> bool:
	var prefix_start = max(0, cue_position - 28)
	var prefix = normalized.substr(prefix_start, cue_position - prefix_start).strip_edges()
	var words = prefix.split(" ", false)
	var first_relevant_word = max(0, words.size() - 3)
	for word_index in range(first_relevant_word, words.size()):
		if NEGATION_WORDS.has(String(words[word_index])):
			return true
	return false


func _normalize(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	# Godot stores UTF-8 strings; these replacements also accept native German
	# spelling while keeping the cue table ASCII-only.
	normalized = normalized.replace("ä", "ae")
	normalized = normalized.replace("ö", "oe")
	normalized = normalized.replace("ü", "ue")
	normalized = normalized.replace("ß", "ss")
	for punctuation in [".", ",", ";", ":", "!", "?", "\"", "'", "(", ")", "-", "_", "/", "\\"]:
		normalized = normalized.replace(punctuation, " ")
	while normalized.find("  ") != -1:
		normalized = normalized.replace("  ", " ")
	return normalized.strip_edges()


func _result(reply: String, success: bool, categories: Array) -> Dictionary:
	return {
		"reply": reply,
		"success": success,
		"trust": _trust,
		"categories": categories.duplicate(),
	}
