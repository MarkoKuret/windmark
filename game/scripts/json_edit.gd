class_name JsonEdit
extends RefCounted
## Minimal-diff edits of a JSON text, for the tools that write a hand-formatted file (the kite tuner writes a class
## file's `visual.sails.<id>` blocks, sail_visuals.md §4.1): a value at a path of object keys is replaced, inserted or
## removed in place, and everything else in the text (layout, number spelling, key order) stays as it was. A new
## member goes after the object's last one, on its own line when the object spans lines (with the indentation of its
## members), else inline; a new object on the way is written compactly on one line.

## A parsed value: {"t": "obj" | "arr" | "str" | "num" | "lit", "s": first index, "e": index past the end,
## "m": [{"k": key, "ks": index of the key's opening quote, "v": value node}] for an object}; {} on a syntax error.
static func parse(text: String) -> Dictionary:
	var r := _value(text, _ws(text, 0))
	if r.is_empty() or _ws(text, r["e"]) != text.length():
		return {}
	return r


## `text` with the value at `path` (object keys from the root) set to `value_json` (JSON text), the objects on the
## way created as needed; "" when the text does not parse or a key on the way names something other than an object.
static func put(text: String, path: PackedStringArray, value_json: String) -> String:
	var node := parse(text)
	if node.is_empty() or node["t"] != "obj":
		return ""
	for d in path.size():
		var key := path[d]
		var mi := _member(node, key)
		if mi < 0:
			var v := value_json
			for k in range(path.size() - 1, d, -1):
				v = "{%s: %s}" % [JSON.stringify(path[k]), v]
			return _insert(text, node, key, v)
		var child: Dictionary = node["m"][mi]["v"]
		if d == path.size() - 1:
			return text.substr(0, child["s"]) + value_json + text.substr(child["e"])
		if child["t"] != "obj":
			return ""
		node = child
	return ""


## `text` without the value at `path`, and without the objects on the way that it leaves empty, down to `keep`
## levels from the root (those stay even when empty); `text` itself when there is nothing at `path`; "" when it
## does not parse.
static func drop(text: String, path: PackedStringArray, keep := 1) -> String:
	var root := parse(text)
	if root.is_empty() or root["t"] != "obj":
		return ""
	var chain: Array[Dictionary] = [root]
	for d in path.size() - 1:
		var mi := _member(chain[-1], path[d])
		if mi < 0 or chain[-1]["m"][mi]["v"]["t"] != "obj":
			return text
		chain.append(chain[-1]["m"][mi]["v"])
	if _member(chain[-1], path[path.size() - 1]) < 0:
		return text
	# the deepest object on the way that would be left empty (above `keep`) goes with the value
	var d := path.size() - 1
	while d > keep and (chain[d]["m"] as Array).size() == 1:
		d -= 1
	return _remove(text, chain[d], _member(chain[d], path[d]))


## The value at `path`, as parsed by JSON (null when there is none).
static func value_at(text: String, path: PackedStringArray) -> Variant:
	var v: Variant = JSON.parse_string(text)
	for key in path:
		if not v is Dictionary or not (v as Dictionary).has(key):
			return null
		v = v[key]
	return v


## A number as the class files write it: at most `decimals` decimals, no trailing zeros, at least one decimal.
static func num(v: float, decimals := 4) -> String:
	var s := String.num(snappedf(v, pow(10.0, -decimals)), decimals)
	if not "." in s:
		s += ".0"
	return s


# ---- scanner ------------------------------------------------------------------------------------------------

static func _ws(text: String, i: int) -> int:
	while i < text.length() and text[i] in " \t\r\n":
		i += 1
	return i


static func _value(text: String, i: int) -> Dictionary:
	if i >= text.length():
		return {}
	var c := text[i]
	if c == "{":
		var node := {"t": "obj", "s": i, "m": []}
		var j := _ws(text, i + 1)
		if j < text.length() and text[j] == "}":
			node["e"] = j + 1
			return node
		while true:
			if j >= text.length() or text[j] != "\"":
				return {}
			var ke := _string_end(text, j)
			if ke < 0:
				return {}
			var key: Variant = JSON.parse_string(text.substr(j, ke - j))
			var k2 := _ws(text, ke)
			if k2 >= text.length() or text[k2] != ":":
				return {}
			var v := _value(text, _ws(text, k2 + 1))
			if v.is_empty():
				return {}
			(node["m"] as Array).append({"k": String(key), "ks": j, "v": v})
			j = _ws(text, v["e"])
			if j < text.length() and text[j] == ",":
				j = _ws(text, j + 1)
				continue
			if j < text.length() and text[j] == "}":
				node["e"] = j + 1
				return node
			return {}
	if c == "[":
		var node := {"t": "arr", "s": i}
		var j := _ws(text, i + 1)
		if j < text.length() and text[j] == "]":
			node["e"] = j + 1
			return node
		while true:
			var v := _value(text, j)
			if v.is_empty():
				return {}
			j = _ws(text, v["e"])
			if j < text.length() and text[j] == ",":
				j = _ws(text, j + 1)
				continue
			if j < text.length() and text[j] == "]":
				node["e"] = j + 1
				return node
			return {}
	if c == "\"":
		var e := _string_end(text, i)
		return {} if e < 0 else {"t": "str", "s": i, "e": e}
	var j := i
	while j < text.length() and not text[j] in ",}] \t\r\n":
		j += 1
	if j == i:
		return {}
	return {"t": "num" if text[i] in "-0123456789" else "lit", "s": i, "e": j}


## The index past the closing quote of the string opening at i, -1 when it does not close.
static func _string_end(text: String, i: int) -> int:
	var j := i + 1
	while j < text.length():
		var c := text[j]
		if c == "\\":
			j += 2
			continue
		if c == "\"":
			return j + 1
		j += 1
	return -1


static func _member(obj: Dictionary, key: String) -> int:
	var m: Array = obj["m"]
	for i in m.size():
		if m[i]["k"] == key:
			return i
	return -1


static func _insert(text: String, obj: Dictionary, key: String, value_json: String) -> String:
	var item := "%s: %s" % [JSON.stringify(key), value_json]
	var m: Array = obj["m"]
	if m.is_empty():
		return text.substr(0, obj["s"] + 1) + item + text.substr(obj["e"] - 1)
	var first: int = m[0]["ks"]
	var lead := text.substr(obj["s"] + 1, first - obj["s"] - 1)
	var at: int = m[-1]["v"]["e"]
	if "\n" in lead:
		var ls := text.rfind("\n", first) + 1
		return text.substr(0, at) + ",\n" + text.substr(ls, first - ls) + item + text.substr(at)
	return text.substr(0, at) + ", " + item + text.substr(at)


static func _remove(text: String, obj: Dictionary, idx: int) -> String:
	var m: Array = obj["m"]
	if m.size() == 1:
		return text.substr(0, obj["s"] + 1) + text.substr(obj["e"] - 1)
	if idx < m.size() - 1:
		return text.substr(0, m[idx]["ks"]) + text.substr(m[idx + 1]["ks"])
	var from: int = m[idx - 1]["v"]["e"]
	return text.substr(0, from) + text.substr(m[idx]["v"]["e"])
