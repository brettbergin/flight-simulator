#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
namespace {
void initialize(godot::ModuleInitializationLevel level) {
    if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        godot::RefCounted* object = memnew(godot::RefCounted);
        memdelete(object);
        godot::UtilityFunctions::print("TOOLCHAIN_NATIVE_INITIALIZER_OK");
    }
}
void terminate(godot::ModuleInitializationLevel) {}
}
extern "C" {
GDExtensionBool GDE_EXPORT toolchain_probe_init(GDExtensionInterfaceGetProcAddress proc,
                                               GDExtensionClassLibraryPtr library,
                                               GDExtensionInitialization* initialization) {
    godot::GDExtensionBinding::InitObject init(proc, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}

