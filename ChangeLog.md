== Release v0.2 (2020-02-18) ==

	* Bump version
	* Copyright
	* sumdate is now a standard git format proposal (cf the ml)
	* Small bugfixes
	* Fixes for ruby 2.7 warnings
	* branch_infos: better log options handling
	* branch_infos: show logs
	* branch_infos.rb: rework case @{u}=@{push}
	* format_branch_infos: show when @{push}=@{u}
	* branch: warn if upstream is nil
	* Add todo
	* status.rb: deleted or type change for submodules
	* rescue if the dir does not exist
	* Activate GIT_OPTIONAL_CLOCKS
	* submodule: recursive foreach
	* submodules foreach
	* status.rb: show when status is shortened
	* Update Rakefile
	* Update Rakefile
	* Bug fixes
	* status.rb: more infos in sequencer
	* status: max_length
	* gitstatus: sequencer formatting
	* status: extra infos optional in sequencer
	* name: can specify several methods
	* sequencer: show onto
	* detached_infos
	* Bug fixes
	* sequencer
	* branch#full_name
	* detached infos
	* branch_infos: cherry log
	* status: Show submodules commited vs submodules changed
	* infos: detached_name
	* status.rb: ignored symbol
	* Bug fix
	* gitstatus.rb: more options
	* status: full branch infos
	* status.rb: branch infos
	* gitstatus.rb options
	* Branch#checkout
	* recursive_upstream
	* status: add 'T' type (= type change)
	* diff-fancy.rb: integrate as library
	* Fix --prompt
	* Move gitstatus2.rb to gitstatus.rb
	* gitstatus2: more options
	* status: only show in a git repo
	* Sequencer status
	* status: minimal status when not in worktree
	* status when not in a worktree
	* More wrapping into run_simple
	* Use run helpers
	* git_helpers: reset cache and run wrappers
	* sequencer: read extra informations
	* branch: raw calls
	* git_dir: use rev-parse to get all infos at once
	* git_helpers.rb: split into multiple files
	* sequencer + stash infos
	* gitstatus2: bug fixes
	* New version of gitstatus.rb
	* git: status
	* git_helpers.rb: status
	* format_branch_infos
	* branch infos: upstream and push branch names

== Release v0.1.0 (2019-04-08) ==

	* branch infos
	* extra_helpers: now can handle a repository
	* extra_helpers: force --no-pager
	* Add extra branch and stats helpers
	* Bug fixes
	* Add #head
	* Import git_helpers from drain and improve the api
	* Desactivate pattern for now
	* diff-fancy: add default patterns to less
	* Last commit checked date
	* Readme + Commits checked
	* GitDiff.output as a convenience class method
	* Fix gemspec
	* Add git versions in Gemfile
	* Add .travis.yml
	* Update gemspec
	* Streamline rake and test files
	* Copyright
	* TODO--
	* Update README
	* gitstatus: check if folder exists
	* Also handle the case of a binary removal
	* Clean up 'binary file differ' in file creation
	* Set default column to 80 if `tput col` fails
	* scrub non utf-8 strings
	* Better detection of submoldules boundaries
	* diff-fancy: can specify diff-highlight location through an ENV variable
	* Add standalone executables
	* Copyright
	* Initial commit.

