module GitHelpers
	# status helper
	module GitStatus

		#get the stash commits
		def stash
			if run_success("git rev-parse --verify refs/stash")
				return run_simple("git rev-list -g refs/stash")
			else
				return nil
			end
		end

		def sequencer
			read_helper=lambda do |file, ref: false; u|
				if file.readable?
					u=file.read.chomp
					u.sub!(/^refs\/heads\//,"") if ref
				end
				u
			end
			gitdir=self.gitdir
			r=[]
			r << '.git' if gitdir?
			r << 'bare' if bare?

			return r unless gitdir
			if (gitdir+"rebase-merge").directory?
				if (gitdir+"rebase-merge/interactive").file?
					r<<"rb-i " #REBASE-i
				else
					r<<"rb-m " #REBASE-m
				end
				r<<read_helper[gitdir+"rebase-merge/head-name", ref: true]
				r<<read_helper[gitdir+"rebase-merge/msgnum"]
				r<<read_helper[gitdir+"rebase-merge/end"]
			end
			if (gitdir+"rebase-apply").directory?
				r<<read_helper[gitdir+"rebase-apply/next"]
				r<<read_helper[gitdir+"rebase-apply/last"]
				if (gitdir+"rebase-apply/rebasing").file?
					r<<read_helper[gitdir+"rebase-apply/head-name"]
					r<<"rb" #RB
				elsif (gitdir+"rebase-apply/applying").file?
					r<<"am" #AM
				else
					r<<"am/rb" #AM/REBASE
				end
			end
			if (gitdir+"MERGE_HEAD").file?
				r<<"mg" #MERGING
			end
			if (gitdir+"CHERRY_PICK_HEAD").file?
				r<<"ch" #CHERRY-PICKING
			end
			if (gitdir+"REVERT_HEAD").file?
				r<<"rv" #REVERTING
			end
			if (gitdir+"BISECT_LOG").file?
				r<<"bi" #BISECTING
			end
		end

		def status(ignored: nil, untracked: nil, branch: true, sequencer: true, stash: true, detached_name: 'branch-fb', **_opts)
			r={}
			if worktree?
				l_branch={}
				paths={}
				l_untracked=[]
				l_ignored=[]
				r.merge!({paths: paths, branch: l_branch, untracked: l_untracked, ignored: l_ignored})

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
				call="git status --porcelain=v2"
				call << " --branch" if branch
				call << " --untracked-files" if untracked
				call << " --untracked-files=no" if untracked==false
				call << " --ignored" if ignored
				call << " --ignored=no" if ignored==false
				out=run_simple(call, error: :quiet, chomp: :lines)
				out.each do |l|
					l.match(/# branch.oid\s+(.*)/) do |m|
						l_branch[:oid]=m[1]
					end
					l.match(/# branch.head\s+(.*)/) do |m|
						br_name=m[1]
						if br_name=="(detached)" and detached_name
							br_name=self.name_branch(method: detached_name, always: true)
						end
						l_branch[:head]=br_name
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
				r[:conflicts]=conflicts
				r[:staged]=staged
				r[:changed]=changed
				r[:untracked]=l_untracked.length
				r[:ignored]=l_ignored.length

			else
				branch_infos=head.infos(name: detached_name)
				branch_infos[:head]=branch_infos[:name]
				r[:branch]=branch_infos
			end

			if stash
				r[:stash]=self.stash&.lines&.length
			end
			r[:sequencer]=self.sequencer if sequencer
			return r
		end

		def format_status(status_infos=nil, **opts)
			if status_infos.nil?
				status_infos=self.status(**opts)
			end
			branch=status_infos.dig(:branch,:head) || ""
			ahead=status_infos.dig(:branch,:ahead)||0
			behind=status_infos.dig(:branch,:behind)||0
			changed=status_infos[:changed] ||0
			staged=status_infos[:staged] ||0
			conflicts=status_infos[:conflicts] ||0
			untracked=status_infos[:untracked] ||0
			stash=status_infos[:stash]||0
			clean=true
			clean=false if staged != 0 || changed !=0 || untracked !=0 || conflicts !=0 || !worktree?
			#ignored=status_infos[:ignored]
			sequencer=status_infos[:sequencer]&.join(" ") || ""
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
			(stash==0 ? "": " $#{stash}".color(:yellow)) <<
			")"
			r
		end
	end
end
