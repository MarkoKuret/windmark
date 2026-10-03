class_name LongLensCamera
extends ChaseCamera
## cameras.md §9 long lens: a chase camera far astern and low with a narrow field of view; the zoom changes the
## field of view (6° to 25°), recentre restores these defaults.

const R_LONG := 150.0
const EL_LONG := deg_to_rad(5.0)
const FOV_LONG := 12.0
const TAU_YAW_LONG := 1.5


func _init() -> void:
	fov_min = 6.0
	fov_max = 25.0
	zoom_is_fov = true
	_defaults()


func _defaults() -> void:
	R = R_LONG
	el = EL_LONG
	az = 0.0
	fov = FOV_LONG
	tau_yaw = TAU_YAW_LONG
	tau_heave = 0.3
	lift = 1.0


func recentre(_t: CamTypes.Target) -> void:
	_defaults()
