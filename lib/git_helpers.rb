require 'git_helpers/version'
require 'simplecolor'
require 'shell_helpers'
require 'dr/base/bool'
require 'git_helpers/git_dir'
require 'git_helpers/branch'

SimpleColor.mix_in_string

#git functions helper
#small library wrapping git; use rugged for more interesting things
module GitHelpers
	DefaultLogOptions=["-M", "-C", "--no-color"].shelljoin

	extend self
	add_instance_methods = lambda do |klass|
		klass.instance_methods(false).each do |m|
			define_method(m) do |*args,&b|
				GitDir.new.public_send(m,*args,&b)
			end
		end
	end
	GitDir.ancestors.each do |mod|
		add_instance_methods.call(mod) if mod.to_s =~ /^GitHelpers::/
	end

end
