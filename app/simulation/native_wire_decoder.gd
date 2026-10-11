extends RefCounted
# Original MIT. ADR023 lexical transduction; Godot owns container grammar.
# No numeric source token is passed to JSON.parse or String.to_float.
const INPUT_LIMIT: int=1048576
const ENTRY_LIMIT: int=32768
const MEMBER_LIMIT: int=8192
const DEPTH_LIMIT: int=24
const TRANSFORM_LIMIT: int=4194304

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message.left(256),"value":null}

class Lexical extends RefCounted:
	static func _scalar(code: int) -> bool:
		return code>=0 and code<=0x10ffff and not (code>=0xd800 and code<=0xdfff)

	static func _space(code: int) -> bool:
		return code in [0x20,0x09,0x0a,0x0d]

	static func _digit(code: int) -> bool:
		return code>=48 and code<=57

	static func _delimiter(code: int) -> bool:
		return _space(code) or code in [123,125,91,93,58,44]

	static func _number(text: String) -> bool:
		var index: int=0
		var size: int=text.length()
		if size==0 or size>2048: return false
		if text.unicode_at(index)==45:
			index+=1
			if index==size: return false
		if text.unicode_at(index)==48:
			index+=1
		elif text.unicode_at(index)>=49 and text.unicode_at(index)<=57:
			while index<size and _digit(text.unicode_at(index)): index+=1
		else: return false
		if index<size and text.unicode_at(index)==46:
			index+=1
			var start: int=index
			while index<size and _digit(text.unicode_at(index)): index+=1
			if index==start: return false
		if index<size and text.unicode_at(index) in [69,101]:
			index+=1
			if index<size and text.unicode_at(index) in [43,45]: index+=1
			var start: int=index
			while index<size and _digit(text.unicode_at(index)): index+=1
			if index==start: return false
		return index==size

	static func _decimal_zero(text: String) -> bool:
		for index in text.length():
			var code: int=text.unicode_at(index)
			if code in [69,101]: break
			if code>=49 and code<=57: return false
		return true

	static func _negative(value: float) -> bool:
		var bytes: PackedByteArray=PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0,value)
		return (bytes[7]&128)!=0

