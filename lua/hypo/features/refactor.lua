local M = {}

local uv = vim.loop
local config = require('hypo.config')

local function backend_type()
  return config.get_backend_type()
end

local function run_cli(args, input, cb)
  local cli = require('hypo.adapters.cli')
  cli.run(args, input, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr ~= '' and stderr or stdout)
      return
    end
    cb(true, stdout)
  end)
end

local function slugify(text)
  local slug = (text or ''):lower()
  slug = slug:gsub('[^%w%s%-_]', ' ')
  slug = slug:gsub('%s+', '-')
  slug = slug:gsub('%-+', '-')
  slug = slug:gsub('^%-+', '')
  slug = slug:gsub('%-+$', '')
  if slug == '' then
    slug = tostring(os.date('%Y%m%d%H%M%S'))
  end
  return slug
end

local function get_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row = start_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_row = end_pos[2] - 1
  local end_col = end_pos[3]
  if start_row > end_row then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end
  local text = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
  return {
    bufnr = bufnr,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
    lines = text,
  }
end

local function first_non_empty_line(lines)
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= '' then
      return trimmed
    end
  end
  return nil
end

local function ensure_cli()
  if backend_type() ~= 'cli' then
    vim.notify('This refactor requires the hypo CLI backend', vim.log.levels.WARN)
    return false
  end
  return true
end

local function write_lines(path, lines)
  local dir = vim.fs.dirname(path)
  if dir and dir ~= '' then
    vim.fn.mkdir(dir, 'p')
  end
  local ok, err = pcall(vim.fn.writefile, lines, path)
  if not ok then
    return false, err
  end
  return true
end

local function parse_new_note(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout or '{}')
  if ok and type(decoded) == 'table' then
    local id = decoded.id or decoded.note_id or decoded.slug
    local path = decoded.path or decoded.file or decoded.location
    return id, path
  end
  local id = stdout and stdout:match('%S+')
  return id, nil
end

local function create_note(title, cb)
  run_cli({ 'new', '--title', title, '--json' }, nil, function(ok, stdout)
    if not ok then
      cb(false, stdout)
      return
    end
    local id, path = parse_new_note(stdout)
    if not id then
      cb(false, 'Failed to determine created note id')
      return
    end
    if not path then
      path = vim.fs.joinpath(config.get().vault_path or '', id .. '.md')
    end
    cb(true, { id = id, path = path })
  end)
end

local function replace_selection(sel, text)
  vim.api.nvim_buf_set_text(sel.bufnr, sel.start_row, sel.start_col, sel.end_row, sel.end_col, { text })
end

local function label_at_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  if not line then
    return nil
  end
  local cursor = col + 1
  local found = nil
  local escaped
  for start_idx, label, finish_idx in line:gmatch('()%^([%w_%-%]+)()') do
    local end_idx = finish_idx - 1
    if cursor >= start_idx and cursor <= end_idx then
      found = label
      escaped = vim.pesc(label)
      break
    end
  end
  if not found then
    return nil
  end
  return { label = found, pattern = escaped }
end

local function rename_label_in_buffer(old_label, new_label)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local escaped = vim.pesc(old_label)
  local replacement = '^' .. new_label
  local changed = false
  for idx, line in ipairs(lines) do
    local new_line = line
    new_line = new_line:gsub('%^' .. escaped .. '(%W)', replacement .. '%1')
    new_line = new_line:gsub('%^' .. escaped .. '$', replacement)
    if new_line ~= line then
      lines[idx] = new_line
      changed = true
    end
  end
  if changed then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    if vim.bo[bufnr].modifiable then
      pcall(vim.cmd, 'silent keepalt write')
    end
    vim.notify('Renamed label to ^' .. new_label, vim.log.levels.INFO)
  else
    vim.notify('No occurrences of ^' .. old_label .. ' found in buffer', vim.log.levels.WARN)
  end
end

function M.rename_label()
  local found = label_at_cursor()
  if not found then
    vim.notify('Cursor is not on a ^label', vim.log.levels.WARN)
    return
  end
  local new_label = vim.fn.input('New label: ', found.label)
  if not new_label or new_label == '' then
    return
  end
  if not new_label:match('^[%w][%w_%-%]*$') then
    vim.notify('Label must start with an alphanumeric character and contain only [-_A-Za-z0-9]', vim.log.levels.ERROR)
    return
  end
  rename_label_in_buffer(found.label, new_label)
end

local function perform_extract(opts)
  if not ensure_cli() then
    return
  end
  local sel = get_selection()
  if not sel or #sel.lines == 0 then
    vim.notify('No selection to extract', vim.log.levels.WARN)
    return
  end
  local default_title = first_non_empty_line(sel.lines) or 'New note'
  local title = vim.fn.input('New note title: ', default_title)
  if not title or title == '' then
    return
  end
  local label_value = nil
  if opts and opts.transclude then
    label_value = opts.label or slugify(title)
  end
  create_note(title, function(ok, result)
    if not ok then
      vim.notify('Failed to create note: ' .. result, vim.log.levels.ERROR)
      return
    end
    local path = result.path or vim.fs.joinpath(config.get().vault_path or '', result.id .. '.md')
    local lines = vim.deepcopy(sel.lines)
    if label_value then
      table.insert(lines, 1, '^' .. label_value)
    end
    local ok_write, err = write_lines(path, lines)
    if not ok_write then
      vim.notify('Failed to write new note: ' .. err, vim.log.levels.ERROR)
      return
    end
    local indent = vim.api.nvim_buf_get_lines(sel.bufnr, sel.start_row, sel.start_row + 1, false)[1]
    indent = indent and indent:match('^%s*') or ''
    local replacement
    if opts and opts.transclude then
      replacement = indent .. '![[%s#^%s]]'
      replacement = string.format(replacement, result.id, label_value)
    else
      replacement = indent .. '[[%s|%s]]'
      replacement = string.format(replacement, result.id, title)
    end
    vim.schedule(function()
      replace_selection(sel, replacement)
      if vim.bo[sel.bufnr].modifiable then
        pcall(vim.cmd, 'silent keepalt write')
      end
      require('hypo.refresh').touch()
    end)
  end)
end

function M.extract_note()
  perform_extract()
end

function M.extract_transclude()
  perform_extract({ transclude = true })
end

function M.normalize_buffer()
  if not ensure_cli() then
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  if not path or path == '' then
    vim.notify('Current buffer has no file on disk', vim.log.levels.WARN)
    return
  end
  local stat_before = uv.fs_stat(path)
  run_cli({ 'fmt', '--links', '--ids-only', '--write', path }, nil, function(ok, out)
    if not ok then
      vim.notify('hypo fmt failed: ' .. out, vim.log.levels.ERROR)
      return
    end
    local stat_after = uv.fs_stat(path)
    if stat_before and stat_after then
      local changed = stat_after.mtime.sec ~= stat_before.mtime.sec or stat_after.mtime.nsec ~= stat_before.mtime.nsec
      if changed then
        vim.schedule(function()
          vim.cmd('edit!')
        end)
      end
    else
      vim.schedule(function()
        vim.cmd('edit!')
      end)
    end
    require('hypo.refresh').touch()
  end)
end

return M
