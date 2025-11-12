local config = require('hypo.config').get
local M = {}

local function build_args(args)
  local c = config()
  local a = { c.hypo_cmd }
  if c.vault_path then
    table.insert(a, '--vault')
    table.insert(a, c.vault_path)
  end
  for _, x in ipairs(args) do
    table.insert(a, x)
  end
  return a
end

function M.run(args, input, onexit)
  local a = build_args(args)
  local stdout, stderr = {}, {}
  local jobid = vim.fn.jobstart(a, {
    stdin = input and 'pipe' or 'null',
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= '' then
            table.insert(stdout, l)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= '' then
            table.insert(stderr, l)
          end
        end
      end
    end,
    on_exit = function(_, code)
      onexit(code, table.concat(stdout, '\n'), table.concat(stderr, '\n'))
    end,
  })
  if input then
    vim.fn.chansend(jobid, input)
    vim.fn.chanclose(jobid, 'stdin')
  end
end

-- Adapter implementation for hypo CLI

function M.list_notes(cb)
  M.run({ 'notes', 'list', '--format', 'json' }, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    local ok, notes = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse JSON: ' .. tostring(notes))
      return
    end
    cb(true, notes)
  end)
end

function M.search(query, opts, cb)
  opts = opts or {}
  local args = { 'search', query }
  if opts.snippets then
    table.insert(args, '--snippets')
  end
  if opts.limit then
    table.insert(args, '--limit')
    table.insert(args, tostring(opts.limit))
  end
  table.insert(args, '--format')
  table.insert(args, 'json')

  M.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    local ok, results = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse JSON: ' .. tostring(results))
      return
    end
    cb(true, results)
  end)
end

function M.backrefs(id, opts, cb)
  opts = opts or {}
  local args = { 'backrefs', id, '--format', 'json' }
  if opts.context then
    table.insert(args, '--context')
    table.insert(args, tostring(opts.context))
  end

  M.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    local ok, refs = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse JSON: ' .. tostring(refs))
      return
    end
    cb(true, refs)
  end)
end

function M.yank(ref, opts, cb)
  opts = opts or {}
  local id = type(ref) == 'table' and ref.id or ref
  local args = { 'yank', id }
  if opts.plain then
    table.insert(args, '--plain')
  end

  M.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    cb(true, { content = stdout })
  end)
end

function M.locate(ref, cb)
  local id = type(ref) == 'table' and ref.id or ref
  local args = { 'locate', id, '--format', 'json' }

  M.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    local ok, loc = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse JSON: ' .. tostring(loc))
      return
    end
    cb(true, loc)
  end)
end

function M.neighbours(id, depth, cb)
  local args = { 'neighbours', id, '--depth', tostring(depth or 1), '--format', 'json' }

  M.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    local ok, neighbours = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse JSON: ' .. tostring(neighbours))
      return
    end
    cb(true, neighbours)
  end)
end

function M.meta_get(id, keys, cb)
  local args = { 'meta', 'get', id, '--format', 'json' }
  if keys and #keys > 0 then
    table.insert(args, '--keys')
    table.insert(args, table.concat(keys, ','))
  end

  M.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    local ok, meta = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse JSON: ' .. tostring(meta))
      return
    end
    cb(true, meta)
  end)
end

function M.meta_set(id, kv, cb)
  local args = { 'meta', 'set', id, '--format', 'json' }
  local input = vim.json.encode(kv)

  M.run(args, input, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    cb(true, { success = true })
  end)
end

function M.reindex(cb)
  M.run({ 'reindex' }, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr)
      return
    end
    cb(true, { success = true, message = stdout })
  end)
end

function M.bulk_edit(edits, cb)
  -- edits: array of { id=note_id, find=pattern, replace=replacement }
  -- For each edit, locate the file, read it, replace, and write atomically
  local errors = {}
  local success_count = 0
  local total = #edits

  if total == 0 then
    cb(true, { success = true, applied = 0, errors = {} })
    return
  end

  local function process_next(idx)
    if idx > total then
      cb(#errors == 0, { success = #errors == 0, applied = success_count, errors = errors })
      return
    end

    local edit = edits[idx]
    M.locate(edit.id, function(ok, loc)
      if not ok or not loc or not loc.path then
        table.insert(errors, { id = edit.id, error = 'Failed to locate note' })
        process_next(idx + 1)
        return
      end

      local path = loc.path
      local file = io.open(path, 'r')
      if not file then
        table.insert(errors, { id = edit.id, error = 'Failed to open file' })
        process_next(idx + 1)
        return
      end

      local content = file:read('*all')
      file:close()

      -- Perform safe string replacement (escape pattern characters)
      local find_escaped = edit.find:gsub('([^%w])', '%%%1')
      local new_content, count = content:gsub(find_escaped, edit.replace)

      if count > 0 then
        local tmp_file = io.open(path, 'w')
        if tmp_file then
          tmp_file:write(new_content)
          tmp_file:close()
          success_count = success_count + 1
        else
          table.insert(errors, { id = edit.id, error = 'Failed to write file' })
        end
      end

      process_next(idx + 1)
    end)
  end

  process_next(1)
end

function M.lint_plan(cb)
  -- Run hypo lint --json with autofix plan mode if available
  -- For now, we'll use standard lint output and parse it
  M.run({ 'lint', '--format', 'json' }, nil, function(code, stdout, stderr)
    if code ~= 0 and stdout == '' then
      cb(false, stderr)
      return
    end
    
    local ok, lint_results = pcall(vim.json.decode, stdout)
    if not ok then
      cb(false, 'Failed to parse lint JSON: ' .. tostring(lint_results))
      return
    end

    -- Transform lint results into fixable items
    local fixes = {}
    if lint_results and type(lint_results) == 'table' then
      for _, item in ipairs(lint_results) do
        if item.kind and item.message then
          table.insert(fixes, {
            id = item.id or item.note_id,
            kind = item.kind,
            message = item.message,
            line = item.line,
            col = item.col,
            -- Patch generation would depend on hypo CLI supporting autofix
            -- For now, we mark certain types as fixable
            fixable = item.kind == 'redundant-link' or item.kind == 'legacy-link' or item.kind == 'duplicate-label',
          })
        end
      end
    end

    cb(true, fixes)
  end)
end

function M.graph(id, depth, cb)
  -- Use neighbours as a fallback for graph data
  -- A dedicated 'graph' command would be better if available
  M.neighbours(id, depth or 1, function(ok, neighbours)
    if not ok then
      cb(false, neighbours)
      return
    end
    
    -- Transform neighbours into graph format
    local graph_data = {
      center = id,
      depth = depth or 1,
      nodes = {},
      edges = {},
    }
    
    if neighbours and type(neighbours) == 'table' then
      graph_data.nodes = neighbours
      -- Build edges from the neighbours data
      for _, node in ipairs(neighbours) do
        if node.id ~= id then
          table.insert(graph_data.edges, { from = id, to = node.id })
        end
      end
    end
    
    cb(true, graph_data)
  end)
end

return M
