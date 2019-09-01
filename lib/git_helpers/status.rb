module GitHelpers
	# status helper
	module GitStatus

		#get the stash commits
		def stash
			if run_success("git rev-parse --verify refs/stash", quiet: true)
				return run_simple("git rev-list -g refs/stash")
			else
				return nil
			end
		end

		def sequencer(extra_infos=true)
			read_helper=lambda do |file, ref: false; u|
				if file.readable?
					u=file.read.chomp
					u.sub!(/^refs\/heads\//,"") if ref
				end
				u
			end
			rb_helper=lambda do |dir; name, onto, rbname, extra|
				name=read_helper[gitdir+"#{dir}/head-name", ref: true]
				onto=read_helper[gitdir+"#{dir}/onto", ref: true]
				onto=branch(onto).name(highlight_detached: "") if onto
				rbname=""
				rbname << name if name
				rbname << "->#{onto}" if onto
				if dir == "rebase-merge"
					cur=read_helper[gitdir+"#{dir}/msgnum"]
					last=read_helper[gitdir+"#{dir}/end"]
				elsif dir == "rebase-merge"
					cur=read_helper[gitdir+"#{dir}/next"]
					last=read_helper[gitdir+"#{dir}/last"]
				end
				extra=[]; extra << rbname unless rbname.empty?;
				extra << "#{cur}/#{last}" if cur and last
				extra
			end
			r=[]; r_extra=[]
			append=lambda do |seq, extra=""|
				r << seq
				if extra_infos
					extra="" if extra.nil?
					if extra.is_a?(Array)
						extra=extra.join(":")
					end
					extra = extra.empty? ? "" : "(#{extra})"
					r_extra << "#{seq}#{extra}"
				end
			end
			rb_handler=lambda do |state, mode; extra|
				if mode == :rbi
					extra = rb_helper.call("rebase-merge") if extra_infos
				elsif mode==:am
					extra = rb_helper.call("rebase-apply") if extra_infos
				end
				append.call(state, extra)
			end

			gitdir=self.gitdir
			if bare?
				append.call 'bare'
			else
				append.call '.git' if gitdir?
			end
			if gitdir.to_s =~ /\/.git\/modules\//
				append.call 'sub'
			elsif gitdir.to_s =~ /\/.git\/worktrees\//
				append.call 'wt'
			end

			return r unless gitdir
			if (gitdir+"index.lock").file?
				append.call "ci" #commit in progress
			end
			if (gitdir+"rebase-merge").directory?
				state=
				if (gitdir+"rebase-merge/interactive").file?
					if (gitdir+"rebase-merge/rewritten").exist?
						"rb-im" #REBASE-im $ rebase -p -i
					else
						"rb-i" #REBASE-i
					end
				else
					"rb-m" #REBASE-m $ rebase -p
				end
				rb_handler.call(state, :rbi)
			end
			if (gitdir+"rebase-apply").directory?
				state = 
				if (gitdir+"rebase-apply/rebasing").file?
					"rb" #RB
				elsif (gitdir+"rebase-apply/applying").file?
					"am" #AM
				else
					"am/rb" #AM/REBASE (should not happen)
				end
				rb_handler.call(state, :am)
			end
			if (gitdir+"MERGE_HEAD").file?
				append.call "mg" #MERGING
			end
			if (gitdir+"CHERRY_PICK_HEAD").file?
				state= "ch" #CHERRY-PICKING
				name=read_helper[gitdir+"CHERRY_PICK_HEAD", ref: true]
				name=branch(name).name(highlight_detached: "") if name
				append.call state, name
			end
			if (gitdir+"REVERT_HEAD").file?
				state=rv #REVERTING
				name=read_helper[gitdir+"REVERT_HEAD", ref: true]
				name=branch(name).name(highlight_detached: "") if name
				append.call state, name
			end
			if (gitdir+"sequencer").directory?
				append.call "seq" #when we have a multiple commits cherry-pick or revert
				# TODO: read the 'todo' file to know if we are picking or reverting?
			end
			if (gitdir+"BISECT_LOG").file?
				state="bi" #BISECTING
				name=read_helper[gitdir+"BISECT_START", ref: true]
				append.call state, name
			end

			if extra_infos == :both
				return r, r_extra
			elsif extra_infos
				r_extra
			else
				r
			end
		end

		def status(br='HEAD', ignored: nil, untracked: nil, branch: :full, files: true, sequencer: true, stash: true, detached_name: :detached_infos, **_opts)
			l_branch={}
			l_branch=self.branch(br).infos(detached_name: detached_name) if branch == :full
			r={branch: l_branch}

			if worktree?
				paths={}
				l_untracked=[]
				l_ignored=[]
				r.merge!({paths: paths, files_untracked: l_untracked, files_ignored: l_ignored})

				staged=0
				staged_sub=0
				staged_nonsub=0
				changed=0
				changed_nonsub=0
				changed_sub=0
				subchanged=0
				subcommited=0
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
						when 'T'; r << :type_change
						end
					end
					infos[:index]=r[0]
					infos[:worktree]=r[1]

					sub=infos[:sub]
					if sub[0]=="N"
						infos[:submodule]=false
					else
						infos[:submodule]=true
						infos[:sub_commited]=sub[1]=="C"
						infos[:sub_modified]=sub[2]=="M"
						infos[:sub_untracked]=sub[3]=="U"
					end

					unless r[0]==:kept or r[0]==:unmerged
						staged +=1
						infos[:submodule] ? staged_sub +=1 : staged_nonsub +=1
					end

					unless r[1]==:kept or r[1]==:unmerged
						changed +=1
						if infos[:submodule]
							changed_sub +=1
							subchanged +=1 if (infos[:sub_modified]||infos[:sub_untracked])
							subcommited +=1 if infos[:sub_commited]
							changed_nonsub +=1 unless (infos[:sub_modified]||infos[:sub_untracked]||infos[:sub_commited]) #for D or T

						else
							changed_nonsub +=1
						end
					end
					conflicts+=1 if r[0]==:unmerged or r[1]==:unmerged

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

				if files
					call=%w(git status --porcelain=v2)
					status_options=[]
					status_options << "--branch" if branch and branch != :full
					status_options << "--untracked-files" if untracked
					status_options << "--untracked-files=no" if untracked==false
					status_options << "--ignored" if ignored
					status_options << "--ignored=no" if ignored==false
					r[:status_options]=status_options + (branch == :full ? ['--branch'] : [])
					out=run_simple((call+status_options).shelljoin, error: :quiet, chomp: :lines)
					out.each do |l|
						l.match(/# branch.oid\s+(.*)/) do |m|
							l_branch[:oid]=m[1]
						end
						l.match(/# branch.head\s+(.*)/) do |m|
							br_name=m[1]
							if br_name=="(detached)" and detached_name
								l_branch[:detached]=true
								br_name=self.name_branch(method: detached_name, always: true)
							else
							end
							l_branch[:name]=br_name
						end
						l.match(/# branch.upstream\s+(.*)/) do |m|
							l_branch[:upstream]=m[1]
						end
						l.match(/# branch.ab\s+\+(\d*)\s+-(\d*)/) do |m|
							l_branch[:upstream_ahead]=m[1].to_i
							l_branch[:upstream_behind]=m[2].to_i
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
					r[:staged_nonsub]=staged_nonsub
					r[:staged_sub]=staged_sub
					r[:changed]=changed
					r[:changed_nonsub]=changed_nonsub
					r[:changed_sub]=changed_sub
					r[:subchanged]=subchanged
					r[:subcommited]=subcommited
					r[:untracked]=l_untracked.length
					r[:ignored]=l_ignored.length
				end
			end

			if branch
				upstream=r.dig(:branch,'upstream')
				push=r.dig(:branch,'push')
				if upstream != push
					r[:push_ahead]=r.dig(:branch,:push_ahead)
					r[:push_behind]=r.dig(:branch,:push_behind)
				end
			end

			if stash
				r[:stash]=self.stash&.lines&.length
			end
			if sequencer
				seq, seq_full=self.sequencer(:both) 
				r[:sequencer]=seq
				r[:full_sequencer]=seq_full
			end
			return r
		end

		#changed_submodule: do we show changed submodule apart?
		def format_status(br='HEAD', status_infos=nil, changed_submodule: true, max_length: nil, **opts)
			if status_infos.nil?
				return "" unless git?
				status_infos=self.status(br, **opts)
			end
			yield status_infos if block_given?
			branch=status_infos.dig(:branch,:name) || ""
			ahead=status_infos.dig(:branch,:upstream_ahead)||0
			behind=status_infos.dig(:branch,:upstream_behind)||0
			push_ahead=status_infos[:push_ahead]||0
			push_behind=status_infos[:push_behind]||0
			# detached=status_infos.dig(:branch,:detached) || false
			allchanged=status_infos[:changed] ||0
			if changed_submodule
				changed=status_infos[:changed_nonsub] ||0
				subchanged=status_infos[:subchanged] ||0
				subcommited=status_infos[:subcommited] ||0
			else
				changed=status_infos[:changed] ||0
			end
			staged=status_infos[:staged] ||0
			conflicts=status_infos[:conflicts] ||0
			untracked=status_infos[:untracked] ||0
			ignored=status_infos[:ignored] || 0
			stash=status_infos[:stash]||0
			clean=true
			clean=false if staged != 0 || allchanged !=0 || untracked !=0 || conflicts !=0 || !worktree? || opts[:files]==false
			sequencer=status_infos[:sequencer] || []
			full_sequencer=status_infos[:full_sequencer] || []
			if stash != 0
				sequencer << "$#{stash}"
				full_sequencer << "$#{stash}"
			end

			# "#{detached ? ":" : ""} # the ':' prefix is done by name now
			left=
			"#{branch}".color(:magenta,:bold) <<
			(ahead==0 ? "" : "↑"<<ahead.to_s ) <<
			(behind==0 ? "" : "↓"<<behind.to_s ) <<
			(push_ahead==0 ? "" : "⇡"<<push_ahead.to_s) <<
			(push_behind==0 ? "" : "⇣"<<push_behind.to_s)

			files=
			(staged==0 ? "" : "●"+staged.to_s).color(:red)  <<
			(conflicts==0 ? "" : "✖"+conflicts.to_s).color(:red) <<
			(changed==0 ? "" : "✚"+changed.to_s).color(:blue)  <<
			(subcommited==0 ? "" : ("✦"+subcommited.to_s).color(:blue)) <<
			(subchanged==0 ? "" : ("✧"+subchanged.to_s).color(:blue)) <<
			(untracked==0 ? "" : "…" +
			 (opts[:untracked].to_s=="full" ? untracked.to_s : "")
			).color(:blue) <<
			(ignored==0 ? "" : "ꜟ" + #❗
			 (opts[:ignored].to_s=="full" ? ignored.to_s : "")
			).color(:blue) <<
			(clean ? "✔".color(:green,:bold) : "")

			extra=full_sequencer.join(" ").color(:yellow)

			length=lambda do
				left.uncolor.size+files.uncolor.size+extra.uncolor.size
			end
			shortened=false
			if max_length
				if length.call > max_length
					extra=sequencer.join(" ").color(:yellow)
				end
				if length.call > max_length
					shortened=true unless extra.empty?
					extra=""
				end
				if length.call > max_length
					shortened=true unless files.empty?
					files=""
				end
			end
			right=files
			unless extra.empty?
				right << " " unless right.empty?
				right << extra 
			end

			r="(" << left <<
				(right.empty? ? "" : "|" ) << right <<
				(shortened ? "⋯" : "") <<
				")"
			r
		end
	end
end
