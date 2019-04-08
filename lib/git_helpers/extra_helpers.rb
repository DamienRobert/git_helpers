require 'shellwords'
require 'dr/sh'
require 'dr/base/encoding'
# require 'git_helpers' #if we are required directly

module GitHelpers
	DefaultLogOptions=["-M", "-C", "--no-color"].shelljoin
	
	module GitStats
		#Note: stats-authors give the same result, should be faster, and handle mailcap
		#inspired by git-mainline//git-rank-contributors
		def stats_diff(logopts=nil)
			lines = {}

			with_dir do
				author = nil
				state = :pre_author
				DR::Encoding.fix_utf8(`git log #{DefaultLogOptions} -p #{logopts}`).each_line do |l|
					case
					when (state == :pre_author || state == :post_author) && m=l[/Author: (.*)$/,1]
						#TODO: using directly author=l[]... seems to only affect a block scoped author variable
						author=m
						state = :post_author
						lines[author] ||= {added: 0, deleted: 0, all: 0}
					when state == :post_author && l =~ /^\+\+\+\s/
						state = :in_diff
					when state == :in_diff && l =~ /^[\+\-]/
						unless l=~ /^(\+\+\+|\-\-\-)\s/
							lines[author][:all] += 1 
							lines[author][:added] += 1	if l[0]=="+"
							lines[author][:deleted] += 1 if l[0]=="-"
						end
					when state == :in_diff && l =~ /^commit /
						state = :pre_author
					end
				end
			end
			lines
		end

		def output_stats_diff(logopts=nil)
			lines=stats_diff(logopts)
			lines.sort_by { |a, c| -c[:all] }.each do |a, c|
				puts "#{a}: #{c[:all]} lines of diff (+#{c[:added]}/-#{c[:deleted]})"
			end
		end

		# inspired by visionmedia//git-line-summary
		def stats_lines(file)
			#p file
			with_dir do
				out,_suc=SH.run_simple("git", "blame", "--line-porcelain", file, quiet: true)
			end
			r={}
			begin
			out.each_line do |l|
					l.match(/^author (.*)/) do |m|
						r[m[1]]||=0
						r[m[1]]+=1
					end
				end
			rescue => e
				warn "Warning: #{e} on #{file}"
			end
			r
		end

		def stats_lines_all
			r={}
			all_files.select {|f| SH::Pathname.new(f).text? rescue false}.each do |f|
				stats_lines(f).each do |k,v|
					r[k]||=0
					r[k]+=v
				end
			end
			r
		end

		def output_stats_lines
			stats=stats_lines_all
			total=stats.values.sum
			stats.sort_by{|k,v| -v}.each do |k,v|
				puts "- #{k}: #{v} (#{"%2.1f%%" % (100*v/total.to_f)})"
			end
			puts "Total lines: #{total}"
		end

		#Inspired by https://github.com/esc/git-stats/blob/master/git-stats.sh
		def stats_authors(logopts=nil, more: false)
			require 'set'
			#Exemple: --after=..., --before=...,
			#  -w #word diff
			#  -C --find-copies-harder; -M
			authors={}
			with_dir do
				%x/git shortlog -sn #{logopts}/.each_line do |l|
					commits, author=l.chomp.split(' ', 2)
					authors[author]={commits: commits.to_i}
				end

				if more
					authors.each_key do |a|
						tot_a=0; tot_r=0; tot_rename=0; files=Set.new
						%x/git log #{DefaultLogOptions} #{logopts} --numstat --format="%n" --author='#{a}'/.each_line do |l|
							added, deleted, file=l.chomp.split(' ',3)
							#puts "#{l} => #{added}, #{deleted}, #{rest}"
							tot_a+=added.to_i; tot_r+=deleted.to_i
							next if file.nil?
							if file.include?(' => ')
								tot_rename+=1
							else
								files.add(file) unless file.empty?
							end
						end
						#rev-list should be faster, but I would need to use 
						# `git rev-parse --revs-only --default HEAD #{logopts.shelljoin}`
						# to be sure we default to HEAD, and 
						# `git rev-parse --flags #{logopts.shelljoin}` to get the log flags...
						#tot_merges=%x/git rev-list #{logopts} --merges --author='#{a}'/.each_line.count
						tot_merges=%x/git log --pretty=oneline #{logopts} --merges --author='#{a}'/.each_line.count
						authors[a].merge!({added: tot_a, deleted: tot_r, files: files.size, renames: tot_rename, merges: tot_merges})
					end
				end
			end
			authors
		end

		def output_stats_authors(logopts=nil)
			authors=stats_authors(logopts, more: true)
			authors.each do |a,v|
				puts "- #{a}: #{v[:commits]} commits (+#{v[:added]}/-#{v[:deleted]}), #{v[:files]} files modified, #{v[:renames]} renames, #{v[:merges]} merges"
			end
		end

		#inspired by visionmedia//git-infos
		def infos
			with_dir do
				puts "## Remote URLs:"
				puts
				system("git --no-pager remote -v")
				puts
				
				puts "## Remote Branches:"
				puts
				system("git --no-pager  branch -r")
				puts
				
				puts "## Local Branches:"
				puts
				system("git --no-pager  branch")
				puts
				
				puts "## Most Recent Commit:"
				puts
				system("git --no-pager log --max-count=1 --pretty=short")
				puts
			end
		end

		#inspired by visionmedia//git-summary
		def summary(logopts=nil)
			with_dir do
				project=Pathname.new(%x/git rev-parse --show-toplevel/).basename
				authors=stats_authors(logopts)
				commits=authors.map {|a,v| v[:commits]}.sum
				file_count=%x/git ls-files/.each_line.count
				active_days=%x/git log --date=short --pretty='format: %ad' #{logopts}/.each_line.uniq.count
				#This only give the rep age of the current branch; and is not
				#efficient since we generate the first log
				#A better way would be to get all the roots commits via
				#    git rev-list --max-parents=0 HEAD
				#and then look at their ages
				repository_age=%x/git log --reverse --pretty=oneline --format="%ar" #{logopts}/.each_line.first.sub!('ago','')
				#total= %x/git rev-list #{logopts}/.each_line.count
				total=%x/git rev-list --count #{logopts.empty? ? "HEAD" : logopts.shelljoin}/.to_i

				puts " project  : #{project}"
				puts " repo age : #{repository_age}"
				puts " active   : #{active_days} days"
				puts " commits  : #{commits}"
				puts " files    : #{file_count}"
				puts " authors  : #{authors.keys.join(", ")} (Total: #{total})"
				authors.each do |a,v|
					puts " - #{a}: #{v[:commits]} (#{"%2.1f" % (100*v[:commits]/commits.to_f)}%)"
				end
			end
		end
	end

	# various helpers
	module GitExtraInfos
		# Inspired by http://chneukirchen.org/dotfiles/bin/git-attic
		def removed_files(logopts=nil)
			removed={}
			with_dir do
				commit=nil; date=nil
				%x/git log #{DefaultLogOptions} --raw --date=short --format="%h %cd" #{logopts}/.each_line do |l|
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
			with_dir do
				commits.each do |commit|
					commit_id=%x/git rev-parse "#{commit}^0"/.chomp #dereference tags
					%x/git rev-list --all --not #{commit_id}^@ --children/.each_line do |l|
						if l=~/^#{commit_id}/
							_commit, *children=l.chomp.split
							described=children.map {|c| %x/git describe --always #{c}/.chomp}
							r[commit]||=[]
							r[commit]+=described
						end
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
			with_dir do
				files=%x/git log #{DefaultLogOptions} --name-only --format="" #{logopts}/.each_line.map {|l| l.chomp!}
				uniq=files.uniq
				uniq.each do |file|
					r[file]=files.count(file)
				end
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
				system("git --no-pager -c color.ui=always log --pretty=summary #{log_opts} #{merges.keys.map {|mb| "^#{mb}"}.join(" ")} #{commit}")
				puts
			end
		end
	end

	class GitDir
		include GitStats
		include GitExtraInfos
	end
end
