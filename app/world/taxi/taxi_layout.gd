extends RefCounted
# Original MIT. ADR027 fixed packaged geometry, not native ground or airport IO.
const CONTENT_SHA256: String = "d8668af407885949a4eb05fbe170d41fe6c6752d3ce15670f9879a36063d355c"
const CONTENT_PATH: String = "res://world/synthetic/taxi-layout-v1.json"
# Exact original source definition, not a runtime-derived expected value.
const AUTHORED_TEMPLATE: Dictionary = {
	"schema": "SyntheticTaxiLayout/v1",
	"id": "original-taxi-navigation",
	"revision": 1,
	"license": "MIT",
	"provenance": "Original synthetic geometry and labels; FAA AIM factual sign and marking conventions paraphrased in ADR027; no operational chart.",
	"world": {
		"id": "original.interactive-plane",
		"version": "1.0.0",
		"prepared_sha256": "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5"
	},
	"frame": "fixed-anchor-east-up-south-metres",
	"pavement": [
		{
			"id": "runway",
			"label": "Synthetic runway 36/18",
			"center_xz_m": [
				0,
				-800
			],
			"half_extent_xz_m": [
				20,
				900
			],
			"ends": [
				{
					"designator": 36,
					"point_eus_m": [
						0,
						0,
						100
					]
				},
				{
					"designator": 18,
					"point_eus_m": [
						0,
						0,
						-1700
					]
				}
			]
		},
		{
			"id": "parallel",
			"label": "A - Parallel",
			"center_xz_m": [
				82,
				-800
			],
			"half_extent_xz_m": [
				7.5,
				920
			]
		},
		{
			"id": "apron",
			"label": "Apron",
			"center_xz_m": [
				132,
				25
			],
			"half_extent_xz_m": [
				65,
				95
			]
		}
	],
	"links": [
		{
			"id": "south-link",
			"label": "A1",
			"z_m": 30,
			"center_xz_m": [
				49,
				30
			],
			"half_extent_xz_m": [
				32.5,
				7.5
			],
			"bar_center_x_m": 30,
			"bar_offsets_x_m": [
				-1.3,
				-0.7,
				0.7,
				1.3
			],
			"bar_half_extent_xz_m": [
				0.1,
				7
			],
			"bar_styles": [
				"dashed",
				"dashed",
				"solid",
				"solid"
			],
			"dash_pattern_m": {
				"length": 1,
				"gap": 1,
				"origin_relative_z": -7
			},
			"stop_point_eus_m": [
				40,
				0,
				30
			]
		},
		{
			"id": "middle-link",
			"label": "A2",
			"z_m": -800,
			"center_xz_m": [
				49,
				-800
			],
			"half_extent_xz_m": [
				32.5,
				7.5
			],
			"bar_center_x_m": 30,
			"bar_offsets_x_m": [
				-1.3,
				-0.7,
				0.7,
				1.3
			],
			"bar_half_extent_xz_m": [
				0.1,
				7
			],
			"bar_styles": [
				"dashed",
				"dashed",
				"solid",
				"solid"
			],
			"dash_pattern_m": {
				"length": 1,
				"gap": 1,
				"origin_relative_z": -7
			},
			"stop_point_eus_m": [
				40,
				0,
				-800
			]
		},
		{
			"id": "north-link",
			"label": "A3",
			"z_m": -1630,
			"center_xz_m": [
				49,
				-1630
			],
			"half_extent_xz_m": [
				32.5,
				7.5
			],
			"bar_center_x_m": 30,
			"bar_offsets_x_m": [
				-1.3,
				-0.7,
				0.7,
				1.3
			],
			"bar_half_extent_xz_m": [
				0.1,
				7
			],
			"bar_styles": [
				"dashed",
				"dashed",
				"solid",
				"solid"
			],
			"dash_pattern_m": {
				"length": 1,
				"gap": 1,
				"origin_relative_z": -7
			},
			"stop_point_eus_m": [
				40,
				0,
				-1630
			]
		}
	],
	"parking": [
		{
			"id": "park-1",
			"label": "PARK1",
			"stripe_center_eus_m": [
				108,
				0,
				34
			],
			"stripe_half_length_m": 18,
			"cap_half_width_m": 5,
			"cap_z_m": 16,
			"stand_point_eus_m": [
				108,
				0,
				18
			]
		},
		{
			"id": "park-2",
			"label": "PARK2",
			"stripe_center_eus_m": [
				127,
				0,
				34
			],
			"stripe_half_length_m": 18,
			"cap_half_width_m": 5,
			"cap_z_m": 16,
			"stand_point_eus_m": [
				127,
				0,
				18
			]
		},
		{
			"id": "park-3",
			"label": "PARK3",
			"stripe_center_eus_m": [
				146,
				0,
				34
			],
			"stripe_half_length_m": 18,
			"cap_half_width_m": 5,
			"cap_z_m": 16,
			"stand_point_eus_m": [
				146,
				0,
				18
			]
		},
		{
			"id": "park-4",
			"label": "PARK4",
			"stripe_center_eus_m": [
				165,
				0,
				34
			],
			"stripe_half_length_m": 18,
			"cap_half_width_m": 5,
			"cap_z_m": 16,
			"stand_point_eus_m": [
				165,
				0,
				18
			]
		},
		{
			"id": "park-5",
			"label": "PARK5",
			"stripe_center_eus_m": [
				184,
				0,
				34
			],
			"stripe_half_length_m": 18,
			"cap_half_width_m": 5,
			"cap_z_m": 16,
			"stand_point_eus_m": [
				184,
				0,
				18
			]
		}
	],
	"signs": [
		{
			"id": "junction-south",
			"point_eus_m": [
				95,
				1.2,
				42
			],
			"faces": [
				{
					"normal_xz": [
						0,
						-1
					],
					"panels": [
						{
							"role": "location",
							"label": "A",
							"direction_xz": null
						},
						{
							"role": "direction",
							"label": "A1",
							"direction_xz": [
								-1,
								0
							]
						}
					]
				},
				{
					"normal_xz": [
						0,
						1
					],
					"panels": [
						{
							"role": "direction",
							"label": "A1",
							"direction_xz": [
								-1,
								0
							]
						},
						{
							"role": "location",
							"label": "A",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "south-link"
		},
		{
			"id": "hold-south",
			"point_eus_m": [
				30,
				1.2,
				20
			],
			"faces": [
				{
					"normal_xz": [
						1,
						0
					],
					"panels": [
						{
							"role": "runway-holding",
							"label": "36-18",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "south-link"
		},
		{
			"id": "junction-middle",
			"point_eus_m": [
				95,
				1.2,
				-788
			],
			"faces": [
				{
					"normal_xz": [
						0,
						-1
					],
					"panels": [
						{
							"role": "location",
							"label": "A",
							"direction_xz": null
						},
						{
							"role": "direction",
							"label": "A2",
							"direction_xz": [
								-1,
								0
							]
						}
					]
				},
				{
					"normal_xz": [
						0,
						1
					],
					"panels": [
						{
							"role": "direction",
							"label": "A2",
							"direction_xz": [
								-1,
								0
							]
						},
						{
							"role": "location",
							"label": "A",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "middle-link"
		},
		{
			"id": "hold-middle",
			"point_eus_m": [
				30,
				1.2,
				-810
			],
			"faces": [
				{
					"normal_xz": [
						1,
						0
					],
					"panels": [
						{
							"role": "runway-holding",
							"label": "36-18",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "middle-link"
		},
		{
			"id": "junction-north",
			"point_eus_m": [
				95,
				1.2,
				-1618
			],
			"faces": [
				{
					"normal_xz": [
						0,
						-1
					],
					"panels": [
						{
							"role": "location",
							"label": "A",
							"direction_xz": null
						},
						{
							"role": "direction",
							"label": "A3",
							"direction_xz": [
								-1,
								0
							]
						}
					]
				},
				{
					"normal_xz": [
						0,
						1
					],
					"panels": [
						{
							"role": "direction",
							"label": "A3",
							"direction_xz": [
								-1,
								0
							]
						},
						{
							"role": "location",
							"label": "A",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "north-link"
		},
		{
			"id": "hold-north",
			"point_eus_m": [
				30,
				1.2,
				-1640
			],
			"faces": [
				{
					"normal_xz": [
						1,
						0
					],
					"panels": [
						{
							"role": "runway-holding",
							"label": "36-18",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "north-link"
		},
		{
			"id": "apron-parking",
			"point_eus_m": [
				100,
				1.2,
				64
			],
			"faces": [
				{
					"normal_xz": [
						0,
						1
					],
					"panels": [
						{
							"role": "original-information",
							"label": "PARK1..5",
							"direction_xz": null
						}
					]
				}
			],
			"reference_id": "apron"
		}
	],
	"itineraries": [
		{
			"id": "locate-parking",
			"label": "Locate PARK1",
			"purpose": "to-parking",
			"runway": null,
			"link": "south-link",
			"parking": "park-1",
			"points": [
				{
					"id": "locate-parking-p1",
					"label": "Locate PARK1 reference 1",
					"point_eus_m": [
						0,
						0,
						30
					]
				},
				{
					"id": "locate-parking-p2",
					"label": "Locate PARK1 reference 2",
					"point_eus_m": [
						40,
						0,
						30
					]
				},
				{
					"id": "locate-parking-p3",
					"label": "Locate PARK1 reference 3",
					"point_eus_m": [
						82,
						0,
						30
					]
				},
				{
					"id": "locate-parking-p4",
					"label": "Locate PARK1 reference 4",
					"point_eus_m": [
						108,
						0,
						30
					]
				},
				{
					"id": "locate-parking-p5",
					"label": "Locate PARK1 reference 5",
					"point_eus_m": [
						108,
						0,
						18
					]
				}
			]
		},
		{
			"id": "outbound-36",
			"label": "To south stop - runway 36",
			"purpose": "to-stop-reference",
			"runway": 36,
			"link": "south-link",
			"parking": "park-1",
			"points": [
				{
					"id": "outbound-36-p1",
					"label": "To south stop - runway 36 reference 1",
					"point_eus_m": [
						108,
						0,
						18
					]
				},
				{
					"id": "outbound-36-p2",
					"label": "To south stop - runway 36 reference 2",
					"point_eus_m": [
						108,
						0,
						0
					]
				},
				{
					"id": "outbound-36-p3",
					"label": "To south stop - runway 36 reference 3",
					"point_eus_m": [
						82,
						0,
						0
					]
				},
				{
					"id": "outbound-36-p4",
					"label": "To south stop - runway 36 reference 4",
					"point_eus_m": [
						82,
						0,
						30
					]
				},
				{
					"id": "outbound-36-p5",
					"label": "To south stop - runway 36 reference 5",
					"point_eus_m": [
						40,
						0,
						30
					]
				}
			]
		},
		{
			"id": "outbound-18",
			"label": "To north stop - runway 18",
			"purpose": "to-stop-reference",
			"runway": 18,
			"link": "north-link",
			"parking": "park-1",
			"points": [
				{
					"id": "outbound-18-p1",
					"label": "To north stop - runway 18 reference 1",
					"point_eus_m": [
						108,
						0,
						18
					]
				},
				{
					"id": "outbound-18-p2",
					"label": "To north stop - runway 18 reference 2",
					"point_eus_m": [
						108,
						0,
						0
					]
				},
				{
					"id": "outbound-18-p3",
					"label": "To north stop - runway 18 reference 3",
					"point_eus_m": [
						82,
						0,
						0
					]
				},
				{
					"id": "outbound-18-p4",
					"label": "To north stop - runway 18 reference 4",
					"point_eus_m": [
						82,
						0,
						-1630
					]
				},
				{
					"id": "outbound-18-p5",
					"label": "To north stop - runway 18 reference 5",
					"point_eus_m": [
						40,
						0,
						-1630
					]
				}
			]
		},
		{
			"id": "return-south",
			"label": "Return via south link",
			"purpose": "to-parking",
			"runway": null,
			"link": "south-link",
			"parking": "park-1",
			"points": [
				{
					"id": "return-south-p1",
					"label": "Return via south link reference 1",
					"point_eus_m": [
						40,
						0,
						30
					]
				},
				{
					"id": "return-south-p2",
					"label": "Return via south link reference 2",
					"point_eus_m": [
						82,
						0,
						30
					]
				},
				{
					"id": "return-south-p3",
					"label": "Return via south link reference 3",
					"point_eus_m": [
						82,
						0,
						0
					]
				},
				{
					"id": "return-south-p4",
					"label": "Return via south link reference 4",
					"point_eus_m": [
						108,
						0,
						0
					]
				},
				{
					"id": "return-south-p5",
					"label": "Return via south link reference 5",
					"point_eus_m": [
						108,
						0,
						18
					]
				}
			]
		},
		{
			"id": "return-middle",
			"label": "Return via middle link",
			"purpose": "to-parking",
			"runway": null,
			"link": "middle-link",
			"parking": "park-1",
			"points": [
				{
					"id": "return-middle-p1",
					"label": "Return via middle link reference 1",
					"point_eus_m": [
						40,
						0,
						-800
					]
				},
				{
					"id": "return-middle-p2",
					"label": "Return via middle link reference 2",
					"point_eus_m": [
						82,
						0,
						-800
					]
				},
				{
					"id": "return-middle-p3",
					"label": "Return via middle link reference 3",
					"point_eus_m": [
						82,
						0,
						0
					]
				},
				{
					"id": "return-middle-p4",
					"label": "Return via middle link reference 4",
					"point_eus_m": [
						108,
						0,
						0
					]
				},
				{
					"id": "return-middle-p5",
					"label": "Return via middle link reference 5",
					"point_eus_m": [
						108,
						0,
						18
					]
				}
			]
		},
		{
			"id": "return-north",
			"label": "Return via north link",
			"purpose": "to-parking",
			"runway": null,
			"link": "north-link",
			"parking": "park-1",
			"points": [
				{
					"id": "return-north-p1",
					"label": "Return via north link reference 1",
					"point_eus_m": [
						40,
						0,
						-1630
					]
				},
				{
					"id": "return-north-p2",
					"label": "Return via north link reference 2",
					"point_eus_m": [
						82,
						0,
						-1630
					]
				},
				{
					"id": "return-north-p3",
					"label": "Return via north link reference 3",
					"point_eus_m": [
						82,
						0,
						0
					]
				},
				{
					"id": "return-north-p4",
					"label": "Return via north link reference 4",
					"point_eus_m": [
						108,
						0,
						0
					]
				},
				{
					"id": "return-north-p5",
					"label": "Return via north link reference 5",
					"point_eus_m": [
						108,
						0,
						18
					]
				}
			]
		}
	],
	"starts": [
		{
			"named_start": "apron-ready",
			"profile_id": "original-interactive-prototype",
			"parking_id": "park-1",
			"requested_cg_eus_m": [
				108,
				1.05,
				18
			],
			"roll_pitch_yaw_rad": [
				0,
				0,
				0
			],
			"wind_profile": "calm"
		},
		{
			"named_start": "piston-cold-apron",
			"profile_id": "original-piston-prop-v1",
			"parking_id": "park-1",
			"requested_cg_eus_m": [
				108,
				1.05,
				18
			],
			"roll_pitch_yaw_rad": [
				0,
				0,
				0
			],
			"wind_profile": "calm"
		}
	]
}


static func _result(error: String, value: Variant = null) -> Dictionary:
	return {"ok":error.is_empty(),"error":error,"value":value}

static func _keys(value: Variant, names: Array) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or value.size()!=names.size(): return false
	for key in value:
		if typeof(key)!=TYPE_STRING or not names.has(key): return false
	return true

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _normalize(value: Variant, pattern: Variant, field: String = "") -> Dictionary:
	# Exact fixed roster/relationships are part of this local contract, not a
	# general airport import. Recursion is bounded by the authored template.
	match typeof(pattern):
		TYPE_DICTIONARY:
			if not _keys(value,pattern.keys()): return _result("invalid_shape")
			var copied: Dictionary = {}
			for key in pattern:
				var child: Dictionary = _normalize(value[key],pattern[key],key)
				if not child.ok: return child
				copied[key]=child.value
			return _result("",copied)
		TYPE_ARRAY:
			if typeof(value)!=TYPE_ARRAY or value.size()!=pattern.size(): return _result("invalid_shape")
			var copied: Array = []
			for i in pattern.size():
				var child: Dictionary = _normalize(value[i],pattern[i],field)
				if not child.ok: return child
				copied.append(child.value)
			return _result("",copied)
		TYPE_INT,TYPE_FLOAT:
			if not _number(value): return _result("invalid_shape")
			if absf(float(value))>2000.0 or float(value)!=float(pattern): return _result("invalid_value")
			if field in ["revision","designator","runway"]:
				if float(value)!=floor(float(value)): return _result("invalid_value")
				return _result("",int(value))
			return _result("",float(value))
		TYPE_STRING:
			if typeof(value)!=TYPE_STRING: return _result("invalid_shape")
			if value!=pattern: return _result("invalid_relationship" if field in ["id","reference_id","link","parking","parking_id","named_start","profile_id"] else "invalid_value")
			return _result("",value)
		TYPE_NIL:
			return _result("",null) if typeof(value)==TYPE_NIL else _result("invalid_shape")
	return _result("invalid_shape")

static func _clip(a: Array, b: Array, rectangle: Dictionary) -> Array:
	var low: float = 0.0
	var high: float = 1.0
	for axis in 2:
		var component: int = 0 if axis==0 else 2
		var start: float = float(a[component])
		var delta: float = float(b[component])-start
		var minimum: float = float(rectangle.center_xz_m[axis])-float(rectangle.half_extent_xz_m[axis])
		var maximum: float = float(rectangle.center_xz_m[axis])+float(rectangle.half_extent_xz_m[axis])
		if delta==0.0:
			if start<minimum or start>maximum: return []
		else:
			var enter: float = (minimum-start)/delta
			var leave: float = (maximum-start)/delta
			low=maxf(low,minf(enter,leave))
			high=minf(high,maxf(enter,leave))
			if low>high: return []
	return [low,high]

static func _segment_on_pavement(a: Array, b: Array, rectangles: Array) -> bool:
	var intervals: Array = []
	for rectangle in rectangles:
		var interval: Array = _clip(a,b,rectangle)
		if not interval.is_empty(): intervals.append(interval)
	intervals.sort_custom(func(left: Array,right: Array)->bool: return left[0]<right[0])
	var covered: float = 0.0
	for interval in intervals:
		if float(interval[0])>covered: return false
		covered=maxf(covered,float(interval[1]))
		if covered>=1.0: return true
	return false

static func validate(value: Variant) -> Dictionary:
	# Pure even on a foreign thread. No cache, IO or caller mutation.
	if not _keys(value,AUTHORED_TEMPLATE.keys()): return _result("invalid_shape")
	if not _keys(value.world,["id","version","prepared_sha256"]): return _result("invalid_shape")
	for key in value.world:
		if typeof(value.world[key])!=TYPE_STRING: return _result("invalid_shape")
	if value.world!=AUTHORED_TEMPLATE.world or typeof(value.frame)!=TYPE_STRING or value.frame!=AUTHORED_TEMPLATE.frame:
		return _result("unsupported_world")
	var result: Dictionary = _normalize(value,AUTHORED_TEMPLATE)
	if not result.ok: return result
	var normalized: Dictionary = result.value
	var rectangles: Array = normalized.pavement.duplicate(true)
	for link in normalized.links: rectangles.append(link.duplicate(true))
	for itinerary in normalized.itineraries:
		for index in range(1,itinerary.points.size()):
			if not _segment_on_pavement(itinerary.points[index-1].point_eus_m,itinerary.points[index].point_eus_m,rectangles):
				return _result("invalid_relationship")
	return result

static func load() -> Dictionary:
	if not Thread.is_main_thread(): return _result("wrong_thread")
	if not FileAccess.file_exists(CONTENT_PATH): return _result("source_unavailable")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(CONTENT_PATH)
	if raw.is_empty(): return _result("source_unavailable")
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256)!=OK or hash_context.update(raw)!=OK:
		return _result("source_unavailable")
	if hash_context.finish().hex_encode()!=CONTENT_SHA256: return _result("source_mismatch")
	# The immutable checksum is provenance for one reviewed duplicate-key-free
	# source. This is not an untrusted JSON/duplicate-key parser promise.
	return validate(JSON.parse_string(raw.get_string_from_utf8()))
