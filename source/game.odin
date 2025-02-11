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
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

View :: enum {
	MOVE,
	EDIT_VERTEX,
	EDIT_EDGE,
	EDIT_FACE,
}

HoverType :: enum {
	VERTEX,
	EDGE,
}

Game_Memory :: struct {
	font: rl.Font,
	camera: rl.Camera3D,
	cursor: rl.Vector2,
	cursor_world_point: rl.Vector3,
	hover_index: int,
	hover_type: HoverType,
	vertices: [dynamic][3]f32,
	edges: [dynamic][2]int,
	faces: [dynamic][3]int,
	drag_vertex: int,
	drag_plane_distance: f32,
	new_edge_start: int,
	new_face_start: int,
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

			// Hover check
			g_mem.hover_index = -1
			min_ray_distance := f32(1e500)

			// Vertex hover
			for point, i in g_mem.vertices {
				ray_distance := linalg.vector_dot(point - ray.position, linalg.normalize(ray.direction))
				point_distance := linalg.length(point - ray.position - ray_distance * linalg.normalize(ray.direction))

				if point_distance < 0.05 {
					length := math.sqrt(0.05 * 0.05 - point_distance * point_distance)
					if ray_distance + length > 0 {
						ray_distance = max(0.0, ray_distance - length)
						if ray_distance < min_ray_distance {
							min_ray_distance = ray_distance
							g_mem.hover_index = i
							g_mem.hover_type = .VERTEX
						}
					}
				}
			}

			// Edge hover
			for edge, i in g_mem.edges {
				a := g_mem.vertices[edge[0]]
				b := g_mem.vertices[edge[1]] - g_mem.vertices[edge[0]]
				c := ray.position
				d := ray.direction

				distance := f32(1e500)
				ray_distance := f32(1e500)
				
				// Closest points on the lines
				disc := linalg.vector_dot(d, d) * linalg.vector_dot(b, b) - linalg.vector_dot(b, d) * linalg.vector_dot(b, d)
				if abs(disc) > 1e-6 {
					t := (linalg.vector_dot(d, a - c) * linalg.dot(b, b) - linalg.vector_dot(b, a - c) * linalg.vector_dot(b, d))/ disc
					s := (t * linalg.vector_dot(d, b) + linalg.vector_dot(c - a, b)) / linalg.vector_dot(b, b)
					if 0 <= s && s <= 1 && t > 0 {
						distance = linalg.distance(a + s * b, c + t * d)
						ray_distance = t * linalg.length(d)
					}
				}

				// Boundary checks
				s1 := clamp(linalg.vector_dot(c - a, b) / linalg.vector_dot(b, b), 0.0, 1.0)
				if distance > linalg.distance(a + s1 * b, c) {
					distance = linalg.distance(a + s1 * b, c)
					ray_distance = 0
				}
				t1 := max(linalg.vector_dot(a - c, d) / linalg.vector_dot(d, d), 0.0)
				if distance > linalg.distance(a, c + t1 * d) {
					distance = linalg.distance(a, c + t1 * d)
					ray_distance = t1 * linalg.length(d)
				}
				t2 := max(linalg.vector_dot(b - c, d) / linalg.vector_dot(d, d), 0.0)
				if distance > linalg.distance(b, c + t2 * d) {
					distance = linalg.distance(b, c + t2 * d)
					ray_distance = t2 * linalg.length(d)
				}

				if ray_distance > 0 && distance < 0.05 && ray_distance < min_ray_distance {
					min_ray_distance = ray_distance
					g_mem.hover_index = i
					g_mem.hover_type = .EDGE
				}
			}

			if g_mem.hover_index != -1 && g_mem.hover_type == .VERTEX && g_mem.drag_vertex == -1 {
				g_mem.cursor_world_point = g_mem.vertices[g_mem.hover_index] // Snap to vertex
			} else if g_mem.drag_vertex != -1 || g_mem.new_edge_start != -1 || g_mem.new_face_start != -1 {
				c := g_mem.drag_plane_distance / linalg.dot(ray.direction, linalg.normalize0(g_mem.camera.target - g_mem.camera.position))
				g_mem.cursor_world_point = g_mem.camera.position + c * ray.direction
			} else if g_mem.hover_index != -1 {
				// TODO: Note that we choose vertices and edges for world point even if they are on the opposite side of the plane.
				g_mem.cursor_world_point = ray.position + min_ray_distance * ray.direction
			} else {
				g_mem.cursor_world_point = ray.position + ray.direction * (-ray.position.y / ray.direction.y)
			}

			if g_mem.view == .EDIT_VERTEX {
				if rl.IsMouseButtonPressed(.LEFT) {
					vertex_hover := g_mem.hover_index != -1 && g_mem.hover_type == .VERTEX
					if vertex_hover {
						g_mem.drag_vertex = g_mem.hover_index
						g_mem.drag_plane_distance = linalg.dot(
							g_mem.vertices[g_mem.drag_vertex] - g_mem.camera.position,
							linalg.normalize0(g_mem.camera.target - g_mem.camera.position),
						)
					} else {
						append(&g_mem.vertices, g_mem.cursor_world_point)
					}
				}
				if g_mem.drag_vertex != -1 {
					// TODO: We are moving a point which can affect hover.
					// How do we handle this?
					g_mem.vertices[g_mem.drag_vertex] = g_mem.cursor_world_point
				}
				if rl.IsMouseButtonReleased(.LEFT) {
					g_mem.drag_vertex = -1
				}
			} else if g_mem.view == .EDIT_EDGE {
				if rl.IsMouseButtonPressed(.LEFT) && g_mem.hover_index != -1 && g_mem.hover_type == .VERTEX {
					g_mem.new_edge_start = g_mem.hover_index
					g_mem.drag_plane_distance = linalg.dot(
						g_mem.vertices[g_mem.new_edge_start] - g_mem.camera.position,
						linalg.normalize0(g_mem.camera.target - g_mem.camera.position),
					)
				}
				if rl.IsMouseButtonReleased(.LEFT) && g_mem.new_edge_start != -1 {
					if g_mem.hover_index == -1 || g_mem.hover_type == .EDGE {
						append(&g_mem.vertices, g_mem.cursor_world_point)
						append(&g_mem.edges, [2]int { g_mem.new_edge_start, len(g_mem.vertices) - 1 })
					} else if g_mem.hover_index != g_mem.new_edge_start {
						new_edge : [2]int = { g_mem.new_edge_start, g_mem.hover_index }
						if new_edge[0] > new_edge[1] {
							new_edge = new_edge.yx
						}
						found := false
						for e in g_mem.edges {
							if e == new_edge {
								found = true
							}
						}
						if !found {
							append(&g_mem.edges, new_edge)
						}
					}
					g_mem.new_edge_start = -1
				}
			} else {
				if rl.IsMouseButtonPressed(.LEFT) && g_mem.hover_index != -1 && g_mem.hover_type == .EDGE {
					g_mem.new_face_start = g_mem.hover_index
					g_mem.drag_plane_distance = linalg.dot(
						g_mem.cursor_world_point - g_mem.camera.position,
						linalg.normalize0(g_mem.camera.target - g_mem.camera.position),
					)
				}
				if rl.IsMouseButtonReleased(.LEFT) && g_mem.new_face_start != -1 {
					if g_mem.hover_index == -1 || g_mem.hover_type == .EDGE {
						append(&g_mem.vertices, g_mem.cursor_world_point)
						append(&g_mem.edges, [2]int { g_mem.edges[g_mem.new_face_start][0], len(g_mem.vertices) - 1 })
						append(&g_mem.edges, [2]int { g_mem.edges[g_mem.new_face_start][1], len(g_mem.vertices) - 1 })
						append(&g_mem.faces, [3]int { g_mem.edges[g_mem.new_face_start][0], g_mem.edges[g_mem.new_face_start][1], len(g_mem.vertices) - 1 })
					} else if g_mem.hover_index != g_mem.edges[g_mem.new_face_start][0] && g_mem.hover_index != g_mem.edges[g_mem.new_face_start][1] {
						for v in g_mem.edges[g_mem.new_face_start] {
							new_edge : [2]int = { v, g_mem.hover_index }
							if new_edge[0] > new_edge[1] {
								new_edge = new_edge.yx
							}
							found := false
							for e in g_mem.edges {
								if e == new_edge {
									found = true
								}
							}
							if !found {
								append(&g_mem.edges, new_edge)
							}
						}
						new_face : [3]int
						if g_mem.hover_index < g_mem.edges[g_mem.new_face_start][0] {
							new_face = { g_mem.hover_index, g_mem.edges[g_mem.new_face_start][0], g_mem.edges[g_mem.new_face_start][1] }
						} else if g_mem.hover_index < g_mem.edges[g_mem.new_face_start][1] {
							new_face = { g_mem.edges[g_mem.new_face_start][0], g_mem.hover_index, g_mem.edges[g_mem.new_face_start][1] }
						} else {
							new_face = { g_mem.edges[g_mem.new_face_start][0], g_mem.edges[g_mem.new_face_start][1], g_mem.hover_index }
						}
						found := false
						for f in g_mem.faces {
							if new_face == f {
								found = true
							}
						}
						if !found {
							append(&g_mem.faces, new_face)
						}
					}
					g_mem.new_face_start = -1
				}
			}
		}

		if rl.IsKeyPressed(.ONE) {
			g_mem.cursor = { 0.0, 0.0 }
			g_mem.hover_index = -1
			g_mem.drag_vertex = -1
			g_mem.new_edge_start = -1
			g_mem.new_face_start = -1
			g_mem.view = .MOVE
		}
		if rl.IsKeyPressed(.TWO) {
			g_mem.hover_index = -1
			g_mem.drag_vertex = -1
			g_mem.new_edge_start = -1
			g_mem.new_face_start = -1
			g_mem.view = .EDIT_VERTEX
		}
		if rl.IsKeyPressed(.THREE) {
			g_mem.hover_index = -1
			g_mem.drag_vertex = -1
			g_mem.new_edge_start = -1
			g_mem.new_face_start = -1
			g_mem.view = .EDIT_EDGE
		}
		if rl.IsKeyPressed(.FOUR) {
			g_mem.hover_index = -1
			g_mem.drag_vertex = -1
			g_mem.new_edge_start = -1
			g_mem.new_face_start = -1
			g_mem.view = .EDIT_FACE
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
	for face in g_mem.faces {
		rl.DrawTriangle3D(g_mem.vertices[face[0]], g_mem.vertices[face[1]], g_mem.vertices[face[2]], rl.GRAY) // TODO: Disable face culling
		rl.DrawTriangle3D(g_mem.vertices[face[0]], g_mem.vertices[face[2]], g_mem.vertices[face[1]], rl.GRAY)
	}
	for edge, i in g_mem.edges {
		color := rl.BLACK
		if g_mem.hover_index == i && g_mem.hover_type == .EDGE {
			color = rl.RED
		}
		rl.DrawLine3D(g_mem.vertices[edge[0]], g_mem.vertices[edge[1]], color)
	}
	for point, i in g_mem.vertices {
		color := rl.BLACK
		if g_mem.hover_index == i && g_mem.hover_type == .VERTEX {
			color = rl.RED
		}
		rl.DrawSphere(point, 0.05, color)
	}
	if g_mem.new_edge_start != -1 {
		rl.DrawLine3D(g_mem.vertices[g_mem.new_edge_start], g_mem.cursor_world_point, rl.RED)
	}
	if g_mem.new_face_start != -1 {
		rl.DrawTriangle3D(g_mem.vertices[g_mem.edges[g_mem.new_face_start][0]], g_mem.vertices[g_mem.edges[g_mem.new_face_start][1]], g_mem.cursor_world_point, rl.RED)
		rl.DrawTriangle3D(g_mem.vertices[g_mem.edges[g_mem.new_face_start][1]], g_mem.vertices[g_mem.edges[g_mem.new_face_start][0]], g_mem.cursor_world_point, rl.RED)
	}
	// Draw grid below y = 0.
	for i in -25..=25 {
		rl.DrawLine3D({ -25, -0.01, f32(i) }, { 25, -0.01, f32(i) }, rl.GRAY)
		rl.DrawLine3D({ f32(i), -0.01, -25 }, { f32(i), -0.01, 25 }, rl.GRAY)
	}
	rl.EndMode3D()
	// Draw hover indicator for vertices.
	if g_mem.hover_index != -1 && g_mem.hover_type == .VERTEX {
		rl.DrawCircle(i32(f32(rl.GetScreenWidth()) / 2.0 + g_mem.cursor.x), i32(f32(rl.GetScreenHeight()) / 2.0 + g_mem.cursor.y), 7.0, rl.RED)
	}
	rl.DrawCircle(i32(f32(rl.GetScreenWidth()) / 2.0 + g_mem.cursor.x), i32(f32(rl.GetScreenHeight()) / 2.0 + g_mem.cursor.y), 5.0, rl.ORANGE)

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("FPS: %v", rl.GetFPS()), { 10.0, 10.0 }, 32, 0.0, rl.BLACK)
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("Vertices: %v", len(g_mem.vertices)), { 10.0, 50.0 }, 32, 0.0, rl.BLACK)
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("Edges: %v", len(g_mem.edges)), { 10.0, 90.0 }, 32, 0.0, rl.BLACK)
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("Faces: %v", len(g_mem.faces)), { 10.0, 130.0 }, 32, 0.0, rl.BLACK)
	rl.DrawTextEx(g_mem.font, fmt.ctprintf("View: %v", g_mem.view), { 10.0, 170.0 }, 32, 0.0, rl.BLACK)

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
		drag_vertex = -1,
		new_edge_start = -1,
		new_face_start = -1,
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
	delete(g_mem.edges)
	delete(g_mem.faces)
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
