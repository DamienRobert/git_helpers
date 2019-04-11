require 'git_helpers/stats'
require 'git_helpers/extra_helpers'
require 'git_helpers/branch_infos'
require 'git_helpers/status'

module GitHelpers
	class GitDir
		include GitStats
		include GitExtraInfos
		include GitBranchInfos
		include GitStatus

		attr_accessor :dir
		attr_writer :infos
		def initialize(dir=".")
			@dir=Pathname.new(dir.to_s).realpath
		end

		def infos(quiet: true)
			return @infos if @infos
			status, out, _err=SH.run("git rev-parse --is-inside-git-dir --is-inside-work-tree --is-bare-repository --show-prefix --show-toplevel --show-cdup --git-dir", chomp: :lines, quiet: quiet)
			@infos={}
			@infos[:git]=status.success?
			@infos[:in_gitdir]=DR::Bool.to_bool out[0]
			@infos[:in_worktree]=DR::Bool.to_bool out[1]
			@infos[:is_bare]=DR::Bool.to_bool out[2]
			@infos[:prefix]=out[3]
			@infos[:toplevel]=out[4]
			@infos[:cdup]=out[5]
			@infos[:gitdir]=out[6]
			@infos
		end

		#are we a git repo?
		def git?
			@infos[:git]
		end
		#are we in .git/?
		def gitdir?
			infos[:in_gitdir]
		end
		#are we in the worktree?
		def worktree?
			infos[:in_worktree]
		end
		#are we in a bare repo?
		def bare?
			infos[:is_bare]
		end
		#relative path from toplevel to @dir
		def prefix
			infos[:prefix]
		end
		#return the absolute path of the toplevel
		def toplevel
			infos[:toplevel]
		end
		#return the relative path from @dir to the toplevel
		def relative_toplevel
			infos[:cdup]
		end
		#get path to .git directory (can be relative or absolute)
		def gitdir
			infos[:gitdir]
		end

		def to_s
			@dir.to_s
		end

		#we could also use 'git -C #{@dir}' for each git invocation
		def with_dir
			Dir.chdir(@dir) { yield }
		end

		def all_files
			with_dir do
				%x/git ls-files -z/.split("\0")
			end
		end

		def with_toplevel(&b)
			with_dir do
				dir=relative_toplevel
				if !dir.to_s.empty?
					Dir.chdir(dir,&b)
				else
					warn "No toplevel found, executing inside dir #{@dir}"
					with_dir(&b)
				end
			end
		end

		#return a list of submodules
		def submodules
			with_dir do
				return %x/git submodule status/.each_line.map { |l| l.split[1] }
			end
		end

		def get_config(*args)
			with_dir do
				return %x/git config #{args.shelljoin}/.chomp
			end
		end

		def current_branch(always: true)
			with_dir do
				branchname= %x/git symbolic-ref -q --short HEAD/.chomp!
				branchname||= %x/git rev-parse --verify HEAD/.chomp! if always
				return branch(branchname)
			end
		end

		def head
			return branch('HEAD')
		end

		#return all branches that have an upstream
		#if branches=:all look through all branches
		def all_upstream_branches(branches)
			#TODO
			upstreams=%x!git for-each-ref --format='%(upstream:short)' refs/heads/branch/!
		end

		def push_default
			with_dir do
				return %x/git config --get remote.pushDefault/.chomp! || "origin"
			end
		end

		def get_topic_branches(*branches, complete: :local)
			if branches.length >= 2
				return branch(branches[0]), branch(branches[1])
			elsif branches.length == 1
				b=branch(branches[0])
				if complete == :local
					return current_branch, b
				elsif complete == :remote
					return b, b.upstream
				else
					fail "complete keyword should be :local or :remote"
				end
			else
				c=current_branch
				return c, c.upstream
			end
		end

		def branch(branch="HEAD")
			GitBranch.new(branch, dir: @self)
		end
	end
end
