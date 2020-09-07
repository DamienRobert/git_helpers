require 'git_helpers/version'
require 'simplecolor/mixin'
require 'shell_helpers'
require 'dr/base/bool'
require 'git_helpers/git_dir'
require 'git_helpers/branch'

#git functions helper
#small library wrapping git; use rugged for more interesting things
module GitHelpers
	DefaultLogOptions=["-M", "-C", "--no-color"].shelljoin
	# we only call git to get status updates, we never modify the git dir
	# so locks are not required, pass that information through the env
	# variabole:
	ENV['GIT_OPTIONAL_LOCKS']="0"
	# another solution would be to invoke git via git --no-optional-locks
	# each time. For now the env variable is easier to use.
	# Note that the only optional lock is for git status currently.
	# There is the following trade-off: If git-status will not take locks, it
	# cannot update the index to save refresh information and reuse the next
	# time. So do we want to use this?

	extend self
	add_instance_methods = lambda do |klass|
		klass.instance_methods(false).each do |m|
			define_method(m) do |*args,**kws,&b|
				GitDir.new.public_send(m,*args,**kws,&b)
			end
		end
	end
	# add the instance methods from each helper to GitHelpers
	GitDir.ancestors.each do |mod|
		add_instance_methods.call(mod) if mod.to_s =~ /^GitHelpers::/
	end

	def self.create(dir='.')
		GitDir.new(dir)
	end
end
