/* [[file:../../../blender.org::*a-star][a-star:1]] */
package astar_test

import "core:os"
import "core:fmt"
import "core:mem"
import "core:strings"
import "vendor:raylib"
import astar "../"

import "base:runtime"
import "core:prof/spall"
import "core:sync"

Values :: struct {
  show_menu: bool,
  texture_selected: string,
  texture_open: bool,
  texture_scroll: i32,
  texture_cost: f32,
  show_costs: bool,
  show_arrows: bool,
  show_path: bool,
  panel_rect: raylib.Rectangle,
}

Cell :: struct {
  x: int,
  y: int,
  key: int,
  texture_name: string,
  texture: ^raylib.Texture,
}

Grid :: struct {
  dim: [2]int,
  screen_dim: [2]int,
  graph : astar.Graph(Cell),
  
  texture_names: [dynamic]string,            // list of possible textures for a cell
  textures: map[string]raylib.Texture,
  background_texture_names: [dynamic]string, // list of possible background grid textures
  background_textures: map[string]raylib.Texture,
  background: string,                        // index of background_texture to use

  start: ^Cell,
  end: ^Cell,
  scale: f32,
  cell_size: int,
  draw_grid_lines: bool,
}

WITH_TRACKING_ALLOC :: false
spall_ctx: spall.Context
@(thread_local) spall_buffer: spall.Buffer

reconstruct_path :: proc(grid: ^Grid, came_from: []int, cost_so_far: map[int]f32) -> (path: [dynamic][2]int) {
  current := grid.end^
  for i := 0; !(current.x == grid.start.x && current.y == grid.start.y); i += 1 {
    append(&path, [2]int{current.x, current.y})
    curr := current.y * grid.dim.x + current.x
    current.x = came_from[curr] % grid.dim.x
    current.y = came_from[curr] / grid.dim.x
  }
  append(&path, [2]int{grid.start.x, grid.start.y})
  return
}

draw_cursor :: proc() {
  using raylib

  // custom mouse cursor
  //cursor_tex := LoadTexture("./assets/Preview.png")
  // TODO: custom cursor
  
  if IsKeyDown(KeyboardKey.S) {
    SetMouseCursor(MouseCursor.CROSSHAIR)
  } else if IsKeyDown(KeyboardKey.E) {
    SetMouseCursor(MouseCursor.CROSSHAIR)
  } else {
    SetMouseCursor(MouseCursor.DEFAULT)
  }
}

draw_cost :: proc(grid: ^Grid, cost_so_far: map[int]f32 = nil) {
  using raylib

  @static grad_img : ^Image
  if grad_img == nil {
    grad_img = new(Image)
    grad_img^ = GenImageGradientLinear(101, 1, 90, Color{0,255,0,150}, Color{255,0,0,150})
  }
  highest_cost : f32 = 0
  for y in 0..<grid.dim.y {
    for x in 0..<grid.dim.x {
      idx := y * grid.dim.x + x
      if idx < len(grid.graph.nodes) && highest_cost < cost_so_far[idx] {
        highest_cost = f32(cost_so_far[idx])
      }
    }
  }
  for y in 0..<grid.dim.y {
    for x in 0..<grid.dim.x {
      idx := y * grid.dim.x + x
      if idx < len(grid.graph.nodes) {
        //tmp := grid.graph.nodes[idx]
        //oh := tmp.key % 101
        oh := int((cost_so_far[idx] / highest_cost) * 101)
        data := transmute([^]([4]u8))grad_img.data
        col := Color{data[oh].x, data[oh].y, data[oh].z, 15}
        
        cs := int(f32(grid.cell_size) * grid.scale)
        dst := Rectangle{f32(x * cs), f32(y * cs), f32(cs), f32(cs)}
        DrawRectangleRec(dst, col)
        
        str := fmt.tprintf("%2d", oh)
        cstr := strings.clone_to_cstring(str); defer delete(cstr)
        col.a = 190
        fs := (f32(cs) * 0.25)
        DrawText(cstr, i32(dst.x+fs), i32(dst.y+fs), i32(f32(cs)*0.5), col)
      }
    }
  }
}