class Transduction extends RefCounted:
	var text: String
	var at: int=0
	var pieces: PackedStringArray=PackedStringArray()
	var transformed_bytes: int=0
	var entries: int=0
	var numbers: Array[String]=[]
	var number_bytes: int=0
	var slots: Array[Dictionary]=[]
	var stack: Array[Dictionary]=[]
	var error: String=""
	var last: int=0
	var root_started: bool=false
	var root_closed: bool=false

	func _bad(message: String) -> bool:
		error=message
		return false

	func _emit(value: String) -> bool:
		transformed_bytes+=value.length() # Emitted stream is ASCII only.
		if transformed_bytes>TRANSFORM_LIMIT: return _bad("Transformed input exceeds bound")
		pieces.append(value)
		return true

	func _entry() -> bool:
		entries+=1
		if entries>ENTRY_LIMIT: return _bad("Lexical entries exceed bound")
		if not stack.is_empty(): stack[-1].has_value=true
		return true

	func _slot(kind: String,value: Variant) -> bool:
		if slots.size()>=ENTRY_LIMIT: return _bad("Side table exceeds bound")
		var ordinal: int=slots.size()
		slots.append({"kind":kind,"value":value})
		return _emit('"NWD'+str(ordinal)+'"')

	func _hex4(start: int) -> int:
		if start+4>text.length(): return -1
		var result: int=0
		for index in range(start,start+4):
			var code: int=text.unicode_at(index)
			var digit: int=code-48 if code>=48 and code<=57 else code-65+10 if code>=65 and code<=70 else code-97+10 if code>=97 and code<=102 else -1
			if digit<0: return -1
			result=result*16+digit
		return result

	func _string() -> bool:
		var start: int=at
		at+=1
		while at<text.length():
			var code: int=text.unicode_at(at)
			if code==34:
				at+=1
				if at<text.length() and not Lexical._delimiter(text.unicode_at(at)): return _bad("Invalid string token boundary")
				var parser: JSON=JSON.new()
				if parser.parse(text.substr(start,at-start))!=OK or typeof(parser.data)!=TYPE_STRING: return _bad("Invalid isolated JSON string")
				var decoded: String=parser.data
				for index in decoded.length():
					if not Lexical._scalar(decoded.unicode_at(index)): return _bad("Invalid decoded Unicode scalar")
				return _slot("string",decoded)
			if code<32 or not Lexical._scalar(code): return _bad("Invalid raw string scalar")
			if code==92:
				at+=1
				if at>=text.length(): return _bad("Incomplete escape")
				var escaped: int=text.unicode_at(at)
				if escaped==117:
					var first: int=_hex4(at+1)
					if first<0: return _bad("Invalid Unicode escape")
					at+=5
					if first>=0xd800 and first<=0xdbff:
						if at+6>text.length() or text.unicode_at(at)!=92 or text.unicode_at(at+1)!=117: return _bad("Unpaired high surrogate")
						var second: int=_hex4(at+2)
						if second<0xdc00 or second>0xdfff: return _bad("Invalid surrogate pair")
						at+=6
					elif first>=0xdc00 and first<=0xdfff: return _bad("Unpaired low surrogate")
					continue
				if escaped not in [34,92,47,98,102,110,114,116]: return _bad("Invalid JSON escape")
			at+=1
		return _bad("Unterminated string")

	func scan(source: String) -> bool:
		text=source
		while at<text.length():
			var code: int=text.unicode_at(at)
			if Lexical._space(code):
				if not _emit(text[at]): return false
				at+=1
				continue
			if root_closed: return _bad("Trailing content after root Dictionary")
			if not root_started:
				if code!=123: return _bad("Expected root Dictionary")
				root_started=true
			if code in [123,91]:
				if not _entry(): return false
				stack.append({"kind":code,"commas":0,"has_value":false})
				if stack.size()>DEPTH_LIMIT: return _bad("Container depth exceeds bound")
				if not _emit(text[at]): return false
				at+=1
			elif code in [125,93]:
				if stack.is_empty() or stack[-1].kind!=(123 if code==125 else 91): return _bad("Unmatched container")
				if last==44: return _bad("Trailing comma")
				var frame: Dictionary=stack.pop_back()
				if stack.is_empty(): root_closed=true
				if frame.has_value and frame.commas+1>MEMBER_LIMIT: return _bad("Container members exceed bound")
				if not _emit(text[at]): return false
				at+=1
			elif code in [44,58]:
				if stack.is_empty(): return _bad("Punctuation outside container")
				if code==44:
					stack[-1].commas+=1
					if stack[-1].commas>=MEMBER_LIMIT: return _bad("Container members exceed bound")
				if not _emit(text[at]): return false
				at+=1
			elif code==34:
				if not _entry() or not _string(): return false
			elif code==45 or Lexical._digit(code):
				if not _entry(): return false
				var start: int=at
				while at<text.length() and text.unicode_at(at) in [45,43,46,69,101,48,49,50,51,52,53,54,55,56,57]: at+=1
				var token: String=text.substr(start,at-start)
				if not Lexical._number(token) or (at<text.length() and not Lexical._delimiter(text.unicode_at(at))): return _bad("Invalid number token")
				if numbers.size()>=MEMBER_LIMIT or number_bytes+token.length()>INPUT_LIMIT: return _bad("Numeric batch exceeds bound")
				number_bytes+=token.length()
				numbers.append(token)
				if not _slot("number",numbers.size()-1): return false
			elif code in [116,102,110]:
				if not _entry(): return false
				var literal: String="true" if code==116 else "false" if code==102 else "null"
				if text.substr(at,literal.length())!=literal: return _bad("Invalid literal")
				at+=literal.length()
				if at<text.length() and not Lexical._delimiter(text.unicode_at(at)): return _bad("Invalid literal boundary")
				if not _emit(literal): return false
			else: return _bad("Unexpected JSON token")
			last=code
		if not stack.is_empty() or not root_closed: return _bad("Incomplete root Dictionary")
		return true

