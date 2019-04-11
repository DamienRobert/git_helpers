
module GitHelpers
	#these raw helpers are not called since we usually use higher level
	#commands that provide all infos at once
	class GitDir
		#are we in a git folder?
		def raw_git?(quiet: false)
			launch="git rev-parse"
			launch=launch + " 2>/dev/null" if quiet
			with_dir do
				system launch
				return DR::Bool.to_bool($?)
			end
		end

		#are we in .git/?
		def raw_gitdir?
			with_dir do
				return DR::Bool.to_bool(%x/git rev-parse --is-inside-git-dir/)
			end
		end
		#are we in the worktree?
		def raw_worktree?
			with_dir do
				return DR::Bool.to_bool(%x/git rev-parse --is-inside-work-tree/)
			end
		end
		#are we in a bare repo?
		def raw_bare?
			with_dir do
				return DR::Bool.to_bool(%x/git rev-parse --is-bare-repository/)
			end
		end
		
		#return the absolute path of the toplevel
		def raw_toplevel
			with_dir do
				return Pathname.new(%x/git rev-parse --show-toplevel/.chomp)
			end
		end
		#relative path from toplevel to @dir
		def raw_prefix
			with_dir do
				return Pathname.new(%x/git rev-parse --show-prefix/.chomp)
			end
		end
		#return the relative path from @dir to the toplevel
		def raw_relative_toplevel
			with_dir do
				return Pathname.new(%x/git rev-parse --show-cdup/.chomp)
			end
		end
		#get path to .git directory (can be relative or absolute)
		def raw_gitdir
			with_dir do
				return Pathname.new(%x/git rev-parse --git-dir/.chomp)
			end
		end
	end

	class GitBranch
		def raw_rebase?
			@gitdir.with_dir do
				rb=%x/git config --bool branch.#{@branch.shellescape}.rebase/.chomp!
				rb||=%x/git config --bool pull.rebase/.chomp!
				return rb=="true"
			end
		end

		def raw_remote
			@gitdir.with_dir do
				rm=%x/git config --get branch.#{@branch.shellescape}.remote/.chomp!
				rm||="origin"
				return rm
			end
		end

		def raw_push_remote
			@gitdir.with_dir do
				rm= %x/git config --get branch.#{@branch.shellescape}.pushRemote/.chomp! || 
				%x/git config --get remote.pushDefault/.chomp! ||
				remote
				return rm
			end
		end

		def raw_upstream
			@gitdir.with_dir do
				up=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{u}/.chomp!
				return new_branch(up)
			end
		end

		def raw_push
			@gitdir.with_dir do
				pu=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{push}/.chomp!
				return new_branch(pu)
			end
		end

		def raw_hash
			@hash||=`git rev-parse #{@branch.shellescape}`.chomp!
		end
	end
end
