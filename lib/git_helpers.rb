require 'git_helpers/version'
require 'dr/base/bool'
require 'pathname'

module GitHelpers
	#git functions helper
	
	#small library wrapping git; use rugged for more interesting things
	class GitDir
		attr_accessor :dir
		def initialize(dir=".")
			@dir=Pathname.new(dir.to_s).realpath
		end

		def to_s
			@dir.to_s
		end

		#we could also use 'git -C #{@dir}' for each git invocation
		def with_dir
			Dir.chdir(@dir) { yield }
		end

		#are we in a git folder?
		def git?(quiet: false)
			launch="git rev-parse"
			launch=launch + " 2>/dev/null" if quiet
			with_dir do
				system launch
				return Bool.to_bool($?)
			end
		end

		#are we in .git/?
		def gitdir?
			with_dir do
				return Bool.to_bool(%x/git rev-parse --is-inside-git-dir/)
			end
		end
		#are we in the worktree?
		def worktree?
			with_dir do
				return Bool.to_bool(%x/git rev-parse --is-inside-work-tree/)
			end
		end
		#are we in a bare repo?
		def bare?
			with_dir do
				return Bool.to_bool(%x/git rev-parse --is-bare-repository/)
			end
		end
		
		#return the absolute path of the toplevel
		def toplevel
			with_dir do
				return Pathname.new(%x/git rev-parse --show-toplevel/.chomp)
			end
		end
		#relative path from toplevel to @dir
		def prefix
			with_dir do
				return Pathname.new(%x/git rev-parse --show-prefix/.chomp)
			end
		end
		#return the relative path from @dir to the toplevel
		def relative_toplevel
			with_dir do
				return Pathname.new(%x/git rev-parse --show-cdup/.chomp)
			end
		end
		#get path to .git directory (can be relative or absolute)
		def gitdir
			with_dir do
				return Pathname.new(%x/git rev-parse --git-dir/.chomp)
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
				return %x/git config #{args.shelljoin}/
			end
		end

		def current_branch(always: true)
			with_dir do
				branchname= %x/git symbolic-ref -q --short HEAD/.chomp!
				branchname||= %x/git rev-parse --verify HEAD/.chomp! if always
				return GitBranch.new(branchname, self)
			end
		end

		def head
			with_dir do
				return GitBranch.new('HEAD', self)
			end
		end

		#return all branches that have an upstream
		#if branches=:all look through all branches
		def all_upstream_branches(branches)
			#TODO
			upstreams=%x!git for-each-ref --format='%(upstream:short)' refs/heads/branch/!
		end

		def get_topic_branches(*branches, complete: :local)
			if branches.length >= 2
				return GitBranch.new(branches[0],self), GitBranch.new(branches[1],self)
			elsif branches.length == 1
				b=GitBranch.new(branches[0])
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
	end
	extend self
	GitDir.instance_methods(false).each do |m|
		define_method(m) do |*args,&b|
			GitDir.new.public_send(m,*args,&b)
		end
	end

	class GitBranch
		attr_accessor :gitdir
		attr_accessor :branch

		def initialize(branch="HEAD", dir=".")
			@gitdir=dir.is_a?(GitDir) ? dir : GitDir.new(dir)
			@branch=branch
		end

		def new_branch(name)
			self.class.new(name, @gitdir)
		end

		def to_s
			@branch.to_s
		end

		def nil?
			@branch.nil?
		end

		def shellescape
			@branch.shellescape
		end

		def name(method: "name", always: true)
			@gitdir.with_dir do
				case method
				when "sha1"
					describe=%x"git rev-parse --short #{@branch.shellescape}".chomp!
				when "describe"
					describe=%x"git describe #{@branch.shellescape}".chomp!
				when "contains"
					describe=%x"git describe --contains #{@branch.shellescape}".chomp!
				when "match"
					describe=%x"git describe --tags --exact-match #{@branch.shellescape}".chomp!
				when "topic"
					describe=%x"git describe --all #{@branch.shellescape}".chomp!
				when "branch"
					describe=%x"git describe --contains --all #{@branch.shellescape}".chomp!
				when "topic-fb" #try --all, then --contains all
					describe=%x"git describe --all #{@branch.shellescape}".chomp!
					describe=%x"git describe --contains --all #{@branch.shellescape}".chomp! if describe.nil? or describe.empty?
				when "branch-fb" #try --contains all, then --all
					describe=%x"git describe --contains --all #{@branch.shellescape}".chomp!
					describe=%x"git describe --all #{@branch.shellescape}".chomp! if describe.nil? or describe.empty?
				when "magic"
					describe1=%x"git describe --contains --all #{@branch.shellescape}".chomp!
					describe2=%x"git describe --all #{@branch.shellescape}".chomp!
					describe= describe1.length < describe2.length ? describe1 : describe2
					describe=describe1 if describe2.empty?
					describe=describe2 if describe1.empty?
				when "name"
					describe=%x"git rev-parse --abbrev-ref --symbolic-full-name #{@branch.shellescape}".chomp!
				else
					describe=%x/#{method}/.chomp! unless method.nil? or method.empty?
				end
				if (describe.nil? or describe.empty?) and always
					describe=%x/git rev-parse --short #{@branch.shellescape}/.chomp!
				end
				return describe
			end
		end

		def rebase?
			@gitdir.with_dir do
				rb=%x/git config --bool branch.#{@branch.shellescape}.rebase/.chomp!
				rb||=%x/git config --bool pull.rebase/.chomp!
				return rb=="true"
			end
		end

		def remote
			@gitdir.with_dir do
				rm=%x/git config --get branch.#{@branch.shellescape}.remote/.chomp!
				rm||="origin"
				return rm
			end
		end

		def upstream
			@gitdir.with_dir do
				up=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{u}/.chomp!
				return new_branch(up)
			end
		end
		def push
			@gitdir.with_dir do
				pu=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{push}/.chomp!
				return new_branch(pu)
			end
		end

		def hash
			@hash||=`git rev-parse #{@branch.shellescape}`.chomp!
		end

		def ==(other)
			@branch == other.branch && @gitdir=other.gitdir
		end

		#return upstream + push if push !=upstream
		def related
			up=upstream
			pu=push
			pu=new_branch(nil) if up==pu
			return up, pu
		end

	end

	def name_branch(branch,*args)
		GitBranch.new(branch).name(*args)
	end
end