draw_grid :: proc(grid: ^Grid, values: ^Values, came_from: []int = nil, cost_so_far: map[int]f32 = nil, path: [dynamic][2]int = nil) {
  using raylib

  // background textures are roughly 1024x1024 with 4 by 4 grid/folds
  tmp := int(1024 * grid.scale)
  tex_x_cnt := (grid.screen_dim.x / tmp) + 1
  tex_y_cnt := (grid.screen_dim.y / tmp) + 1
  rot : f32 = 0

  for y in 0..<tex_y_cnt { // draw just enuf background to cover the window
    for x in 0..<tex_x_cnt {
      pos := Vector2{f32(x * tmp), f32(y * tmp)}
      DrawTextureEx(grid.background_textures[grid.background], pos, rot, grid.scale, WHITE)
      // TODO: partially filled cells?
    }
  }
  // draw a line between each cell?  1024 / 4 = 256 == cell size (w/o scale)
  if grid.draw_grid_lines {
    for hline_y := 0; hline_y < grid.screen_dim.y; hline_y += int(f32(grid.cell_size) * grid.scale) {
      DrawLine(0, i32(hline_y), i32(grid.screen_dim.x), i32(hline_y), BLACK)
    }
    for vline_x := 0; vline_x < grid.screen_dim.x; vline_x += int(f32(grid.cell_size) * grid.scale) {
      DrawLine(i32(vline_x), 0, i32(vline_x), i32(grid.screen_dim.y), BLACK)
    }
  }

  cs := int(f32(grid.cell_size) * grid.scale)
  cs2 := [2]f32{f32(cs), f32(cs)}
  for y in 0..<grid.dim.y {
    for x in 0..<grid.dim.x {
      idx := y * grid.dim.x + x
      if idx < len(grid.graph.nodes) {
        tmp := grid.graph.nodes[idx]
        if tmp.texture_name != "" {
          tex := grid.textures[tmp.texture_name]
          src := Rectangle{0, 0, f32(tex.width), f32(tex.height)}
          dst := Rectangle{f32(x * cs), f32(y * cs), f32(cs), f32(cs)}
          origin := Vector2{0, 0}
          rot : f32 = 0
          DrawTexturePro(tex, src, dst, origin, rot, WHITE)
        }
      }
    }
  }

  for p, idx in path {
    // draw a line from middle of p to middle of next p
    if idx < (len(path)-1) {
      a := [?]f32{f32(p.x) + 0.5, f32(p.y) + 0.5}
      b := [?]f32{f32(path[idx+1].x) + 0.5, f32(path[idx+1].y) + 0.5}
      a = a * cs2
      b = b * cs2
      DrawLine(i32(a.x), i32(a.y), i32(b.x), i32(b.y), BLACK)
    }
  }

  if values.show_costs {
    draw_cost(grid, cost_so_far)
  }
}

draw_menu :: proc(w, h: int, grid: ^Grid, values: ^Values) {
  using raylib

  if !values.show_menu {
    values.show_menu = GuiButton(Rectangle{f32(w) - 40, 13, 18, 18}, "_")
  } else {
    tmp_rect := values.panel_rect
    tmp_rect.x = f32(w) - tmp_rect.x
    panel := GuiPanel(tmp_rect, "")
    values.show_menu = !GuiButton(Rectangle{f32(w) - 40, 13, 18, 18}, "_")

    tmp_x := f32(grid.dim.x)
    tmp_y := f32(grid.dim.y)
    str := fmt.tprintf("%v x %v", i32(tmp_x), i32(tmp_y))
    cstr := strings.clone_to_cstring(str)
    GuiTextBox(Rectangle{f32(w) - 185, 40, 160, 20}, cstr, 10, false)
    delete(cstr)
    // scale and cell_size
    tmp_scale := f32(grid.scale)
    GuiSlider(Rectangle{f32(w) - 185, 65, 160, 20}, "scale", "", &tmp_scale, 0.1, 2)
    grid.scale = tmp_scale
    str = fmt.tprintf("%v", tmp_scale)
    cstr = strings.clone_to_cstring(str)
    GuiTextBox(Rectangle{f32(w) - 185, 65, 160, 20}, cstr, 10, false)
    delete(cstr)

    str = ""
    for idx in values.texture_scroll..<i32(len(grid.texture_names)) {
      if idx > (values.texture_scroll+10) { // show only 10 at a time
        break
      }
      s := grid.texture_names[idx]
      if idx == values.texture_scroll {
        str = fmt.tprintf("%s", s)
      } else {
        str = fmt.tprintf("%s\n%s", str, s)
      }
    }
    cstr = strings.clone_to_cstring(str)
    active : i32 = 0
    for s,idx in grid.texture_names {
      if values.texture_selected == s {
        active = i32(idx) - values.texture_scroll
        break
      }
    }
    // show selected .png above this dropdown
    tex := grid.textures[values.texture_selected]
    src := Rectangle{0, 0, f32(tex.width), f32(tex.height)}
    dst := Rectangle{f32(w) - 135, 100, 50, 50}
    origin := Vector2{0, 0}
    rot : f32 = 0
    DrawTexturePro(tex, src, dst, origin, rot, WHITE)

    if GuiDropdownBox(Rectangle{f32(w) - 185, 160, 160, 20}, cstr, &active, values.texture_open) {
      values.texture_open = !values.texture_open
      for s,idx in grid.texture_names {
        if active + values.texture_scroll == i32(idx) {
          values.texture_selected = s
          break
        }
      }
    }
    delete(cstr)

    if !values.texture_open {
      if GuiToggle(Rectangle{f32(w) - 185, 185, 160, 20}, "show costs", &values.show_costs) > 0 {
        values.show_costs = !values.show_costs
      }
      if GuiToggle(Rectangle{f32(w) - 185, 210, 160, 20}, "show arrows", &values.show_arrows) > 0 {
        values.show_arrows = !values.show_arrows
      }

      tmp_cost := f32(values.texture_cost)
      GuiSlider(Rectangle{f32(w) - 185, 235, 160, 20}, "cost", "", &tmp_cost, 0, 100)
      values.texture_cost = tmp_cost
      str = fmt.tprintf("%v", i32(tmp_cost))
      cstr := strings.clone_to_cstring(str)
      GuiTextBox(Rectangle{f32(w) - 185, 235, 160, 20}, cstr, 10, false)
      delete(cstr)

      GuiSetStyle(GuiControl.LABEL, i32(GuiControlProperty.TEXT_COLOR_NORMAL), transmute(i32)Color{255,0,0,255})
      str = "hold 'S' and left mouse click\nto place start\nhold 'E' and left mouse click\nto place end"
      cstr = strings.clone_to_cstring(str)
      GuiLabel(Rectangle{f32(w) - 200, 310, 160, 20}, cstr)
      delete(cstr)
    }    
  }
}

