/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
      pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g_mem` global
      variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

View :: enum {
	MOVE,
	EDIT,
}

Game_Memory :: struct {
	font: rl.Font,
	camera: rl.Camera3D,
	cursor: rl.Vector2,
	hover_index: int,
	vertices: [dynamic][3]f32,
	view: View,
}

g_mem: ^Game_Memory

update :: proc() {
	if rl.IsCursorHidden() {
		if g_mem.view == .MOVE {
			rl.UpdateCameraPro(
				&g_mem.camera,
				{},
				{ rl.GetMouseDelta().x * 0.05, rl.GetMouseDelta().y * 0.05, 0.0 },
				rl.GetMouseWheelMove() * 2.0,
			)

			movement: rl.Vector3
			if rl.IsKeyDown(.W) {
				movement.x += 1.0
			}
			if rl.IsKeyDown(.A) {
				movement.y -= 1.0
			}
			if rl.IsKeyDown(.S) {
				movement.x -= 1.0
			}
			if rl.IsKeyDown(.D) {
				movement.y += 1.0
			}
			if rl.IsKeyDown(.SPACE) {
				movement.z += 1.0
			}
			if rl.IsKeyDown(.LEFT_SHIFT) {
				movement.z -= 1.0
			}
			movement = 0.1 * linalg.normalize0(movement)
		
			rl.UpdateCameraPro(&g_mem.camera, movement, {}, 0.0)
		} else {
			g_mem.cursor += rl.GetMouseDelta()
			ray := rl.GetScreenToWorldRay(
				{f32(rl.GetScreenWidth()) / 2.0 + g_mem.cursor.x, f32(rl.GetScreenHeight()) / 2.0 + g_mem.cursor.y},
				g_mem.camera,
			)

			g_mem.hover_index = -1
			min_ray_distance := f32(1e500)
			for point, i in g_mem.vertices {
				ray_distance := linalg.vector_dot(point - ray.position, linalg.normalize(ray.direction))
				point_distance := linalg.length(point - ray.position - ray_distance * linalg.normalize(ray.direction))

				if ray_distance > 0 && point_distance < 0.05 {
					if ray_distance < min_ray_distance {
						min_ray_distance = ray_distance
						g_mem.hover_index = i
					}
				}
			}

			if rl.IsMouseButtonPressed(.LEFT) && g_mem.hover_index == -1 {
				new_point := ray.position + ray.direction * (-ray.position.y / ray.direction.y)
				append(&g_mem.vertices, new_point)
			}
		}

		if rl.IsKeyPressed(.M) {
			g_mem.cursor = {}
			g_mem.hover_index = -1
			if g_mem.view == .MOVE {
				g_mem.view = .EDIT
			} else {
				g_mem.view = .MOVE
			}
		}
		if rl.IsKeyPressed(.ESCAPE) {
			rl.EnableCursor()
		}
	} else {
		if rl.IsMouseButtonPressed(.LEFT) {
			rl.DisableCursor()
		}
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	rl.BeginMode3D(g_mem.camera)
	rl.DrawTriangle3D({0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, rl.GRAY)
	rl.DrawTriangle3D({0.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {1.0, 0.0, 0.0}, rl.GRAY) // TODO: Disable face culling
	for point, i in g_mem.vertices {
		color := rl.BLACK
		if g_mem.hover_index == i {
			color = rl.RED
		}
		rl.DrawSphere(point, 0.05, color)
	}
	rl.DrawGrid(50, 1.0)
	rl.EndMode3D()
	rl.DrawCircle(i32(f32(rl.GetScreenWidth()) / 2.0 + g_mem.cursor.x), i32(f32(rl.GetScreenHeight()) / 2.0 + g_mem.cursor.y), 5.0, rl.ORANGE)

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("FPS: %v", rl.GetFPS()), { 10.0, 10.0 }, 32, 0.0, rl.BLACK)
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("Vertices: %v", len(g_mem.vertices)), { 10.0, 50.0 }, 32, 0.0, rl.BLACK)

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
	rl.SetExitKey(.ZERO) // TODO: Change this?
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		font = rl.LoadFontEx("assets/Inter/Inter-VariableFont_opsz,wght.ttf", 32, nil, 0),
		camera = rl.Camera3D {
			position = { 0.0, 2.0, 4.0 },
			target = { 0.0, 2.0, 0.0 },
			up = { 0.0, 1.0, 0.0 },
			fovy = 60.0,
		},
		hover_index = -1,
	}

	game_hot_reloaded(g_mem)
}

@(export)
game_should_close :: proc() -> bool {
	return rl.WindowShouldClose()
}

@(export)
game_shutdown :: proc() {
	delete(g_mem.vertices)
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g_mem`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
