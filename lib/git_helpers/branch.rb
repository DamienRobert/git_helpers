module GitHelpers
	GitBranchError = Class.new(Exception)
	class GitBranch
		attr_accessor :gitdir
		attr_accessor :branch
		attr_writer :infos

		def initialize(branch="HEAD", dir: ".")
			@gitdir=dir.is_a?(GitDir) ? dir : GitDir.new(dir)
			@branch=branch
		end

		def new_branch(name)
			self.class.new(name, dir: @gitdir)
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
			raise GitBranchError.new("Bad Branch #{self}") if infos.nil?
			type=infos[:type]
			if type == :local
				rebase=gitdir.get_config("branch.#{name}.rebase")
				rebase = false if rebase.empty?
				rebase = true if rebase == "true"
				infos[:rebase]=rebase
			end
			@infos=infos
		end

		def format_infos(**opts)
			@gitdir.format_branch_infos([infos], **opts)
		end

		def name(method: :default, always: true)
			method="name" if method == :default
			@gitdir.with_dir do
				case method
				when "sha1"
					describe=%x"git rev-parse --short #{@branch.shellescape}".chomp!
				when "describe"
					describe=%x"git describe #{@branch.shellescape}".chomp!
				when "contains"
					describe=%x"git describe --contains #{@branch.shellescape}".chomp!
				when "tags"
					describe=%x"git describe --tags #{@branch.shellescape}".chomp!
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
					describe=%x"git rev-parse --abbrev-ref #{@branch.shellescape}".chomp!
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
			infos[:rebase]
		end
		def remote
			infos["upstream:remotename"]
		end
		def push_remote
			infos["push:remotename"]
		end
		def upstream
			# up=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{u}/.chomp!
			new_branch(infos["upstream:short"])
		end
		def push
			# pu=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{push}/.chomp!
			new_branch(infos["push:short"])
		end
		def hash
			infos["objectname"]
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

		def ahead_behind(br)
			@gitdir.ahead_behind(@branch,br)
		end
	end
end
