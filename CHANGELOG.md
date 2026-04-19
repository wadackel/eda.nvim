# Changelog

## 1.0.0 (2026-04-19)


### Features

* add mark_clear_all action and visual mode mark_toggle ([#19](https://github.com/wadackel/eda.nvim/issues/19)) ([c183ab3](https://github.com/wadackel/eda.nvim/commit/c183ab3f2a269d85347ab084e8ae50245e904a8e))
* add quickfix action for marked files ([#18](https://github.com/wadackel/eda.nvim/issues/18)) ([a0629f8](https://github.com/wadackel/eda.nvim/commit/a0629f8e117c639e35548bcdbbf8276bac4de389))
* add sticky cursor-anchored inspect float ([#20](https://github.com/wadackel/eda.nvim/issues/20)) ([47462e4](https://github.com/wadackel/eda.nvim/commit/47462e4726c84c0e262277f2d3ed590a7b48ca17))
* add visual indicator for marked nodes ([#11](https://github.com/wadackel/eda.nvim/issues/11)) ([3a6ee9d](https://github.com/wadackel/eda.nvim/commit/3a6ee9d6e1a33e413fc02f96158a3648e8671512))
* async directory size calculation in inspect float ([#21](https://github.com/wadackel/eda.nvim/issues/21)) ([0d7cab8](https://github.com/wadackel/eda.nvim/commit/0d7cab87132dceb55fd4e2990f2bb7b6ef7841a1))
* change default mark icon to nf-md-checkbox_marked ([#12](https://github.com/wadackel/eda.nvim/issues/12)) ([eb8fe77](https://github.com/wadackel/eda.nvim/commit/eb8fe77c815715e53cae49a767653a0b465766cc))
* disable buffer editing in empty state when git filter is active ([#8](https://github.com/wadackel/eda.nvim/issues/8)) ([2e9cfbf](https://github.com/wadackel/eda.nvim/commit/2e9cfbf2271b50fdb1c4cd0d0776f84030bf2949))
* initial implement ([2d4110d](https://github.com/wadackel/eda.nvim/commit/2d4110dc7f9c2d6e38e847103da5dbeec78e3fd7))
* refresh git status after file operations for real-time indicators ([#9](https://github.com/wadackel/eda.nvim/issues/9)) ([2b7007e](https://github.com/wadackel/eda.nvim/commit/2b7007efb7de6e43ce92f035c2b3084c2165ff0a))
* split EdaMarkedNode into Icon/Name and fix linked name_hl in arrays ([#15](https://github.com/wadackel/eda.nvim/issues/15)) ([2d1d83e](https://github.com/wadackel/eda.nvim/commit/2d1d83eab1c2027b813cc3b542a071d74365c546))
* unify mark-aware file operations (cut/copy/delete/duplicate) ([#14](https://github.com/wadackel/eda.nvim/issues/14)) ([1fbfaaa](https://github.com/wadackel/eda.nvim/commit/1fbfaaa76640463b1e47b0ff573268caf7438db7))


### Bug Fixes

* defer action dispatch until initial render completes ([#22](https://github.com/wadackel/eda.nvim/issues/22)) ([6e47144](https://github.com/wadackel/eda.nvim/commit/6e47144260b9381eb20604a27b17a3ff3a378986))
* mark highlight wins priority over symlink ([#16](https://github.com/wadackel/eda.nvim/issues/16)) ([4aef650](https://github.com/wadackel/eda.nvim/commit/4aef65046f252b7fea76201db321f42aefb89410))
* preserve user attributes on EdaMarkedNode and re-apply on :colorscheme ([#13](https://github.com/wadackel/eda.nvim/issues/13)) ([b0962a1](https://github.com/wadackel/eda.nvim/commit/b0962a1eaed7e3d283d75ba154fc77c44aad49e8))

## Changelog
