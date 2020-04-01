module GitHelpers
	module GitSubmodules
		def foreach(commited: true, modified: true, untracked: true, recursive: false, &b)
			r=[]
			st=status
			st[:paths].each do |k,v|
				sub=v[:submodule]
				if sub
					sub_commited=v[:sub_commited]
					sub_modified=v[:sub_modified]
					sub_untracked=v[:sub_untracked]
					if (commited && sub_commited or modified && sub_modified or untracked && sub_untracked)
						b.call(k, v) if b
						r << k
					end

					if recursive
						# Dir.chdir(k) do
						# 	rec=GitDir.new.foreach(commited: commited, modified: modified, untracked: untracked, recursive: true, &b)
						# 	r+=rec
						# end
						GitDir.clear_env do
						  GitDir.new(k).with_dir do |g|
							  rec=g.foreach(commited: commited, modified: modified, untracked: untracked, recursive: true, &b)
							  r+=rec.map {|sub| g.reldir+sub}
						  end
					  end
					end
				end
			end
			r
		end
	end
end
