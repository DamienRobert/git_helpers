require 'git_helpers/version'
require 'git_helpers/extra_helpers'
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

		def all_files
			with_dir do
				%x/git ls-files -z/.split("\0")
			end
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

		def branch_infos(*branches, local: false, remote: false, tags: false)
			query=branches.map {|b| name_branch(b, method: 'full_name')}
			query << 'refs/heads' if local
			query << 'refs/remotes' if remote
			query << 'refs/tags' if tags
			r={}
			format=%w(refname refname:short objecttype objectsize objectname upstream upstream:short upstream:track upstream:remotename upstream:remoteref push push:short push:remotename push:remoteref HEAD symref)
			out=SH::Run.run_simple("git for-each-ref --format '#{format.map {|f| "%(#{f})"}.join(',')}, ' #{query.shelljoin}", chomp: :lines)
			out.each do |l|
				infos=l.split(',')
				full_name=infos[0]
				r[full_name]=Hash[format.zip(infos)]
				type=if full_name.start_with?("refs/heads/")
							:local
						elsif full_name.start_with?("refs/remotes/")
							:remote
						elsif full_name.start_with?("refs/tags/")
							:tags
						end
				name = case type
						when :local
							full_name.delete_prefix("refs/heads/")
						when :remote
							full_name.delete_prefix("refs/remotes/")
						when :tags
							full_name.delete_prefix("refs/tags/")
						end
				r[full_name][:type]=type
				r[full_name][:name]=name
			end
			r
		end

		def name_branch(branch,*args)
			self.branch(branch).name(*args)
		end
	end

	extend self
	add_instance_methods = lambda do |klass|
		klass.instance_methods(false).each do |m|
			define_method(m) do |*args,&b|
				GitDir.new.public_send(m,*args,&b)
			end
		end
	end
	add_instance_methods.call(GitDir)
	add_instance_methods.call(GitStats)
	add_instance_methods.call(GitExtraInfos)

	class GitBranch
		attr_accessor :gitdir
		attr_accessor :branch
		attr_writer :infos

		def initialize(branch="HEAD", dir: ".")
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
		
		def infos
			return @infos if @infos
			infos=branch_infos
			type=infos[:type]
			if type == :local
				rebase=gitdir.get_config("branch.#{name}.rebase")
				rebase = false if rebase.empty?
				rebase = true if rebase == "true"
				infos[:rebase]=rebase
			end
			@infos=infos
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
				when "full_name"
					describe=%x"git rev-parse --symbolic-full-name #{@branch.shellescape}".chomp!
				when "symbolic"
					describe=%x"git rev-parse --symbolic #{@branch.shellescape}".chomp!
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

		def push_remote
			@gitdir.with_dir do
				rm= %x/git config --get branch.#{@branch.shellescape}.pushRemote/.chomp! || 
				%x/git config --get remote.pushDefault/.chomp! ||
				remote
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

		def branch_infos
			@gitdir.branch_infos(@branch).values.first
		end
	end

end
