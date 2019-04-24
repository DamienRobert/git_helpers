module GitHelpers
	module GitSubmodules
		def foreach(commited: true, modified: true, untracked: true, recursive: true)
			r=[]
			st=status
			st[:paths].each do |k,v|
				sub=v[:submodule]
				if sub
					sub_commited=v[:sub_commited]
					sub_modified=v[:sub_modified]
					sub_untracked=v[:sub_untracked]
					if (commited && sub_commited or modified && sub_modified or untracked && sub_untracked)
						yield k, v if block_given?
						r << k
					end
				end
			end
			r
		end
	end
end
