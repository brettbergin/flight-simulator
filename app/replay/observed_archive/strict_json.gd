extends RefCounted
# Original MIT. ADR012 byte admission before the deliberately relaxed engine parser.
const MAX_BYTES: int = 8388608
const MAX_VALUES: int = 250000
const MAX_PISTON_VALUES: int = 400000
var data: PackedByteArray
var cursor: int = 0
var values: int = 0
var error: String = ""
var outer: bool = false
var _max_values: int = MAX_VALUES

static func scan(bytes: Variant, is_outer: bool = false) -> Dictionary:
	return _scan(bytes,is_outer,false)

# ADR022: only an already admitted archive2 envelope selects this fixed policy.
# The ordinary scan entry and every outer envelope retain the v1 node limit.
static func scan_piston_payload(bytes: Variant) -> Dictionary:
	return _scan(bytes,false,true)

static func _scan(bytes: Variant, is_outer: bool, piston_payload: bool) -> Dictionary:
	if is_outer and piston_payload:
		return {"ok":false,"error":"Piston payload policy cannot scan an outer envelope"}
	if typeof(bytes)!=TYPE_PACKED_BYTE_ARRAY or bytes.is_empty() or bytes.size()>MAX_BYTES:
		return {"ok":false,"error":"Archive byte bound or type rejected"}
	if not valid_utf8(bytes):
		return {"ok":false,"error":"Archive UTF8 is not a bounded scalar encoding"}
	var reader = new()
	reader.data=bytes
	reader.outer=is_outer
	reader._max_values=MAX_PISTON_VALUES if piston_payload else MAX_VALUES
	reader._space()
	reader._value(0,false)
	reader._space()
	if reader.error.is_empty() and reader.cursor!=bytes.size():
		reader.error="Trailing archive data"
	return {"ok":reader.error.is_empty(),"error":reader.error}

static func valid_utf8(bytes: PackedByteArray) -> bool:
	var i: int = 0
	while i<bytes.size():
		var first: int = bytes[i]
		if first<128:
			if first==0: return false
			i+=1
			continue
		var count: int = 0
		var code: int = 0
		var minimum: int = 0
		if first>=194 and first<=223:
			count=2; code=first&31; minimum=128
		elif first>=224 and first<=239:
			count=3; code=first&15; minimum=2048
		elif first>=240 and first<=244:
			count=4; code=first&7; minimum=65536
		else: return false
		if i+count>bytes.size(): return false
		for n in range(1,count):
			var next: int = bytes[i+n]
			if next<128 or next>191: return false
			code=(code<<6)|(next&63)
		if code<minimum or code>1114111 or (code>=55296 and code<=57343) or code==65279:
			return false
		i+=count
	return true

func _fail(message: String) -> void:
	if error.is_empty(): error=message

func _space() -> void:
	while cursor<data.size() and data[cursor] in [9,10,13,32]: cursor+=1

func _take(character: int) -> bool:
	if cursor<data.size() and data[cursor]==character:
		cursor+=1
		return true
	return false

func _value(depth: int, large_string: bool) -> void:
	if not error.is_empty(): return
	values+=1
	if values>_max_values: _fail("Archive value bound exceeded"); return
	if cursor>=data.size(): _fail("Truncated JSON value"); return
	var character: int = data[cursor]
	if character==123 or character==91:
		if depth>=16: _fail("Archive depth bound exceeded"); return
		if character==123: _object(depth+1)
		else: _array(depth+1)
	elif character==34:
		_string(false,large_string)
	elif character==116: _literal("true")
	elif character==102: _literal("false")
	elif character==110: _literal("null")
	elif character==45 or (character>=48 and character<=57): _integer()
	else: _fail("Invalid JSON value")

func _object(depth: int) -> void:
	cursor+=1
	_space()
	if _take(125): return
	var seen: Dictionary = {}
	while error.is_empty():
		if seen.size()>=16: _fail("Archive object member bound exceeded"); return
		if cursor>=data.size() or data[cursor]!=34: _fail("Expected literal JSON key"); return
		var key: String = _string(true,false)
		if not error.is_empty(): return
		if seen.has(key): _fail("Duplicate JSON key"); return
		seen[key]=true
		_space()
		if not _take(58): _fail("Expected JSON colon"); return
		_space()
		_value(depth,outer and depth==1 and key=="payload_json")
		_space()
		if _take(125): return
		if not _take(44): _fail("Expected JSON object separator"); return
		_space()
		if cursor>=data.size() or data[cursor]==125: _fail("Trailing JSON object comma"); return

