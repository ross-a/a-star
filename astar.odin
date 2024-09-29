/* [[file:../../blender.org::*a-star][a-star:2]] */
package astar

import "core:mem"
import "core:fmt"
import "core:math"
import pheap "../pairing_heap"

INF :: 1e5000 // for walls infinite key/weight

// Graph with nodes of type T, some key and some heuristic, etc
Graph :: struct($T: typeid) {
  nodes : []T,
  data: rawptr, // contains something like ^[2]int{width, height}

  get_node_index : proc(a: T, data: rawptr) -> int,
  edges : proc(node_idx: int, data: rawptr, clean: bool = false) -> []int, // return list of edges for this node index
  key : proc(a: T) -> f32, // TODO: rename cost at a??
  less : proc(a, b: T) -> bool,
  heuristic : proc(a, b: T) -> f32,
}

// Helper astar procs ---
// helper procs need to be rewritten if you have non-2dgrid graph
// note: BOTH get_node_index() and edges() expects data to be width and height of grid
get_node_index :: proc(a: $T, data: rawptr) -> int {
  grid_wh := transmute(^[2]int)data
  w := grid_wh[0]
  return a.y * w + a.x
}

edges :: proc(node_idx: int, data: rawptr, clean: bool = false) -> (ret: []int) {
  grid_wh := transmute(^[2]int)data
  w := grid_wh[0]
  h := grid_wh[1]
  x := node_idx % w
  y := node_idx / w
  is_corner := (node_idx == 0 || node_idx == w-1 || node_idx == (h-1) * grid_wh[0] || node_idx == (w * h)-1)
  is_edge := (x == 0 || x == w-1 || y == 0 || y == h-1)
  horizontal :: proc(x, w: int) -> (int, bool) {
    if x >= 0 && x < w {
      return x, true
    }
    return 0, false
  }
  vertical :: proc(y, h: int) -> (int, bool) {
    if y >= 0 && y < h {
      return y, true
    }
    return 0, false
  }
  diagonal :: proc(x, y: int, w, h: int) -> (int, int, bool) {
    if x >= 0 && x < w && y >= 0 && y < h {
      return x, y, true
    }
    return 0, 0, false
  }

  WITH_DIAGONAL :: false
  
  if is_corner {
    ret = make([]int, 2 + (WITH_DIAGONAL ? 1 : 0)) // corners have 2 or 3 connections
  } else if is_edge {
    ret = make([]int, 3 + (WITH_DIAGONAL ? 2 : 0)) // edge of grid has 3 or 5 connections
  } else {
    ret = make([]int, 4 + (WITH_DIAGONAL ? 4 : 0)) // every other grid cell should be completely surrounded (4 or 8)
  }

  xy : [4]int; oks : [8]bool
  xy[0], oks[0] = horizontal(x+1, w)
  xy[1], oks[1] = horizontal(x-1, w)      
  xy[2], oks[2] = vertical(y+1, h)
  xy[3], oks[3] = vertical(y-1, h)
  // maybe diagonals
  dxy : [8]int
  dxy[0], dxy[1], oks[4] = diagonal(x+1, y+1, w, h)
  dxy[2], dxy[3], oks[5] = diagonal(x+1, y-1, w, h)
  dxy[4], dxy[5], oks[6] = diagonal(x-1, y+1, w, h)
  dxy[6], dxy[7], oks[7] = diagonal(x-1, y-1, w, h)

  idx := 0
  for i in 0..<(WITH_DIAGONAL ? 8 : 4) { // 2 to 8 edges
    if oks[i] {
      if i <= 1 {
        ret[idx] = y * w + xy[i]; idx += 1
      } else if i <= 3 {
        ret[idx] = xy[i] * w + x; idx += 1
      } else if i % 2 == 0 {
        ii := i - 4
        ret[idx] = dxy[ii+1] * w + dxy[ii]; idx += 1
      }
    }
  }
  return ret
}

key :: proc(a: $T) -> f32 {
  return f32(a.key)                                     // assumes .key in struct a
}

heuristic :: proc(a, b: $T) -> f32 {
  //return f32(abs(a.x - b.x) + abs(a.y - b.y))         // assumes .x,.y in struct of a and b
  // use euclidean dist?
  return math.sqrt_f32(math.pow(f32(a.x - b.x), 2) + math.pow(f32(a.y - b.y), 2))
}

less :: proc(a, b: $T) -> bool { return a.key < b.key } // assume .key in a and b

search :: proc(start, goal: $T, graph: Graph($P)) -> (came_from: []int, cost_so_far: map[int]f32) {
  // A* search... should be general purpose enough to handle most/any Graph (only 2d tested)
  frontier := new(pheap.Pairing_Heap(P)); defer free(frontier)
  pheap.init(frontier, graph.less)
  frontier.elem = start

  came_from = make([]int, len(graph.nodes))
  for &i in came_from { i = -1 }

  start_node := graph.get_node_index(start, graph.data)
  goal_node := graph.get_node_index(goal, graph.data)
  came_from[start_node] = -1 // -1 is invalid index
  cost_so_far[start_node] = 0.0

  cnt := 0
  for ; frontier != nil; {
    popped := pheap.pop(&frontier); defer free(popped)
    curr_node := graph.get_node_index(popped.elem, graph.data)
    curr := graph.nodes[curr_node]

    e := graph.edges(curr_node, graph.data); defer delete(e)
    for next in e {
      neighbor := graph.nodes[next]
      new_cost := cost_so_far[curr_node] + (key(neighbor) * heuristic(neighbor, curr))
      csf, ok := cost_so_far[next]

      if !ok || (new_cost < csf) {
        cost_so_far[next] = new_cost // set to a new cheaper cost

        // heuristic used only here to "pick best direction to take" sort of thing
        neighbor.key = int(new_cost + heuristic(neighbor, graph.nodes[goal_node]))

        new_node := new(pheap.Pairing_Heap(P))
        pheap.init(new_node, graph.less)
        new_node.elem = neighbor

        pheap.push(&frontier, new_node)
        came_from[next] = curr_node
      }
    }
  }
  return
}
/* a-star:2 ends here */
