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

		def run(*args,**kw, &b)
			@gitdir.run(*args,**kw, &b)
		end
		def run_simple(*args,**kw,&b)
			@gitdir.run_simple(*args,**kw, &b)
		end
		def run_success(*args,**kw,&b)
			@gitdir.run_success(*args,**kw, &b)
		end

		def checkout
			branch=@branch
			branch&.delete_prefix!('refs/heads/') #git checkout refs/heads/master check out in a detached head
			SH.sh! "git checkout #{branch}"
		end
		def checkout_detached
			SH.sh! "git checkout #{@branch}~0"
		end

		def infos(*args, name: :default, detached_name: :detached_default)
			@infos=infos!(*args) unless @infos
			@infos.merge({name: self.name(method: name, detached_method: detached_name)})
		end

		def infos!(detached: true)
			raise GitBranchError.new("Nil Branch #{self}") if nil?
			infos=branch_infos

			if infos.nil?
				if !detached #error out
					raise GitBranchError.new("Detached Branch #{self}")
				else
					infos={detached: true}
					return infos
				end
			end

			type=infos[:type]
			infos[:detached]=false
			if type == :local
				rebase=gitdir.get_config("branch.#{infos["refname:short"]}.rebase")
				rebase = false if rebase.empty?
				rebase = true if rebase == "true"
				infos[:rebase]=rebase
			end
			infos
		end

		def format_infos(**opts)
			@gitdir.format_branch_infos([infos], **opts)
		end

		def name(method: :default, detached_method: [:detached_default, :short], shorten: true, highlight_detached: ':', expand_head: true)
			l=lambda { |ev| run_simple(ev, chomp: true, error: :quiet) }
			methods=[*method]
			detached_methods=[*detached_method]
			method=methods.shift
			if method.nil? 
				if !detached_methods.empty?
					describe=self.name(method: detached_methods, detached_method: [], shorten: shorten, highlight_detached: highlight_detached, expand_head: expand_head)
					describe="#{highlight_detached}#{describe}" unless describe.nil? or describe.empty?
					return describe
				else
					return nil
				end
			end
			method="name" if method == :default
			#method="branch-fb" if method == :detached_default
			#method="short" if method == :detached_default
			method="match" if method == :detached_default
			method="branch-fb" if method == :detached_infos
			describe=
				case method.to_s
				when "sha1"
					l.call "git rev-parse #{@branch.shellescape}"
				when "short"
					l.call "git rev-parse --short #{@branch.shellescape}"
				when "symbolic-ref"
					l.call "git symbolic-ref -q --short #{@branch.shellescape}"
				when "describe"
					l.call "git describe #{@branch.shellescape}"
				when "contains"
					l.call "git describe --contains #{@branch.shellescape}"
				when "tags"
					l.call "git describe --tags #{@branch.shellescape}"
				when "match"
					l.call "git describe --all --exact-match #{@branch.shellescape}"
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
				when Proc
					method.call(@branch)
				else
					l.call method unless method.nil? or method.empty?
				end
			if describe.nil? or describe.empty? or describe == "HEAD" && expand_head
				describe=self.name(method: methods, detached_method: detached_method, shorten: shorten, highlight_detached: highlight_detached, expand_head: expand_head)
			end
			if shorten
				describe&.delete_prefix!("refs/")
				describe&.delete_prefix!("heads/")
			end
			return describe
		end

		def full_name(method: :full_name, detached_method: nil, shorten: false, **opts)
			name(method: method, detached_method: detached_method, shorten: shorten, **opts)
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
		def upstream(short: true, warn: true)
			# up=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{u}/.chomp!
			br= short ? infos["upstream:short"] : infos["upstream"]
			if br&.empty?
				br=nil
				warn "Warning: Branch #{self} has no upstream" if warn
			end
			new_branch(br)
		end
		def push(short: true)
			# pu=%x/git rev-parse --abbrev-ref #{@branch.shellescape}@{push}/.chomp!
			br= short ? infos["push:short"] : infos["push"]
			br=nil if br.empty?
			new_branch(br)
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
			@gitdir.branch_infos(branch).values.first
		end

		def ahead_behind(br)
			@gitdir.ahead_behind(@branch,br)
		end
	end
end
