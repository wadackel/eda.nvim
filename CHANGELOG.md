# Changelog

## [1.8.0](https://github.com/wadackel/eda.nvim/compare/v1.7.0...v1.8.0) (2026-09-05)


### Features

* preview inside replace-mode explorer windows ([#106](https://github.com/wadackel/eda.nvim/issues/106)) ([85e2edf](https://github.com/wadackel/eda.nvim/commit/85e2edff0054b725769c39707d527c13aaef73cf))


### Bug Fixes

* dispose watcher and preview debounce timers ([#86](https://github.com/wadackel/eda.nvim/issues/86)) ([ea61eaa](https://github.com/wadackel/eda.nvim/commit/ea61eaa6bf3a7a91d7ea658cde28e79c94d61086))
* honor the large directory warning threshold ([#95](https://github.com/wadackel/eda.nvim/issues/95)) ([d092b5f](https://github.com/wadackel/eda.nvim/commit/d092b5fdaca3e480c2e80b7a36a281766e6233a7))
* invalidate stale preview requests across lifecycles ([#87](https://github.com/wadackel/eda.nvim/issues/87)) ([2acbcd3](https://github.com/wadackel/eda.nvim/commit/2acbcd36c91bbd8b3eb78ad9a5ebead6878456f6))
* keep preview toggle state per explorer ([#104](https://github.com/wadackel/eda.nvim/issues/104)) ([6fce45e](https://github.com/wadackel/eda.nvim/commit/6fce45e47e45afa76e244c731d715ceb5c89be10))
* parse Git status with NUL-delimited paths ([#85](https://github.com/wadackel/eda.nvim/issues/85)) ([fca74d3](https://github.com/wadackel/eda.nvim/commit/fca74d382c3cb726a91126d3c58e7a42e1cde084))
* preserve files when system trash is unavailable ([#84](https://github.com/wadackel/eda.nvim/issues/84)) ([8cb9c39](https://github.com/wadackel/eda.nvim/commit/8cb9c3924a56ca33506d76fe61a3f59aec847341))
* preserve unsaved edits during automatic refresh ([#81](https://github.com/wadackel/eda.nvim/issues/81)) ([0d06782](https://github.com/wadackel/eda.nvim/commit/0d06782c83934ace001332bf1e399b6c6e108f3c)), closes [#59](https://github.com/wadackel/eda.nvim/issues/59)
* reconcile watched directory changes without replacing the tree ([#89](https://github.com/wadackel/eda.nvim/issues/89)) ([7406556](https://github.com/wadackel/eda.nvim/commit/7406556f6c2df18b7e6330737f7e0ae616ad33da))
* reject occupied file creation destinations ([#79](https://github.com/wadackel/eda.nvim/issues/79)) ([9757146](https://github.com/wadackel/eda.nvim/commit/97571463fcac8145cbf2ea775e0f85e74c52c2ce))
* reserve unique batch paste destinations ([#83](https://github.com/wadackel/eda.nvim/issues/83)) ([3156378](https://github.com/wadackel/eda.nvim/commit/3156378356627ea30312f66783bb72216d390edf))
* unify mutation results and event delivery ([#88](https://github.com/wadackel/eda.nvim/issues/88)) ([198c264](https://github.com/wadackel/eda.nvim/commit/198c26462754d1c85d78803488aa12ef636073c4))
* validate buffer mutation batches and preserve partial writes ([#82](https://github.com/wadackel/eda.nvim/issues/82)) ([2e32fd7](https://github.com/wadackel/eda.nvim/commit/2e32fd7fbe19b62dea788f521bc85f6a4945029f)), closes [#57](https://github.com/wadackel/eda.nvim/issues/57)
* verify filesystem outcomes and preserve symlink targets ([#101](https://github.com/wadackel/eda.nvim/issues/101)) ([cb34298](https://github.com/wadackel/eda.nvim/commit/cb342987e5cbeb36b826fbb75e3529bd83200e21)), closes [#76](https://github.com/wadackel/eda.nvim/issues/76)


### Performance Improvements

* coordinate Git status requests per repository ([#94](https://github.com/wadackel/eda.nvim/issues/94)) ([6045cb4](https://github.com/wadackel/eda.nvim/commit/6045cb4d3b0a39c5812a7149985a6cfcd3e52f47))
* limit incremental icon updates and redraw resync ([#91](https://github.com/wadackel/eda.nvim/issues/91)) ([ac08bff](https://github.com/wadackel/eda.nvim/commit/ac08bff1b24d850a9339cb784dab8f4f3ad6cd26))
* resolve symlink metadata with bounded async work ([#93](https://github.com/wadackel/eda.nvim/issues/93)) ([d48272a](https://github.com/wadackel/eda.nvim/commit/d48272a36265e3b60c2f78c3504f0181ba3f7317))
* reuse the capture within dirty directory collapse ([#92](https://github.com/wadackel/eda.nvim/issues/92)) ([fad6cc9](https://github.com/wadackel/eda.nvim/commit/fad6cc97845f8ea413b932e230065de4eee9fb45))

## [1.7.0](https://github.com/wadackel/eda.nvim/compare/v1.6.0...v1.7.0) (2026-09-04)


### Features

* image preview via the Kitty graphics protocol ([#50](https://github.com/wadackel/eda.nvim/issues/50)) ([be53ab4](https://github.com/wadackel/eda.nvim/commit/be53ab4d19f8cfcabe82570faa976dd62dca31af))
* **image:** transmit previews by file path, animate loading, size conversions to the pane ([#54](https://github.com/wadackel/eda.nvim/issues/54)) ([e49161a](https://github.com/wadackel/eda.nvim/commit/e49161a079e72528609c580c3cce212551f4872e))


### Bug Fixes

* **image:** allow tmux passthrough from hidden panes so images are removed ([#53](https://github.com/wadackel/eda.nvim/issues/53)) ([b76eb16](https://github.com/wadackel/eda.nvim/commit/b76eb1639d662d1d3f141af837f70bafb3b603c0))
* **image:** detect an SSH client attached to a local tmux server ([#55](https://github.com/wadackel/eda.nvim/issues/55)) ([fded724](https://github.com/wadackel/eda.nvim/commit/fded724894256859bb57123e116652e96dcbb912))
* **image:** send both cell axes and a source crop so large images stay inside the preview ([#52](https://github.com/wadackel/eda.nvim/issues/52)) ([afa1b15](https://github.com/wadackel/eda.nvim/commit/afa1b15f732d15f7709aa81c10f2087b9188eda4))

## [1.6.0](https://github.com/wadackel/eda.nvim/compare/v1.5.0...v1.6.0) (2026-05-28)


### Features

* add open_in_browser action for GitHub/GHE ([#44](https://github.com/wadackel/eda.nvim/issues/44)) ([a2330b8](https://github.com/wadackel/eda.nvim/commit/a2330b8690eea05e1cb31239847939c6d1498c6b))


### Bug Fixes

* **dir_size:** use monotonic clock for cache TTL ([#45](https://github.com/wadackel/eda.nvim/issues/45)) ([6d73fc7](https://github.com/wadackel/eda.nvim/commit/6d73fc7a3c806f9530e8f3bcf4c2ece6f7166d94))

## [1.5.0](https://github.com/wadackel/eda.nvim/compare/v1.4.0...v1.5.0) (2026-05-17)


### Features

* add yank_tree action to copy selected nodes as ASCII tree ([#37](https://github.com/wadackel/eda.nvim/issues/37)) ([3746cbf](https://github.com/wadackel/eda.nvim/commit/3746cbfe5054c3126de5bf0ddd596891c71de496))

## [1.4.0](https://github.com/wadackel/eda.nvim/compare/v1.3.0...v1.4.0) (2026-05-13)


### Features

* center viewport on float explorer reopen ([#35](https://github.com/wadackel/eda.nvim/issues/35)) ([935bd0f](https://github.com/wadackel/eda.nvim/commit/935bd0f24fdc8d5a6fe964291f92ea6a04dedee5))

## [1.3.0](https://github.com/wadackel/eda.nvim/compare/v1.2.0...v1.3.0) (2026-05-10)


### Features

* reopen float explorer in replace mode ([#33](https://github.com/wadackel/eda.nvim/issues/33)) ([f59b9f5](https://github.com/wadackel/eda.nvim/commit/f59b9f55217a4055840071908310b1aa6c616e2e))

## [1.2.0](https://github.com/wadackel/eda.nvim/compare/v1.1.0...v1.2.0) (2026-04-25)


### Features

* directory preview with eda tree rendering ([#26](https://github.com/wadackel/eda.nvim/issues/26)) ([7bfaa06](https://github.com/wadackel/eda.nvim/commit/7bfaa06e2c19efdfb378dcfeba55c8a093fe5205))


### Bug Fixes

* disable swapfile on eda buffer to prevent E325/E95 conflict ([#28](https://github.com/wadackel/eda.nvim/issues/28)) ([9c7f2d0](https://github.com/wadackel/eda.nvim/commit/9c7f2d0fff692db78c0f35796a625a77acb27806))
* **e2e:** stabilize flaky tests with deterministic observation helpers ([#30](https://github.com/wadackel/eda.nvim/issues/30)) ([c246914](https://github.com/wadackel/eda.nvim/commit/c2469148af1e38d0eb19b0064107295c599e94b4))

## [1.1.0](https://github.com/wadackel/eda.nvim/compare/v1.0.0...v1.1.0) (2026-04-25)


### Features

* preserve directory open state across root changes ([#24](https://github.com/wadackel/eda.nvim/issues/24)) ([b41952b](https://github.com/wadackel/eda.nvim/commit/b41952b31f64e0d6eb030b6cc82bd46106dbcdb4))

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
