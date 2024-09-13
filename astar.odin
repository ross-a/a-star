/* [[file:../../blender.org::*a-star][a-star:2]] */
package astar


import "core:mem"
import "core:fmt"
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
  horizontal :: proc(x, w: int) -> (int, bool) { if x >= 0 && x < w do return x, true; return 0, false }
  vertical :: proc(y, h: int) -> (int, bool) { if y >= 0 && y < h do return y, true; return 0, false }    

  if is_corner {
    ret = make([]int, 2)
  } else if is_edge {
    ret = make([]int, 3)
  } else {
    ret = make([]int, 4)
  }

  xy : [4]int; oks : [4]bool
  xy[0], oks[0] = horizontal(x+1, w)
  xy[1], oks[1] = horizontal(x-1, w)      
  xy[2], oks[2] = vertical(y+1, h)
  xy[3], oks[3] = vertical(y-1, h)

  idx := 0
  for i in 0..<4 { // 2 to 4 edges
    if oks[i] {
      if i <= 1 {
        ret[idx] = y * w + xy[i]; idx += 1
      } else {
        ret[idx] = xy[i] * w + x; idx += 1
      }
    }
  }
  return ret
}

key :: proc(a: $T) -> f32 {
  return a.key                                          // assumes .key in struct a
}

heuristic :: proc(a, b: $T) -> f32 {
  // some cost from a to b
  return f32(abs(a.x - b.x) + abs(a.y - b.y))           // assumes .x,.y in struct of a and b
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

    e := graph.edges(curr_node, graph.data); defer delete(e)
    for next in e {
      neighbor := graph.nodes[next]

      neighbor_node := graph.get_node_index(neighbor, graph.data)
      new_cost := cost_so_far[curr_node] + key(neighbor)

      csf, ok := cost_so_far[neighbor_node]
      if !ok || new_cost < csf {
        idx := graph.get_node_index(neighbor, graph.data)
        cost_so_far[idx] = new_cost
        neighbor.key = new_cost + heuristic(graph.nodes[neighbor_node], graph.nodes[goal_node])

        new_node := new(pheap.Pairing_Heap(P))
        pheap.init(new_node, graph.less)
        new_node.elem = neighbor

        pheap.push(&frontier, new_node)
        came_from[neighbor_node] = curr_node
      }
    }
  }
  return
}
/* a-star:2 ends here */