class Restoration extends RefCounted:
	var slots: Array[Dictionary]
	var numbers: Array
	var used: Dictionary={}
	var nodes: int=0
	var error: String=""

	func _count() -> bool:
		nodes+=1
		if nodes>ENTRY_LIMIT:
			error="Restored nodes exceed bound"
			return false
		return true

	func _placeholder(value: String,key: bool) -> Variant:
		# Do not use permissive String.to_int. A bounded exact lookup accepts
		# only placeholders emitted from this call's private ordinal side table.
		if not value.begins_with("NWD"):
			error="Unknown placeholder";return null
		var digits: String=value.substr(3)
		if digits.is_empty() or digits.length()>5 or (digits.length()>1 and digits[0]=="0"):
			error="Invalid placeholder ordinal";return null
		var index: int=0
		for offset in digits.length():
			var code: int=digits.unicode_at(offset)
			if not Lexical._digit(code):
				error="Invalid placeholder ordinal";return null
			index=index*10+code-48
		if index>=slots.size() or used.has(index):
			error="Missing or repeated placeholder";return null
		used[index]=true
		var slot: Dictionary=slots[index]
		if key and slot.kind!="string":
			error="Original object key was not a String";return null
		return slot.value if slot.kind=="string" else numbers[slot.value]

	func restore(value: Variant,depth: int=0) -> Variant:
		if not _count(): return null
		if value is Dictionary:
			if depth>=DEPTH_LIMIT or value.size()>MEMBER_LIMIT:
				error="Restored object exceeds bound";return null
			var result: Dictionary={}
			for placeholder in value:
				if typeof(placeholder)!=TYPE_STRING or not _count():
					error="Invalid restored key";return null
				var key: Variant=_placeholder(placeholder,true)
				if not error.is_empty(): return null
				if result.has(key):
					error="Duplicate decoded object key";return null
				var restored: Variant=restore(value[placeholder],depth+1)
				if not error.is_empty(): return null
				result[key]=restored
			return result
		if value is Array:
			if depth>=DEPTH_LIMIT or value.size()>MEMBER_LIMIT:
				error="Restored array exceeds bound";return null
			var result: Array=[]
			for item in value:
				result.append(restore(item,depth+1))
				if not error.is_empty(): return null
			return result
		if typeof(value)==TYPE_STRING: return _placeholder(value,false)
		if value==null or typeof(value)==TYPE_BOOL: return value
		error="Unexpected transformed scalar"
		return null

static func decode(encoded: Variant,converter: Callable=Callable()) -> Dictionary:
	if typeof(encoded)!=TYPE_STRING: return _failure("Expected exact String publication")
	if encoded.length()>INPUT_LIMIT: return _failure("Input characters exceed bound")
	for index in encoded.length():
		if not Lexical._scalar(encoded.unicode_at(index)): return _failure("Invalid input Unicode scalar")
	if encoded.to_utf8_buffer().size()>INPUT_LIMIT: return _failure("Input UTF8 bytes exceed bound")
	var scanner: Transduction=Transduction.new()
	if not scanner.scan(encoded): return _failure(scanner.error)
	var parser: JSON=JSON.new()
	if parser.parse("".join(scanner.pieces))!=OK or not parser.data is Dictionary: return _failure("Invalid transformed Dictionary publication")
	var utility: RefCounted
	var call: Callable=converter
	if call.is_null():
		if not ClassDB.class_exists("FlightWireNumbers"): return _failure("Native numeric utility unavailable")
		utility=ClassDB.instantiate("FlightWireNumbers") as RefCounted
		if utility==null or not utility.has_method("decode_binary64"): return _failure("Native numeric method unavailable")
		call=Callable(utility,"decode_binary64")
	if not call.is_valid(): return _failure("Invalid numeric converter")
	# Exactly one owned batch. Side tables remain private even for fault tests.
	var converted: Variant=call.call(scanner.numbers.duplicate())
	if typeof(converted)!=TYPE_DICTIONARY or converted.size()!=3: return _failure("Malformed numeric result")
	for key in converted:
		if typeof(key)!=TYPE_STRING or key not in ["ok","error","value"]: return _failure("Malformed numeric result keys")
	if typeof(converted.ok)!=TYPE_BOOL or typeof(converted.error)!=TYPE_STRING or converted.error.length()>256: return _failure("Malformed numeric result fields")
	if not converted.ok:
		if converted.error.is_empty() or converted.value!=null: return _failure("Contradictory numeric failure")
		return _failure(converted.error)
	if not converted.error.is_empty() or typeof(converted.value)!=TYPE_ARRAY or converted.value.size()!=scanner.numbers.size(): return _failure("Contradictory numeric success")
	var values: Array=converted.value.duplicate()
	for index in values.size():
		if typeof(values[index])!=TYPE_FLOAT or not is_finite(values[index]): return _failure("Numeric result must contain finite FLOATs")
		var token: String=scanner.numbers[index]
		var zero: bool=Lexical._decimal_zero(token)
		if zero!=(values[index]==0.0) or Lexical._negative(values[index])!=token.begins_with("-"): return _failure("Numeric zero/sign contradiction")
	var restore: Restoration=Restoration.new()
	restore.slots=scanner.slots
	restore.numbers=values
	var value: Variant=restore.restore(parser.data)
	if not restore.error.is_empty(): return _failure(restore.error)
	if restore.used.size()!=scanner.slots.size() or not value is Dictionary: return _failure("Unused or missing side entries")
	return {"ok":true,"error":"","value":value}
