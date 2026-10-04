extends RefCounted
# Original MIT. Decimal wire identity never passes through signed int or double.
const MAXIMUM: String = "18446744073709551615"

static func valid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 20:
		return false
	if value.length() > 1 and value[0] == "0":
		return false
	for i in value.length():
		var digit: int = value.unicode_at(i)
		if digit < 48 or digit > 57:
			return false
	return compare(value, MAXIMUM) <= 0

static func compare(a: String, b: String) -> int:
	if a.length() != b.length():
		return -1 if a.length() < b.length() else 1
	return 0 if a == b else (-1 if a < b else 1)

static func increment(value: String) -> Dictionary:
	if not valid(value) or value == MAXIMUM:
		return {"ok":false,"error":"Invalid or exhausted uint64","value":null}
	var cursor: int = value.length()-1
	while cursor >= 0 and value.unicode_at(cursor) == 57:
		cursor -= 1
	if cursor < 0:
		return {"ok":true,"error":"","value":"1"+"0".repeat(value.length())}
	var result: String = value.substr(0,cursor)+String.chr(value.unicode_at(cursor)+1)+"0".repeat(value.length()-cursor-1)
	return {"ok":true,"error":"","value":result}

static func small_difference(newer: String, older: String, limit: int = 32) -> Dictionary:
	if not valid(newer) or not valid(older) or limit < 0 or limit > 4096 or compare(newer,older) < 0:
		return {"ok":false,"error":"Invalid bounded uint64 difference","value":null}
	var cursor: String = older
	for difference in range(limit+1):
		if cursor == newer:
			return {"ok":true,"error":"","value":difference}
		var next: Dictionary = increment(cursor)
		if not next.ok:
			break
		cursor = next.value
	return {"ok":false,"error":"uint64 difference exceeds bound","value":null}
