/* [[file:../../../blender.org::*a-star][a-star:1]] */
package astar_test


import "core:fmt"
import "core:mem"
import astar "../"

import "base:runtime"
import "core:prof/spall"
import "core:sync"

Node2d :: struct {
  x: int,
  y: int,
  key: f32,
}

WITH_TRACKING_ALLOC :: false
spall_ctx: spall.Context
@(thread_local) spall_buffer: spall.Buffer

main :: proc() {
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

  reconstruct_path :: proc(start, goal: Node2d, width: int, came_from: []int, cost_so_far: map[int]f32) -> (path: [dynamic][2]int) {
    current := goal
    for i := 0; !(current.x == start.x && current.y == start.y); i += 1 {
      append(&path, [2]int{current.x, current.y})
      curr := current.y * width + current.x
      current.x = came_from[curr] % width
      current.y = came_from[curr] / width
    }
    append(&path, [2]int{start.x, start.y})
    return
  }

  // this will make a 10 x 10 grid with most tiles at cost 1 (maybe think dirt path), some at 5.5 (maybe think water ~) and some at INF (impassable #)
  make_diamond4 :: proc(g: ^[]Node2d) {
    for j in 0..<10 {
      for i in 0..<10 {
        g[j*10 + i].x = i
        g[j*10 + i].y = j
        g[j*10 + i].key = 1
      }
      //if j == 0 { g[j*10 + 4].key = astar.INF }

      if j == 1 { g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; }
      if j == 2 { g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; g[j*10 + 5].key = 5.5; }
      if j == 3 { g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; g[j*10 + 6].key = 5.5; g[j*10 + 7].key = 5.5; }

      if j == 4 { g[j*10 + 3].key = 5.5; g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; g[j*10 + 6].key = 5.5; g[j*10 + 7].key = 5.5; }
      if j == 5 { g[j*10 + 3].key = 5.5; g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; g[j*10 + 6].key = 5.5; g[j*10 + 7].key = 5.5; }

      if j == 6 { g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; g[j*10 + 6].key = 5.5; }
      if j == 7 { g[j*10 + 1].key = astar.INF; g[j*10 + 2].key = astar.INF; g[j*10 + 3].key = astar.INF; g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; g[j*10 + 6].key = 5.5; }
      if j == 8 { g[j*10 + 1].key = astar.INF; g[j*10 + 2].key = astar.INF; g[j*10 + 3].key = astar.INF; g[j*10 + 4].key = 5.5; g[j*10 + 5].key = 5.5; }

      //if j == 9 { g[j*10 + 1].key = astar.INF; }
    }
  }

  FG_BLACK :: "\033[30m";       BG_BLACK :: "\033[40m"   
  FG_RED :: "\033[31m";         BG_RED :: "\033[41m"     
  FG_GREEN :: "\033[32m";       BG_GREEN :: "\033[42m"   
  FG_YELLOW :: "\033[33m";      BG_YELLOW :: "\033[43m"  
  FG_BLUE :: "\033[34m";        BG_BLUE :: "\033[44m"    
  FG_PURPLE :: "\033[35m";      BG_PURPLE :: "\033[45m"  
  FG_CYAN :: "\033[36m";        BG_CYAN :: "\033[46m"    
  FG_GRAY :: "\033[37m";        BG_GRAY :: "\033[47m"
  FG_DEFAULT :: "\033[39m";     BG_DEFAULT :: "\033[49m"

  draw_grid :: proc(g: ^[]Node2d, start: ^Node2d = nil, goal: ^Node2d = nil, came_from: []int = nil, cost_so_far: map[int]f32 = nil, path: [dynamic][2]int = nil) {
    for j in 0..<10 {
      for i in 0..<10 {
        ch : string
        fg := FG_DEFAULT
        bg := BG_DEFAULT
        idx := j*10 + i
        if g[idx].key == 1 do ch = " . "
        if g[idx].key >= 5 do ch = " ~ "
        if g[idx].key == astar.INF do ch = " # "

        if came_from != nil {
          arrows := []rune {'\u2190', '\u2191', '\u2192', '\u2193'} // left, up, right, down

          cf := came_from[idx]
          if cf != -1 {
            bg = BG_BLUE

            if cf + 1 == idx do ch = fmt.tprintf(" %c ", arrows[0])
            if cf - 1 == idx do ch = fmt.tprintf(" %c ", arrows[2])
            if cf + 10 == idx do ch = fmt.tprintf(" %c ", arrows[1])
            if cf - 10 == idx do ch = fmt.tprintf(" %c ", arrows[3])
          }
        }

        csf, ok := cost_so_far[idx]
        if ok && csf != astar.INF {
          bg = BG_YELLOW
          ch = fmt.tprintf(" %2.0f", csf)
        }

        if path != nil {
          for p in path {
            if p.x == i && p.y == j {
              fg = FG_BLACK
              bg = BG_GRAY
            }
          }
        }

        if start != nil && (j == start.y && i == start.x) {
          bg = BG_CYAN
          ch = " A "
        }
        if goal != nil && (j == goal.y && i == goal.x) {
          bg = BG_CYAN
          ch = " Z "
        }

        fmt.printf("%s%s%s%s%s", fg, bg, ch, FG_DEFAULT, BG_DEFAULT)
      }
      fmt.println()
    }
    fmt.println()
  }

  diamond4_get_node_index :: proc(n: Node2d, r: rawptr) -> int {
    return astar.get_node_index(n, r)
  }
  diamond4_key :: proc(n: Node2d) -> f32 {
    return astar.key(n)
  }
  diamond4_heuristic :: proc(n: Node2d, m: Node2d) -> f32 {
    return astar.heuristic(n, m)
  }
  diamond4_less :: proc(a,b: Node2d) -> bool {
    return astar.less(a,b)
  }

  // TODO: bigger searches
  {
    spall._buffer_begin(&spall_ctx, &spall_buffer, "diamond4 search")
    defer spall._buffer_end(&spall_ctx, &spall_buffer)

    diamond4 : astar.Graph(Node2d)
    diamond4.nodes = make([]Node2d, 10 * 10); defer delete(diamond4.nodes)
    diamond4.data = transmute(rawptr)&[2]int{10, 10}
    diamond4.get_node_index = diamond4_get_node_index
    diamond4.edges = astar.edges
    diamond4.key = diamond4_key
    diamond4.heuristic = diamond4_heuristic
    diamond4.less = diamond4_less
    make_diamond4(&diamond4.nodes)

    start := Node2d{1,4,0} // x, y, key
    goal := Node2d{8,3,0}

    came_from, cost_so_far := astar.search(start, goal, diamond4)
    defer delete(came_from); defer delete(cost_so_far)

    // Draw 3 grids showing:
    //  costs (cost from A(start) to here)
    //  came_from (direction grid (or direction you go from Z to get back to A))
    //  searched for shortest path from A to Z
    // note: reconstruct_path() just makes a path by going from Z to A via came_from look ups,
    // so you can set Z(goal) to anything and get back to A without doing another search()
    // or to be clear:
    // if A was the player, many enemies could find their path to the player without doing ANOTHER search()
    draw_grid(g=&diamond4.nodes, start=&start, goal=&goal, cost_so_far=cost_so_far)
    draw_grid(g=&diamond4.nodes, start=&start, goal=&goal, came_from=came_from)
    path := reconstruct_path(start, goal, 10, came_from, cost_so_far)
    defer delete(path)
    draw_grid(g=&diamond4.nodes, start=&start, goal=&goal, path=path)
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
