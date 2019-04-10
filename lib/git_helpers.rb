require 'git_helpers/version'
require 'git_helpers/extra_helpers'
require 'dr/base/bool'
require 'simplecolor'
require 'pathname'

SimpleColor.mix_in_string

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

		def ahead_behind(br1, br2)
			with_dir do
				out=SH::Run.run_simple("git rev-list --left-right --count #{br1.shellescape}...#{br2.shellescape}", error: :quiet)
				out.match(/(\d+)\s+(\d+)/) do |m|
					return m[1].to_i, m[2].to_i #br1 is ahead by m[1], behind by m[2] from br2
				end
				return 0, 0
			end
		end

		def branch_infos(*branches, local: false, remote: false, tags: false, merged: nil, no_merged: nil)
			query = []
			query << "--merged=#{merged.shellescape}" if merged
			query << "--no_merged=#{no_merged.shellescape}" if no_merged
			query += branches.map {|b| name_branch(b, method: 'full_name')}
			query << 'refs/heads' if local
			query << 'refs/remotes' if remote
			query << 'refs/tags' if tags
			r={}
			format=%w(refname refname:short objecttype objectsize objectname upstream upstream:short upstream:track upstream:remotename upstream:remoteref push push:short push:track push:remotename push:remoteref HEAD symref)
			#Note push:remoteref is buggy (always empty)
			#and push:track is upstream:track
			out=SH::Run.run_simple("git for-each-ref --format '#{format.map {|f| "%(#{f})"}.join(';')}, ' #{query.shelljoin}", chomp: :lines)
			out.each do |l|
				infos=l.split(';')
				full_name=infos[0]
				infos=Hash[format.zip(infos)]

				infos[:head]=!infos["HEAD"].empty?

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
				infos[:type]=type
				infos[:name]=name

				infos[:upstream_ahead]=0
				infos[:upstream_behind]=0
				infos[:push_ahead]=0
				infos[:push_behind]=0
				track=infos["upstream:track"]
				track.match(/ahead (\d+)/) do |m|
					infos[:upstream_ahead]=m[1].to_i
				end
				track.match(/behind (\d+)/) do |m|
					infos[:upstream_behind]=m[1].to_i
				end

				## git has a bug for push:track
				# ptrack=infos["push:track"]
				# ptrack.match(/ahead (\d+)/) do |m|
				# 	infos[:push_ahead]=m[1].to_i
				# end
				# ptrack.match(/behind (\d+)/) do |m|
				# 	infos[:push_behind]=m[1].to_i
				# end
				unless infos["push"].empty?
					ahead, behind=ahead_behind(infos["refname"], infos["push"])
					infos[:push_ahead]=ahead
					infos[:push_behind]=behind
				end

				origin = infos["upstream:remotename"]
				unless origin.empty?
					upstream_short=infos["upstream:short"]
					infos["upstream:name"]=upstream_short.delete_prefix(origin+"/")
				end
				pushorigin = infos["push:remotename"]
				unless pushorigin.empty?
					push_short=infos["push:short"]
					if push_short.empty?
						infos["push:name"]=infos["refname:short"]
					else
						infos["push:name"]= push_short.delete_prefix(pushorigin+"/")
					end
				end

				r[full_name]=infos
			end
			r
		end

		def format_branch_infos(infos, compare: nil, merged: nil)
			# warning, here we pass the info values, ie infos should be a list
			infos.each do |i|
				name=i["refname:short"]
				upstream=i["upstream:short"]
				color=:magenta
				if merged
					color=:red #not merged
					[*merged].each do |br|
						ahead, behind=ahead_behind(i["refname"], br)
						if ahead==0
							color=:magenta
							break
						end
					end
				end
				r="#{i["HEAD"]}#{name.color(color)}"
				if compare
					ahead, behind=ahead_behind(i["refname"], compare)
					r << "↑#{ahead}" unless ahead==0
					r << "↓#{behind}" unless behind==0
				end
				unless upstream.empty?
					r << "  @{u}=#{upstream.color(:yellow)}"
					r << "↑#{i[:upstream_ahead]}" unless i[:upstream_ahead]==0
					r << "↓#{i[:upstream_behind]}" unless i[:upstream_behind]==0
				end
				push=i["push:short"]
				unless push.empty?
					r << "  @{push}=#{push.color(:yellow)}"
					r << "↑#{i[:push_ahead]}" unless i[:push_ahead]==0
					r << "↓#{i[:push_behind]}" unless i[:push_behind]==0
				end
				puts r
			end
		end

		def name_branch(branch='HEAD',**args)
			self.branch(branch).name(**args)
		end

		def status(ignored: nil, untracked: nil, branch: true)
			l_branch={}
			paths={}
			l_untracked=[]
			l_ignored=[]
			r={paths: paths, branch: l_branch, untracked: l_untracked, ignored: l_ignored}

			staged=0
			changed=0
			conflicts=0

			complete_infos=lambda do |infos; r|
				r=[]
				infos[:xy].each_char do |c|
					case c
					when '.'; r << :kept
					when 'M'; r << :updated
					when 'A'; r << :added
					when 'D'; r << :deleted
					when 'R'; r << :renamed
					when 'C'; r << :copied
					when 'U'; r << :unmerged
					end
				end
				infos[:index]=r[0]
				staged +=1 unless r[0]==:kept or r[0]==:unmerged
				infos[:worktree]=r[1]
				changed +=1 unless r[1]==:kept or r[0]==:unmerged
				conflicts+=1 if r[0]==:unmerged or r[1]==:unmerged

				sub=infos[:sub]
				if sub[0]=="N"
					infos[:submodule]=false
				else
					infos[:submodule]=true
					infos[:sub_commited]=sub[1]=="C"
					infos[:sub_modified]=sub[2]=="M"
					infos[:sub_untracked]=sub[3]=="U"
				end

				if (xscore=infos[:xscore])
					if xscore[0]=="R"
						infos[:rename]=true
					elsif xscore[0]=="C"
						infos[:copy]=true
					end
					infos[:score]=xscore[1..-1].to_i
				end

				infos
			end
			with_dir do
				call="git status --porcelain=v2"
				call << " --branch" if branch
				call << " --untracked-files" if untracked
				call << " --untracked-files=no" if untracked==false
				call << " --ignored" if ignored
				call << " --ignored=no" if ignored==false
				out=SH::Run.run_simple(call, error: :quiet, chomp: :lines)
				out.each do |l|
					l.match(/# branch.oid\s+(.*)/) do |m|
						l_branch[:oid]=m[1]
					end
					l.match(/# branch.head\s+(.*)/) do |m|
						l_branch[:head]=m[1]
					end
					l.match(/# branch.upstream\s+(.*)/) do |m|
						l_branch[:upstream]=m[1]
					end
					l.match(/# branch.ab\s+\+(\d*)\s+-(\d*)/) do |m|
						l_branch[:ahead]=m[1].to_i
						l_branch[:behind]=m[2].to_i
					end

					l.match(/1 (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (.*)/) do |m|
						xy=m[1]; sub=m[2]; #modified data, submodule information
						mH=m[3]; mI=m[4]; mW=m[5]; #file modes
						hH=m[6]; hI=m[7]; #hash
						path=m[8]
						info={xy: xy, sub: sub, mH: mH, mI: mI, mW: mW, hH: hH, hI: hI}
						paths[path]=complete_infos.call(info)
					end

					#rename copy
					l.match(/2 (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (.*)\t(.*)/) do |m|
						xy=m[1]; sub=m[2]; mH=m[3]; mI=m[4]; mW=m[5];
						hH=m[6]; hI=m[7]; xscore=m[8]
						path=m[9]; orig_path=m[10]
						info={xy: xy, sub: sub, mH: mH, mI: mI, mW: mW, hH: hH, hI: hI,
						xscore: xscore, orig_path: orig_path}
						paths[path]=complete_infos.call(info)
					end

					# unmerged
					l.match(/u (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (\S*) (.*)/) do |m|
						xy=m[1]; sub=m[2]; #modified data, submodule information
						m1=m[3]; m2=m[4]; m3=m[5]; mW=m[6] #file modes
						h1=m[7]; h2=m[8]; h3=m[9] #hash
						path=m[10]
						info={xy: xy, sub: sub, m1: m1, m2: m2, m3: m3, mW: mW, h1: h1, h2: h2, h3: h3}
						paths[path]=complete_infos.call(info)
					end

					l.match(/\? (.*)/) do |m|
						l_untracked << m[1]
					end
					l.match(/! (.*)/) do |m|
						l_ignored << m[1]
					end
				end
			end
			r[:conflicts]=conflicts
			r[:staged]=staged
			r[:changed]=changed
			r[:untracked]=l_untracked.length
			r[:ignored]=l_ignored.length
			return r
		end

		def format_status(status_infos)
			branch=status_infos.dig(:branch,:head)
			ahead=status_infos.dig(:branch,:ahead)||0
			behind=status_infos.dig(:branch,:behind)||0
			changed=status_infos[:changed]
			staged=status_infos[:staged]
			conflicts=status_infos[:conflicts]
			untracked=status_infos[:untracked]
			clean=true
			clean=false if staged != 0 || changed !=0 || untracked !=0 || conflicts !=0
			#ignored=status_infos[:ignored]
			sequencer="" #todo
			r="(" <<
			branch.color(:magenta,:bold) <<
			(ahead==0 ? "" : "↑"<<ahead.to_s ) <<
			(behind==0 ? "" : "↓"<<behind.to_s ) <<
			"|" <<
			(staged==0 ? "" : ("●"+staged.to_s).color(:red) ) <<
			(conflicts==0 ? "" : ("✖"+conflicts.to_s).color(:red) ) <<
			(changed==0 ? "" : ("✚"+changed.to_s).color(:blue) ) <<
			(untracked==0 ? "" : "…" ) <<
			(clean ? "✔".color(:green,:bold) : "" ) <<
			(sequencer.empty? ? "" : sequencer.color(:yellow) ) <<
			")"
			r
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

		def ahead_behind(br)
			@gitdir.ahead_behind(@branch,br)
		end
	end

end
