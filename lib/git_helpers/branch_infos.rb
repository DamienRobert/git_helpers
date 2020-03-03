module GitHelpers
	# more infos on branches
	module GitBranchInfos
		def ahead_behind(br1, br2)
			with_dir do
				out=run_simple("git rev-list --left-right --count #{br1.shellescape}...#{br2.shellescape}", error: :quiet)
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
			query += branches.map {|b| name_branch(b)}
			query << 'refs/heads' if local
			query << 'refs/remotes' if remote
			query << 'refs/tags' if tags
			r={}
			format=%w(refname refname:short objecttype objectsize objectname upstream upstream:short upstream:track upstream:remotename upstream:remoteref push push:short push:track push:remotename push:remoteref HEAD symref)
			#Note push:remoteref is buggy (empty if no push refspec specified)
			#and push:track is upstream:track (cf my patch to the git mailing
			#list to correct that)
			out=run_simple("git for-each-ref --format '#{format.map {|f| "%(#{f})"}.join(';')}' #{query.shelljoin}", chomp: :lines)
			out.each do |l|
				infos=l.split(';')
				full_name=infos[0]
				infos=Hash[format.zip(infos)]

				infos[:name]=infos["refname:short"]
				infos[:head]=!(infos["HEAD"]&.empty? or infos["HEAD"]==" ")

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
				track&.match(/ahead (\d+)/) do |m|
					infos[:upstream_ahead]=m[1].to_i
				end
				track&.match(/behind (\d+)/) do |m|
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
				unless infos["push"]&.empty?
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

		def format_branch_infos(infos, compare: nil, merged: nil, cherry: false, log: false)
			# warning, here we pass the info values, ie infos should be a list
			infos.each do |i|
				name=i["refname:short"]
				upstream=i["upstream:short"]
				push=i["push:short"]
				color=:magenta
				if merged
					color=:red #not merged
					[*merged].each do |br|
						ahead, _behind=ahead_behind(i["refname"], br)
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
					r <<  "  @{u}"
					r << "=@{push}" if push==upstream
					r << "=#{upstream.color(:yellow)}"
					r << "↑#{i[:upstream_ahead]}" unless i[:upstream_ahead]==0
					r << "↓#{i[:upstream_behind]}" unless i[:upstream_behind]==0
				end
				unless push.empty? or push == upstream
					r << "  @{push}=#{push.color(:yellow)}"
					r << "↑#{i[:push_ahead]}" unless i[:push_ahead]==0
					r << "↓#{i[:push_behind]}" unless i[:push_behind]==0
				end
				if log
					log_options=case log
					when Hash
						log.map {|k,v| "--#{k}=#{v.shellescape}"}.join(' ')
					when String
						log
					else
						""
					end
					r << " → "+run_simple("git -c color.ui=always log --date=human --oneline --no-walk #{log_options} #{name}")
				end
				puts r
				if cherry #todo: add push cherry?
					if upstream and i[:upstream_ahead] != 0 || i[:upstream_behind] != 0
						ch=run_simple("git -c color.ui=always log --left-right --topo-order --oneline #{name}...#{upstream}")
						ch.each_line do |l|
							puts "   #{l}"
						end
					end
				end
			end
		end

		def name_branch(branch='HEAD',**args)
			self.branch(branch).full_name(**args)
		end
		def name(branch='HEAD',**args)
			self.branch(branch).name(**args)
		end

		#return all local upstreams of branches, recursively
		def recursive_upstream(*branches, local: true)
			require 'tsort'
			each_node=lambda do |&b| branches.each(&b) end
			each_child=lambda do |br, &b|
				upstream=branch(br).upstream(short: false)
				upstreams=[]
				upstreams << upstream.to_s unless upstream.nil? or local && upstream.to_s.start_with?("refs/remotes/")
				upstreams.each(&b)
			end
			TSort.tsort(each_node, each_child)
		end
	end
end
