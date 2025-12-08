-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>cr", function()
  local file = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t:r")
  local dir = vim.fn.expand("%:p:h")

  vim.cmd("write")

  local cmd = string.format(
    "cd '%s'; g++ '%s' -o '%s.exe'; if ($?) { & '.\\%s.exe' }",
    dir,
    file,
    filename,
    filename
  )

  require("toggleterm.terminal").Terminal:new({
    cmd = cmd,
    direction = "horizontal",
    close_on_exit = false,
  }):toggle()
end, { desc = "Compile and Run C++" })
