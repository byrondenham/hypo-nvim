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

return M
