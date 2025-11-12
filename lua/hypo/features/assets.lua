local M = {}

local uv = vim.loop
local config = require('hypo.config')

local image_ext = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  svg = true,
  bmp = true,
}

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

local function assets_dir()
  local conf = config.get()
  local vault = conf.vault_path
  if not vault or vault == '' then
    return nil, nil, 'vault_path not configured'
  end
  local dir = (conf.assets and conf.assets.dir) or 'assets'
  local full = vim.fs.normalize(vim.fs.joinpath(vault, dir))
  vim.fn.mkdir(full, 'p')
  return full, dir
end

local function split_extension(name)
  local ext = name:match('%.([%w]+)$')
  local stem
  if ext then
    stem = name:sub(1, #name - #ext - 1)
  else
    stem = name
  end
  return stem, ext and ('.' .. ext) or ''
end

local function unique_name(dir, name)
  local stem, ext = split_extension(name)
  local candidate = name
  local counter = 1
  while uv.fs_stat(vim.fs.joinpath(dir, candidate)) do
    candidate = string.format('%s-%d%s', stem, counter, ext)
    counter = counter + 1
  end
  return candidate
end

local function format_name(name)
  local conf = config.get()
  local base = vim.fn.fnamemodify(name, ':t')
  if conf.assets and conf.assets.slugify then
    local stem, ext = split_extension(base)
    base = slugify(stem) .. ext
  end
  return base
end

local function list_assets(dir)
  local items = {}
  local function scan(path, base)
    for name, type in vim.fs.dir(path) do
      local full = vim.fs.joinpath(path, name)
      local rel = base and (base .. '/' .. name) or name
      if type == 'file' then
        table.insert(items, { path = full, rel = rel })
      elseif type == 'directory' then
        scan(full, rel)
      end
    end
  end
  local ok, err = pcall(scan, dir, nil)
  if not ok then
    vim.notify('Failed to scan assets: ' .. err, vim.log.levels.ERROR)
    return {}
  end
  table.sort(items, function(a, b)
    return a.rel:lower() < b.rel:lower()
  end)
  return items
end

local function insert_text(text)
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { text })
  vim.api.nvim_win_set_cursor(0, { row, col + #text })
end

local function insert_link(asset)
  local full_dir, rel_dir = assets_dir()
  if not full_dir then
    return
  end
  local rel = vim.fs.relpath(asset.path, full_dir) or asset.rel or vim.fn.fnamemodify(asset.path, ':t')
  local display_path = rel
  if rel_dir and rel_dir ~= '' then
    display_path = rel_dir .. '/' .. rel
  end
  local ext = display_path:match('%.([%w]+)$')
  local default_alt = vim.fn.fnamemodify(rel, ':t:r')
  local alt = vim.fn.input('Alt text (optional): ', default_alt)
  local link
  if ext and image_ext[ext:lower()] then
    link = string.format('![%s](%s)', alt or '', display_path)
  else
    local label = (alt and alt ~= '') and alt or rel
    link = string.format('[%s](%s)', label, display_path)
  end
  insert_text(link)
end

local function copy_or_move(src, dst, mode)
  if mode == 'copy' then
    local ok, err = uv.fs_copyfile(src, dst)
    if not ok then
      return false, err
    end
    return true
  elseif mode == 'move' then
    local ok, err = uv.fs_rename(src, dst)
    if ok then
      return true
    end
    return false, err
  end
  return false, 'unsupported mode'
end

local function ensure_within_assets(path)
  local dir = assets_dir()
  if not dir then
    return false
  end
  local normalized = vim.fs.normalize(path)
  local assets_root = dir
  return normalized:sub(1, #assets_root) == assets_root
end

function M.insert()
  local dir, rel_dir, err = assets_dir()
  if not dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local assets = list_assets(dir)
  local choices = {}
  for _, item in ipairs(assets) do
    table.insert(choices, { label = item.rel, path = item.path, rel = item.rel })
  end
  table.insert(choices, { label = '[Browse filesystem…]', browse = true })

  vim.ui.select(choices, {
    prompt = 'Select asset to insert',
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    local path
    if choice.browse then
      local picked = vim.fn.input('Asset path: ', '', 'file')
      if picked == '' then
        return
      end
      path = vim.fs.normalize(picked)
    else
      path = choice.path
    end

    local final_path = path
    local rel = choice.rel
    if not ensure_within_assets(path) then
      local action = vim.fn.confirm('Asset is outside the assets directory. Copy or move it in?', '&Copy\n&Move\n&Cancel', 1)
      if action == 0 or action == 3 then
        return
      end
      local mode = action == 1 and 'copy' or 'move'
      local formatted = format_name(path)
      local target_name = unique_name(dir, formatted)
      final_path = vim.fs.joinpath(dir, target_name)
      local ok_copy, copy_err = copy_or_move(path, final_path, mode)
      if not ok_copy then
        vim.notify('Failed to import asset: ' .. (copy_err or 'unknown error'), vim.log.levels.ERROR)
        return
      end
      rel = target_name
    end

    insert_link({ path = final_path, rel = rel or vim.fn.fnamemodify(final_path, ':t') })
    require('hypo.refresh').touch()
  end)
end

local paste_commands = {
  pngpaste = function(path, cb)
    vim.fn.jobstart({ 'pngpaste', path }, {
      on_exit = function(_, code)
        cb(code == 0, code)
      end,
    })
  end,
  ['wl-paste'] = function(path, cb)
    local cmd = string.format('wl-paste --type image/png > %s', vim.fn.shellescape(path))
    vim.fn.jobstart({ 'sh', '-c', cmd }, {
      on_exit = function(_, code)
        cb(code == 0, code)
      end,
    })
  end,
  xclip = function(path, cb)
    local cmd = string.format('xclip -selection clipboard -t image/png -o > %s', vim.fn.shellescape(path))
    vim.fn.jobstart({ 'sh', '-c', cmd }, {
      on_exit = function(_, code)
        cb(code == 0, code)
      end,
    })
  end,
}

local function detect_provider()
  local assets_conf = config.get().assets or {}
  local paste_conf = assets_conf.paste or {}
  if not paste_conf.enable then
    return nil, 'Clipboard paste is disabled (set assets.paste.enable = true)'
  end
  local provider = paste_conf.provider or 'auto'
  if provider == 'auto' then
    if vim.fn.executable('pngpaste') == 1 then
      provider = 'pngpaste'
    elseif vim.fn.executable('wl-paste') == 1 then
      provider = 'wl-paste'
    elseif vim.fn.executable('xclip') == 1 then
      provider = 'xclip'
    else
      return nil, 'No clipboard image provider found (pngpaste, wl-paste, or xclip)'
    end
  end
  if not paste_commands[provider] then
    return nil, 'Unsupported clipboard provider: ' .. provider
  end
  return provider
end

function M.paste()
  local dir, rel_dir, err = assets_dir()
  if not dir then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  local provider, perr = detect_provider()
  if not provider then
    vim.notify(perr, vim.log.levels.WARN)
    return
  end
  local filename = unique_name(dir, format_name('clipboard.png'))
  local target = vim.fs.joinpath(dir, filename)
  paste_commands[provider](target, function(ok)
    if not ok then
      vim.schedule(function()
        vim.notify('Failed to paste image from clipboard', vim.log.levels.ERROR)
      end)
      return
    end
    vim.schedule(function()
      insert_link({ path = target, rel = filename })
      require('hypo.refresh').touch()
    end)
  end)
end

return M
