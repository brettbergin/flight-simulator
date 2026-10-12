// Original MIT. No storage/root/worker is opened by extension registration.
#include "local_players.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <chrono>
#include <thread>

namespace flight::local_players::bridge {
namespace {
void initialize(godot::ModuleInitializationLevel level) {
    if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
    godot::ClassDB::register_class<LocalPlayers>();
}

void terminate(godot::ModuleInitializationLevel level) {
    if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
    // Godot's void deinitializer has no veto result. Returning while close_all
    // is false would unload code still owned by a live/unjoined native worker.
    // Request/drain and retry the real registry join; elapsed time is never
    // interpreted as closure. Owner-preflight failures leave services untouched.
    // A foreign owner must close its own service; teardown waits rather than
    // calling its owner-only API or freeing its arena from this thread.
    while (!LocalPlayers::close_all()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}
} // namespace
} // namespace flight::local_players::bridge

extern "C" GDExtensionBool GDE_EXPORT flight_local_players_init(
    GDExtensionInterfaceGetProcAddress api, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization* initialization) {
    godot::GDExtensionBinding::InitObject object(api, library, initialization);
    object.register_initializer(flight::local_players::bridge::initialize);
    object.register_terminator(flight::local_players::bridge::terminate);
    object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
