if vim.fn.has("nvim-0.7.0") == 0 then
	vim.api.nvim_err_writeln("Notes requires at least nvim-0.7.0.+")
	return
end

-- prevent loading file twice
if vim.g.loaded_notes == 1 then
	return
end
vim.g.loaded_notes = 1

vim.api.nvim_create_user_command("NewNote", function()
	require("notes").new_note()
end, {})

vim.api.nvim_create_user_command("ListNotes", function()
	require("notes").list_notes()
end, {})

vim.api.nvim_create_user_command("FindNoteByKeyword", function()
	require("notes").find_by_keyword()
end, {})

vim.api.nvim_create_user_command("NotePasteImage", function()
	require("notes").paste_image()
end, {})
