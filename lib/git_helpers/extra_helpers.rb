# require 'dr/base/encoding'
# require 'git_helpers' #if we are required directly

module GitHelpers
	# various helpers
	module GitExtraInfos
		# Inspired by http://chneukirchen.org/dotfiles/bin/git-attic
		def removed_files(logopts=nil)
			removed={}
			commit=nil; date=nil
			run_simple(%Q/git log #{DefaultLogOptions} --raw --date=short --format="%h %cd" #{logopts}/, chomp: :lines).each do |l|
				l.chomp!
				case l
				when /^[0-9a-f]/
					commit, date=l.split(' ',2)
				when /^:/
					_old_mode, _new_mode, _old_hash, _new_hash, state, filename=l.split(' ',6)
					#keep earliest removal
					removed[filename]||={date: date, commit: commit} if state=="D"
				end
			end
			removed
		end
		def output_removed_files(logopts=nil)
			r=removed_files(logopts)
			r.each do |file, data|
				puts "#{data[:date]} #{data[:commit]}^:#{file}"
			end
		end

		#Inspired by https://gist.github.com/7590246.git
		def commit_children(*commits)
			r={}
			commits.each do |commit|
				commit_id=run_simple %Q/git rev-parse "#{commit}^0"/, chomp: true #dereference tags
				run_simple(%Q/git rev-list --all --not #{commit_id}^@ --children/, chomp: :lines).each do |l|
					if l=~/^#{commit_id}/
						_commit, *children=l.split
						described=children.map {|c| run_simple("git describe --always #{c}", chomp: true)}
						r[commit]||=[]
						r[commit]+=described
					end
				end
			end
			r
		end
		def output_commit_children(*commits)
			commit_children(*commits).each do |commit, children|
				puts "#{commit}: #{children.join(", ")}"
			end
		end

		#number of commits modifying each file (look in the logs)
		#Inspired by the script git-churn, written by Corey Haines # Scriptified by Gary Bernhardt
		def log_commits_by_files(logopts=nil)
			r={}
			files=run_simple("git log #{DefaultLogOptions} --name-only --format="" #{logopts}", chomp: :lines)
			uniq=files.uniq
			uniq.each do |file|
				r[file]=files.count(file)
			end
			r
		end
		def output_log_commits_by_files(logopts=nil)
			log_commits_by_files(logopts).sort {|f1, f2| -f1[1] <=> -f2[1]}.each do |file, count|
				puts "- #{file}: #{count}"
			end
		end

		#Inspired by the script git-effort from visionmedia
		def commits_by_files(*files)
			r={}
			files=all_files if files.empty?
			with_dir do
				files.each do |file|
					dates=%x/git log #{DefaultLogOptions} --pretty='format: %ad' --date=short -- "#{file}"/.each_line.map {|l| l.chomp}
					r[file]={commits: dates.length, active: dates.uniq.length}
				end
			end
			r
		end
		def output_commits_by_files(*files)
			commits_by_files(*files).each do |file, data|
				puts "- #{file}: #{data[:commits]} (active: #{data[:active]} days)"
			end
		end

			#git config --list
		#inspired by visionmedia//git-alias
		def aliases
			with_dir do
				%x/git config --get-regexp 'alias.*'/.each_line.map do |l|
					puts l.sub(/^alias\./,"").sub(/ /," = ")
				end
			end
		end

		#inspired by git-trail from https://github.com/cypher/dotfiles
		#merges: key=branch point hash, values=tips names
		def trails(commit, remotes: true, tags: true)
			merges={}
			with_dir do
				%x/git for-each-ref/.each_line do |l|
					hash, type, name=l.split
					next if type=="tags" and !tags
					next if type=="commit" && !name.start_with?("refs/heads/") and !remotes
					mb=`git merge-base #{commit.shellescape} #{hash}`.chomp
					mb=:disjoint if mb.empty?
					merges[mb]||=[]
					merges[mb] << name
				end
			end
			merges
		end

		def output_all_trails(*args, **opts)
			args.each do |commit|
				trails(commit, **opts).each do |mb, tips|
					next if mb==:disjoint
					with_dir do
						l=%x/git -c color.ui=always log -n1 --date=short --format="%C(auto,green)%cd %C(auto)%h" #{mb}/
						date, short_hash=l.split
						nr=tips.map do |tip|
							`git name-rev --name-only --refs=#{tip.shellescape} #{mb}`.chomp
						end
						puts "#{date}: #{short_hash} – #{nr.join(', ')}"
					end
				end
			end
		end

		#only output trails present in the log options passed
		def output_trails(*args, **opts)
			with_dir do
				commit=`git rev-parse --revs-only --default HEAD #{args.shelljoin}`.chomp
				merges=trails(commit, **opts)
				%x/git -c color.ui=always log --date=short --format="%C(auto,green)%cd %C(auto)%h%C(reset) %H" #{args.shelljoin}/.each_line do |l|
					date, short_hash, hash=l.split
					if merges.key?(hash)
						nr=merges[hash].map do |tip|
							`git name-rev --name-only --refs=#{tip.shellescape} #{hash}`.chomp
						end
						puts "#{date}: #{short_hash} – #{nr.join(', ')}"
					end
				end
			end
		end

		#inspired by git-neck from https://github.com/cypher/dotfiles
		def neck(*args, **opts)
			with_dir do
				commit=`git rev-parse --revs-only --default HEAD #{args.shelljoin}`.chomp
				log_opts=`git rev-parse --flags --no-revs #{args.shelljoin}`.chomp
				hash=`git rev-parse #{commit.shellescape}`.chomp
				merges=trails(commit, **opts)
				merges.delete(hash) #todo: only delete if we are the only tip
				merges.delete(:disjoint)
				system("git --no-pager -c color.ui=always log --pretty=suminfo #{log_opts} #{merges.keys.map {|mb| "^#{mb}"}.join(" ")} #{commit}")
				puts
			end
		end
	end
end
