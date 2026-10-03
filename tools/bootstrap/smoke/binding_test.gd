extends SceneTree
func _initialize() -> void:
    var status := GDExtensionManager.load_extension("res://probe.gdextension")
    if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
        push_error("Pinned GDExtension binding probe failed to load: %s" % status)
        quit(1)
        return
    print("TOOLCHAIN_BINDING_LOAD_OK")
    quit(0)
