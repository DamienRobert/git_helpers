#!/usr/bin/env ruby

require "git_helpers"
require 'optparse'

opts={:color => true, :indent => nil, :sequencer => true, :describe => "magic"}
optparse = OptionParser.new do |opt|
	opt.banner= "#{File.basename($0)} [options] git_dirs"
	opt.on("-p", "--[no-]prompt", "To be used in shell prompt", "This ensure that color ansi sequence are escaped so that they are not counted as text by the shell") do |v|
		opts[:prompt]=v
	end
	opt.on("-s", "--[no-]status", "List file", "Print the output of git status additionally of what this program parse") do |v|
		opts[:status]=v
	end
	opt.on("-c", "--[no-]color", "Color output", "on by default") do |v|
		opts[:color]=v
	end
	opt.on("--[no-]sequencer", "Show sequencer data (and also look for bare directory)", "on by default") do |v|
		opts[:sequencer]=v
	end
	opt.on("--indent spaces", Integer, "Indent to use if showing git status", "2 by default, 0 for empty ARGV") do |v|
		opts[:indent]=v
	end
	opt.on("--describe sha1/describe/contains/branch/match/all/magic", "How to describe a detached HEAD", "'magic' by default") do |v|
		opts[:describe]=v
	end
	opt.on("--sm", "Recurse on each submodules") do |v|
		opts[:submodules]=v
	end
end
optparse.parse!

if !opts[:color]
	SimpleColor.enabled=false
end

def prettify_dir(dir)
	return '' if dir=="."
	return (dir.sub(/^#{ENV['HOME']}/,"~"))+": "
end

def gs_output(dir=".", **opts)
	g=GitHelpers::GitDir.new(dir)
	status=g.status
	puts "#{prettify_dir(dir)}#{g.format_status(status)}"
	if opts[:status] and g.git?
		g.msg.lines.each do |line|
			print " "*(opts[:indent]||0) + line
		end
	end
end

if opts[:prompt]
	SimpleColor.enabled=:shell
	prompt=GitStatus::Git.new.prompt
	puts prompt if prompt #in ruby1.8, puts nil output nil...
else
	args=ARGV
	if args.empty?
		opts[:indent]=0 unless opts[:indent]
		args=["."]
	else
		opts[:indent]=2 unless opts[:indent]
	end
	args.each do |dir|
		gs_output(dir,**opts)
		if opts[:submodules]
			Dir.chdir(dir) do
				%x/git submodule status/.each_line.map { |l| l.split[1] }.each do |sdir|
					gs_output(sdir, **opts)
				end
			end
		end
	end
end