func _array(depth: int) -> void:
	cursor+=1
	_space()
	if _take(93): return
	var count: int = 0
	while error.is_empty():
		count+=1
		if count>2401: _fail("Archive array bound exceeded"); return
		_value(depth,false)
		_space()
		if _take(93): return
		if not _take(44): _fail("Expected JSON array separator"); return
		_space()
		if cursor>=data.size() or data[cursor]==93: _fail("Trailing JSON array comma"); return

func _literal(literal: String) -> void:
	for code in literal.to_ascii_buffer():
		if cursor>=data.size() or data[cursor]!=code:
			_fail("Invalid JSON literal"); return
		cursor+=1

func _integer() -> void:
	var negative: bool = _take(45)
	if cursor>=data.size(): _fail("Truncated JSON integer"); return
	if data[cursor]==48:
		cursor+=1
		if negative: _fail("Negative zero integer rejected"); return
	else:
		if data[cursor]<49 or data[cursor]>57: _fail("Noncanonical JSON integer"); return
		var magnitude: int = 0
		while cursor<data.size() and data[cursor]>=48 and data[cursor]<=57:
			magnitude=magnitude*10+data[cursor]-48
			if magnitude>2401: _fail("JSON integer exceeds bounded fields"); return
			cursor+=1
	if cursor<data.size() and (data[cursor] in [43,45,46,69,101] or (data[cursor]>=48 and data[cursor]<=57)):
		_fail("Fractional, exponent or noncanonical JSON number rejected")

func _hex4() -> int:
	if cursor+4>data.size(): _fail("Truncated Unicode escape"); return -1
	var value: int = 0
	for unused in 4:
		var code: int = data[cursor]
		cursor+=1
		var digit: int = -1
		if code>=48 and code<=57: digit=code-48
		elif code>=65 and code<=70: digit=code-55
		elif code>=97 and code<=102: digit=code-87
		if digit<0: _fail("Invalid Unicode escape"); return -1
		value=(value<<4)|digit
	return value

func _string(key: bool, large: bool) -> String:
	cursor+=1
	var start: int = cursor
	var characters: int = 0
	var utf8_bytes: int = 0
	while error.is_empty() and cursor<data.size():
		var code: int = data[cursor]
		if code==34:
			var result: String = data.slice(start,cursor).get_string_from_ascii() if key else ""
			cursor+=1
			return result
		cursor+=1
		var width: int = 1
		if code<32: _fail("Unescaped JSON control character"); return ""
		if key:
			if code>=128 or code==92: _fail("Escaped or non-ASCII JSON key rejected"); return ""
		elif code==92:
			if cursor>=data.size(): _fail("Truncated JSON escape"); return ""
			code=data[cursor]; cursor+=1
			if code==117:
				code=_hex4()
				if not error.is_empty(): return ""
				if code>=55296 and code<=56319:
					if not _take(92) or not _take(117): _fail("Unpaired high surrogate escape"); return ""
					var low: int = _hex4()
					if low<56320 or low>57343: _fail("Invalid surrogate escape pair"); return ""
					code=65536+((code-55296)<<10)+(low-56320)
				elif code>=56320 and code<=57343: _fail("Unpaired low surrogate escape"); return ""
				if code==0 or code==65279: _fail("NUL or BOM scalar rejected"); return ""
				width=1 if code<128 else (2 if code<2048 else (3 if code<65536 else 4))
			elif code not in [34,47,92,98,102,110,114,116]: _fail("Invalid JSON escape"); return ""
		elif code>=128:
			# The prior UTF8 pass established valid sequence widths.
			width=2 if code<224 else (3 if code<240 else 4)
			cursor+=width-1
		characters+=1
		utf8_bytes+=width
		if key and characters>64: _fail("JSON key bound exceeded"); return ""
		if not key and not large and (characters>1024 or utf8_bytes>4096): _fail("JSON string bound exceeded"); return ""
		if large and utf8_bytes>MAX_BYTES: _fail("Payload decoded byte bound exceeded"); return ""
	_fail("Unterminated JSON string")
	return ""
