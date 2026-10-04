extends RefCounted
# Original MIT. Private ADR011 decimal arithmetic; no absolute tick conversion.
const U64 = preload("res://simulation/uint64.gd")

static func _result(value: Variant, error: String = "") -> Dictionary:
	return {"ok":error.is_empty(),"error":error,"value":value}

static func subtract(newer: Variant, older: Variant) -> Dictionary:
	if typeof(newer)!=TYPE_STRING or typeof(older)!=TYPE_STRING or not U64.valid(newer) or not U64.valid(older) or U64.compare(newer,older)<0:
		return _result(null,"Invalid or reversed uint64 subtraction")
	var result: String = ""
	var borrow: int = 0
	for offset in newer.length():
		var a: int = newer.unicode_at(newer.length()-1-offset)-48-borrow
		var b: int = older.unicode_at(older.length()-1-offset)-48 if offset<older.length() else 0
		borrow=1 if a<b else 0
		result=String.chr(48+a-b+10*borrow)+result
	while result.length()>1 and result[0]=="0":
		result=result.substr(1)
	return _result(result) if U64.valid(result) else _result(null,"Invalid uint64 difference")

static func add_small(tick: Variant, amount: Variant) -> Dictionary:
	if typeof(tick)!=TYPE_STRING or not U64.valid(tick) or typeof(amount)!=TYPE_INT or amount<0 or amount>144000:
		return _result(null,"Invalid bounded uint64 addition")
	var result: String = ""
	var carry: int = amount
	for offset in tick.length():
		var total: int = tick.unicode_at(tick.length()-1-offset)-48+carry
		result=String.chr(48+total%10)+result
		carry=total/10
	if carry>0:
		result=str(carry)+result
	return _result(result) if U64.valid(result) else _result(null,"Uint64 addition exhausted")

static func bounded_difference(newer: Variant, older: Variant, limit: int = 144000) -> Dictionary:
	if limit<0 or limit>144000:
		return _result(null,"Invalid difference bound")
	var difference: Dictionary = subtract(newer,older)
	if not difference.ok or U64.compare(difference.value,str(limit))>0:
		return _result(null,"Uint64 difference exceeds bound or is invalid")
	return _result(int(difference.value))
