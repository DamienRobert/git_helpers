#!/usr/bin/env ruby

require "git_helpers"
require 'optparse'

opts={:color => true}
optparse = OptionParser.new do |opt|
	opt.banner= "#{File.basename($0)} [options] git_dirs"
	opt.on("-p", "--[no-]prompt", "To be used in shell prompt", "This ensure that color ansi sequence are escaped so that they are not counted as text by the shell") do |v|
		opts[:prompt]=v
	end
	opt.on("-s", "--[no-]status[=options]", "List file", "Print the output of git status additionally of what this program parse") do |v|
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
	opt.on("--describe sha1/describe/contains/branch/match/all/magic", "How to describe a detached HEAD", "'branch-fb' by default") do |v|
		opts[:detached_name]=v
	end
	opt.on("--[no-]ignored[=full]", "-i", "Show ignored files") do |v|
		opts[:ignored]=v
	end
	opt.on("--[no-]untracked[=full]", "-u", "Show untracked files") do |v|
		opts[:untracked]=v
	end
	opt.on("--[no-]branch", "Get branch infos") do |v|
		opts[:branch]=v
	end
	opt.on("--[no-]raw", "Show raw status infos") do |v|
		opts[:raw]=v
	end
	opt.on("--sm", "Recurse on each submodules") do |v|
		opts[:submodules]=v
	end
	opt.on("--[no-]debug", "Debug git calls") do |v|
		opts[:debug]=v
	end
end
optparse.parse!

if !opts[:color]
	SimpleColor.enabled=false
end
if opts[:debug]
	SH.debug
end

def prettify_dir(dir)
	return '' if dir.nil?
	return (dir.sub(/^#{ENV['HOME']}/,"~"))+": "
end

def gs_output(dir=".", **opts)
	g=GitHelpers::GitDir.new(dir || ".")
	status={}
	if opts[:raw]
		puts "#{prettify_dir(dir)}#{g.status(**opts)}"
	else
		puts "#{prettify_dir(dir)}#{g.format_status(**opts) {|s| status=s}}"
	end
	if opts[:status] and g.worktree?
		g.with_dir do
			options=opts[:status]
			if options.is_a?(String)
				options=options.split(',')
			else
				options=[]
			end
			out=SH.run_simple("git #{opts[:color] ? "-c color.ui=always" : ""} status --short #{(status[:status_options]+options).shelljoin}")
			out.each_line.each do |line|
				print " "*(opts[:indent]||0) + line
			end
		end
	end
end

if opts[:prompt]
	SimpleColor.enabled=:shell
	prompt=GitHelpers.create.format_status(**opts)
	puts prompt if prompt #in ruby1.8, puts nil output nil...
else
	args=ARGV
	if args.empty?
		opts[:indent]=0 unless opts[:indent]
		args=[nil]
	else
		opts[:indent]=2 unless opts[:indent]
	end
	args.each do |dir|
		gs_output(dir,**opts)
		if opts[:submodules]
			g.with_dir do
				%x/git submodule status/.each_line.map { |l| l.split[1] }.each do |sdir|
					gs_output(sdir, **opts)
				end
			end
		end
	end
end
