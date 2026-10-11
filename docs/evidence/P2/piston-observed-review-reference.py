# Original MIT synthetic wire-reference preparation. No Godot/native/codec calls.
import pathlib,json,hashlib,copy,sys

def node_count(value):
    return 1+sum(node_count(v) for v in (value.values() if isinstance(value,dict) else value if isinstance(value,list) else []))

def generate(input_file,output_directory):
    raw=pathlib.Path(input_file).read_bytes()
    if hashlib.sha256(raw).hexdigest()!="33d5e338aa0dd7b57157dcb0bce613e3d1a1126170c5045a0dfb8b2b93ea8afc":
        raise ValueError("Unexpected legacy synthetic reference bytes")
    archive=json.loads(raw.decode("utf-8")); payload=json.loads(archive["payload_json"])
    if hashlib.sha256(archive["payload_json"].encode("utf-8")).hexdigest()!=archive["payload_sha256"]:
        raise ValueError("Legacy payload digest mismatch")
    assert archive["archive_version"]==archive["recording_contract_version"]==payload["contract_version"]==1
    assert len(payload["samples"])==2401
    old_count=node_count(payload)
    payload["contract_version"]=2
    payload["metadata"]["model_identity"]={"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
    payload["metadata"]["named_start"]="piston-cold-ground"
    units={"fuel.total":"kg","engine.throttle":"fraction","engine.mixture":"fraction","propeller.angular_speed":"radps","engine.running":"bool","engine.ignition_left":"bool","engine.ignition_right":"bool","engine.starter":"bool","fuel.feed":"bool","engine.starved":"bool"}
    for sample in payload["samples"]:
        channels={key:{"value":False if unit=="bool" else {"$binary64_le":"0000000000000000"},"unit":unit,"valid":True,"error":""} for key,unit in units.items()}
        assert sample["readings"]["readings"]["fuel_total"]["valid"]
        channels["fuel.total"]["value"]=copy.deepcopy(sample["readings"]["readings"]["fuel_total"]["value"])
        for key in ["throttle","mixture"]:
            value=sample["held_axes"][key]
            assert isinstance(value,dict) and list(value)==["$binary64_le"]
            channels["engine."+key]["value"]=copy.deepcopy(value)
        sample["engine_status"]={"session_id":payload["metadata"]["session_id"],"tick":sample["tick"],"state":sample["readings"]["state"],"native_truth":True,"readings":channels,"error":""}
    text=json.dumps(payload,ensure_ascii=False,separators=(",",":"),sort_keys=True)
    digest=hashlib.sha256(text.encode("utf-8")).hexdigest()
    envelope={"format":"ObservedFlightReview","archive_version":2,"recording_contract_version":2,"payload_json":text,"payload_sha256":digest}
    encoded=json.dumps(envelope,ensure_ascii=False,separators=(",",":"),sort_keys=True).encode("utf-8")
    values=node_count(payload)
    assert old_count==225725 and values==372186
    assert len(text.encode("utf-8"))<=8388608 and len(encoded)<=8388608
    assert values>250000 and values<=400000
    destination=pathlib.Path(output_directory)/"dense-v2.reference.fsreview.json"
    assert not destination.exists()
    destination.write_bytes(encoded)
    return {"schema":"SyntheticPistonWireReference/v1","synthetic":True,"is_native_trace":False,"is_production_codec_output":False,"generator":"piston-observed-review-reference.py","base_reference":{"path":"tests/debrief/observed_archive/reference/dense-2401.fsreview.json","bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()},"output":{"file":destination.name,"bytes":len(encoded),"sha256":hashlib.sha256(encoded).hexdigest()},"payload_sha256":digest,"payload_bytes":len(text.encode("utf-8")),"payload_values":values,"sample_values":node_count(payload["samples"][0]),"engine_status_values":node_count(payload["samples"][0]["engine_status"]),"samples":len(payload["samples"]),"v1_reference_values":old_count,"fits_proposed_v2_400000_values":True,"fits_existing_v1_250000_values":False,"both_byte_caps":8388608,"both_byte_caps_pass":True,"qualification":"Actual independently serialized synthetic wire fixture bytes and counts, not native data or new production codec proof. Contract requires independent review; consumer must later prove actual encoder/decoder and strict policy boundaries."}

if __name__=="__main__":
    print(json.dumps(generate(sys.argv[1],sys.argv[2]),indent=2))
