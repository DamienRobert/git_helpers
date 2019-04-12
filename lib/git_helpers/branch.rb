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

		def reset!
			@infos=nil
		end

		def run(*args, &b)
			@gitdir.run(*args, &b)
		end
		def run_simple(*args,&b)
			@gitdir.run_simple(*args, &b)
		end
		def run_success(*args,&b)
			@gitdir.run_success(*args, &b)
		end

		def infos(*args)
			return @infos if @infos
			@infos=infos!(*args)
		end

		def infos!(detached: true, name: :default)
			raise GitBranchError.new("Nil Branch #{self}") if nil?
			infos=branch_infos

			if infos.nil?
				if !detached #error out
					raise GitBranchError.new("Detached Branch #{self}")
				else
					infos={name: self.name(method: name) }
					return infos
				end
			end

			type=infos[:type]
			if type == :local
				rebase=gitdir.get_config("branch.#{name}.rebase")
				rebase = false if rebase.empty?
				rebase = true if rebase == "true"
				infos[:rebase]=rebase
			end
			infos
		end

		def format_infos(**opts)
			@gitdir.format_branch_infos([infos], **opts)
		end

		def name(method: :default, always: true)
			l=lambda { |ev| run_simple(ev, chomp: true, error: :quiet) }
			method="name" if method == :default
			describe=
				case method.to_s
				when "sha1"
					l.call "git rev-parse --short #{@branch.shellescape}"
				when "describe"
					l.call "git describe #{@branch.shellescape}"
				when "contains"
					l.call "git describe --contains #{@branch.shellescape}"
				when "tags"
					l.call "git describe --tags #{@branch.shellescape}"
				when "match"
					l.call "git describe --tags --exact-match #{@branch.shellescape}"
				when "topic"
					l.call "git describe --all #{@branch.shellescape}"
				when "branch"
					l.call "git describe --contains --all #{@branch.shellescape}"
				when "topic-fb" #try --all, then --contains all
					d=l.call "git describe --all #{@branch.shellescape}"
					d=l.call "git describe --contains --all #{@branch.shellescape}" if d.nil? or d.empty?
					d
				when "branch-fb" #try --contains all, then --all
					d=l.call "git describe --contains --all #{@branch.shellescape}"
					d=l.call "git describe --all #{@branch.shellescape}" if d.nil? or d.empty?
					d
				when "magic"
					d1=l.call "git describe --contains --all #{@branch.shellescape}"
					d2=l.call "git describe --all #{@branch.shellescape}"
					d= d1.length < d2.length ? d1 : d2
					d=d1 if d2.empty?
					d=d2 if d1.empty?
					d
				when "name"
					l.call "git rev-parse --abbrev-ref #{@branch.shellescape}"
				when "full_name"
					l.call "git rev-parse --symbolic-full-name #{@branch.shellescape}"
				when "symbolic"
					l.call "git rev-parse --symbolic #{@branch.shellescape}"
				else
					l.call method unless method.nil? or method.empty?
				end
			if (describe.nil? or describe.empty?) and always
				#this is the same fallback as `git describe --always`
				describe=l.call "git rev-parse --short #{@branch.shellescape}"
			end
			return describe
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
