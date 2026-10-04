// Entry point of the Windmark GDExtension (game/bin/windmark.gdextension): registers CoreSim, SailShape, the wake classes
// (SeaSampler, WakeRibbon, BowWaveSheets, MistCloud), BoatShadowShape and SheetRopes.
#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "boat_shadow.h"
#include "core_sim.h"
#include "sail_shape.h"
#include "sea_wakes.h"
#include "sheet_ropes.h"

using namespace godot;

namespace {

void initialize(ModuleInitializationLevel level) {
  if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
  GDREGISTER_CLASS(windmark_godot::CoreSim);
  GDREGISTER_CLASS(windmark_godot::SailShape);
  GDREGISTER_CLASS(windmark_godot::SeaSampler);
  GDREGISTER_CLASS(windmark_godot::WakeRibbon);
  GDREGISTER_CLASS(windmark_godot::BowWaveSheets);
  GDREGISTER_CLASS(windmark_godot::MistCloud);
  GDREGISTER_CLASS(windmark_godot::BoatShadowShape);
  GDREGISTER_CLASS(windmark_godot::SheetRopes);
}

void uninitialize(ModuleInitializationLevel level) { (void)level; }

}  // namespace

extern "C" {
GDExtensionBool GDE_EXPORT windmark_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                                                 GDExtensionClassLibraryPtr library,
                                                 GDExtensionInitialization* init) {
  GDExtensionBinding::InitObject obj(get_proc_address, library, init);
  obj.register_initializer(initialize);
  obj.register_terminator(uninitialize);
  obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
  return obj.init();
}
}