cell_get_node_index :: proc(n: Cell, r: rawptr) -> int {
  return astar.get_node_index(n, r)
}
cell_key :: proc(n: Cell) -> f32 {
  return astar.key(n)
}
cell_heuristic :: proc(n, m: Cell) -> f32 {
  return astar.heuristic(n, m)
}
cell_less :: proc(a,b: Cell) -> bool {
  return astar.less(a,b)
}

main :: proc() {
  using raylib
  
  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    when WITH_TRACKING_ALLOC {
      mem.tracking_allocator_init(&track, context.allocator)
      context.allocator = mem.tracking_allocator(&track)
    }
    
    spall_ctx = spall.context_create("trace_test.spall")
    buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
    spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
    spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
    
    defer {
      spall.buffer_flush(&spall_ctx, &spall_buffer)

      spall.context_destroy(&spall_ctx)
      spall.buffer_destroy(&spall_ctx, &spall_buffer)
      delete(buffer_backing)

      when WITH_TRACKING_ALLOC {      
        if len(track.allocation_map) > 0 {
          fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
          for _, entry in track.allocation_map {
            fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
          }
        }
        if len(track.bad_free_array) > 0 {
          fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
          for entry in track.bad_free_array {
            fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
          }
          mem.tracking_allocator_destroy(&track)
        }
      }
    }
  }
  
  {
    spall._buffer_begin(&spall_ctx, &spall_buffer, "astar search")
    defer spall._buffer_end(&spall_ctx, &spall_buffer)

    values : Values
    values.show_menu = false
    values.show_costs = true
    values.show_arrows = false
    values.show_path = true
    values.panel_rect = Rectangle{230, 10, 220, 430}
    
    grid : Grid
    grid.screen_dim.x = 500
    grid.screen_dim.y = 500
    grid.background = ""
    grid.draw_grid_lines = true
    grid.scale = 0.25
    grid.cell_size = 128 // scale * cell_size = actual pixel size of cell
    grid.start = new(Cell); defer free(grid.start)
    grid.end = new(Cell); defer free(grid.end)

    SetConfigFlags(ConfigFlags{ConfigFlag.WINDOW_RESIZABLE})
    InitWindow(i32(grid.screen_dim.x), i32(grid.screen_dim.y), "A* search testing")
    SetTargetFPS(60)
    
    hdl, err1 := os.open("./assets/PNG/Default/")
    fi, err := os.read_dir(hdl, 0)
    for f, i in fi {
      if i == 0 {
        values.texture_selected = f.name
      }
      append(&grid.texture_names, f.name)
      cstr := strings.clone_to_cstring(fmt.tprintf("assets/PNG/Default/%s", f.name)); defer delete(cstr)
      grid.textures[f.name] = LoadTexture(cstr)
    }
    hdl, err1 = os.open("./assets/Textures/")
    fi, err = os.read_dir(hdl, 0)
    for f, i in fi {
      if i == 0 { // just grab first as default
        grid.background = f.name
      }
      append(&grid.background_texture_names, f.name)
      cstr := strings.clone_to_cstring(fmt.tprintf("assets/Textures/%s", f.name)); defer delete(cstr)
      grid.background_textures[f.name] = LoadTexture(cstr)
    }
      
    was_change := true
    came_from : []int
    cost_so_far : map[int]f32
    path : [dynamic][2]int

    for !WindowShouldClose() {
      // Update ------------------------------
      grid.screen_dim.x = int(GetScreenWidth())
      grid.screen_dim.y = int(GetScreenHeight())
      tmp := grid.scale * f32(grid.cell_size)
      prev_dim := grid.dim
      grid.dim.x = int(f32(grid.screen_dim.x) / tmp)
      grid.dim.y = int(f32(grid.screen_dim.y) / tmp)
      if prev_dim != grid.dim {
        tmp_cells := make([]Cell, grid.dim.x * grid.dim.y)
        for y in 0..<grid.dim.y {
          for x in 0..<grid.dim.x {
            idx := y * grid.dim.x + x
            tmp_cells[idx].x = int(x)
            tmp_cells[idx].y = int(y)
            tmp_cells[idx].key = 20
          }
        }

        // transfer all possible visible grid cells
        for y in 0..<prev_dim.y {
          for x in 0..<prev_dim.x {
            idx1 := y * prev_dim.x + x
            idx2 := y * grid.dim.x + x
            if int(idx1) < len(grid.graph.nodes) && int(idx2) < len(tmp_cells) {
              tmp_cells[idx2] = grid.graph.nodes[idx1]
            }
          }
        }
        grid.graph.nodes = tmp_cells
      }
      mwm := GetMouseWheelMove()
      if values.texture_open {
        values.texture_scroll -= i32(mwm)
        if values.texture_scroll < 0 do values.texture_scroll = 0
        if values.texture_scroll >= i32(len(grid.texture_names)) do values.texture_scroll = i32(len(grid.texture_names)-1)
      }

      if IsMouseButtonDown(MouseButton.LEFT) {
        // put texture_selected here at grid pos
        pos := GetMousePosition()
        tmp_rect := values.panel_rect
        tmp_rect.x = f32(grid.screen_dim.x) - tmp_rect.x
        if !values.show_menu || !CheckCollisionPointRec(pos, tmp_rect) { // check not in menu
          grid_pos : [2]int
          tmp := f32(grid.cell_size) * grid.scale
          grid_pos.x = int(pos.x / tmp)
          grid_pos.y = int(pos.y / tmp)

          idx := grid_pos.y * grid.dim.x + grid_pos.x
          if int(idx) < len(grid.graph.nodes) {
            if grid.graph.nodes[idx].texture_name != values.texture_selected {
              was_change = true
              grid.graph.nodes[idx].texture_name = values.texture_selected
              grid.graph.nodes[idx].x = int(grid_pos.x)
              grid.graph.nodes[idx].y = int(grid_pos.y)
              grid.graph.nodes[idx].key = int(values.texture_cost)
              if IsKeyDown(KeyboardKey.S) {
                grid.start.x = int(grid_pos.x)
                grid.start.y = int(grid_pos.y)
                grid.start.key = int(values.texture_cost)
              }
              if IsKeyDown(KeyboardKey.E) {
                grid.end.x = int(grid_pos.x)
                grid.end.y = int(grid_pos.y)
                grid.end.key = int(values.texture_cost)
              }
            }
          }
        }
      }

      if was_change {
        grid.graph.data = transmute(rawptr)&[2]int{int(grid.dim.x), int(grid.dim.y)}
        
        grid.graph.get_node_index = cell_get_node_index
        grid.graph.edges = astar.edges
        grid.graph.key = cell_key
        grid.graph.heuristic = cell_heuristic
        grid.graph.less = cell_less
        if grid.graph.get_node_index(grid.start^, grid.graph.data) > len(grid.graph.nodes) {
          grid.start.x = 0
          grid.start.y = 0
        }
        if grid.graph.get_node_index(grid.end^, grid.graph.data) > len(grid.graph.nodes) {
          grid.end.x = 0
          grid.end.y = 0
        }

        came_from, cost_so_far = astar.search(grid.start^, grid.end^, grid.graph)
        path = reconstruct_path(&grid, came_from, cost_so_far)
        was_change = false
      }
      
      // Draw   ------------------------------
      BeginDrawing()
      ClearBackground(BLUE)

      draw_grid(&grid, &values, came_from, cost_so_far, path)
      draw_menu(grid.screen_dim.x, grid.screen_dim.y, &grid, &values)

      draw_cursor()
      
      EndDrawing()
    }
    CloseWindow()    
  }
}

// Automatic profiling of every procedure:
@(instrumentation_enter)
spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
  spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
  spall._buffer_end(&spall_ctx, &spall_buffer)
}
/* a-star:1 ends here */
