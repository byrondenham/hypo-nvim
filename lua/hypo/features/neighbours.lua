-- features/neighbours.lua
-- Client-side graph utilities (simple BFS & degree ranking)
local M = {}
local provider = require('hypo.provider')

-- Build a simple adjacency map from provider.graph (if available)
function M.build_graph(cb)
  -- attempt to use provider.neighbours with a special flag if available
  provider.neighbours('__all__', 1, function(ok, res)
    -- backends may not support this; if not, client will fetch graph endpoint via adapter directly
    if ok and res then
      local nodes = {}
      local adj = {}
      for _, n in ipairs(res) do
        nodes[n.id] = n
        adj[n.id] = adj[n.id] or {}
        for _, e in ipairs(n.neighbours or {}) do
          adj[n.id][e] = true
          adj[e] = adj[e] or {}
          adj[e][n.id] = true
        end
      end
      cb(true, { nodes = nodes, adj = adj })
      return
    end
    -- fallback: try provider.list_notes and build empty adj (server-only)
    provider.list_notes(function(ok2, notes)
      if not ok2 then
        cb(false, 'no graph available')
        return
      end
      local nodes = {}
      local adj = {}
      for _, n in ipairs(notes) do
        nodes[n.id] = n
        adj[n.id] = adj[n.id] or {}
      end
      cb(true, { nodes = nodes, adj = adj })
    end)
  end)
end

local function bfs(adj, start, depth)
  local q = { start }
  local seen = { [start] = 0 }
  local out = {}
  while #q > 0 do
    local cur = table.remove(q, 1)
    local dcur = seen[cur]
    if dcur < depth then
      for nb, _ in pairs(adj[cur] or {}) do
        if not seen[nb] then
          seen[nb] = dcur + 1
          table.insert(q, nb)
        end
      end
    end
  end
  for id, d in pairs(seen) do
    if id ~= start then
      table.insert(out, { id = id, degree = 0, depth = d })
    end
  end
  return out
end

function M.neighbours(id, depth, cb)
  depth = depth or 1
  M.build_graph(function(ok, graph)
    if not ok then
      cb(false, graph)
      return
    end
    local list = bfs(graph.adj, id, depth)
    -- compute degrees
    for _, node in ipairs(list) do
      local deg = 0
      for _ in pairs(graph.adj[node.id] or {}) do
        deg = deg + 1
      end
      node.degree = deg
      node.title = (graph.nodes[node.id] and graph.nodes[node.id].title) or ''
    end
    table.sort(list, function(a, b)
      return a.degree > b.degree
    end)
    cb(true, list)
  end)
end

return M
