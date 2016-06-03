#!/usr/bin/env ruby
#Inspired by diff-so-fancy; wrapper around diff-highlight
#https://github.com/stevemao/diff-so-fancy

require "simplecolor"
SimpleColor.mix_in_string
begin
	require "shell_helpers"
rescue LoadError
end

class GitDiff
	def self.output(gdiff)
	end

	attr_reader :output
	include Enumerable
	NoNewLine="\\ No newline at end of file\n"

	def initialize(diff,**opts)
		@diff=diff #Assume diff is a line iterator [diff.each_line.to_a]
		@current=0
		@mode=:unknown
		@opts=opts
		@opts[:color]=@opts.fetch(:color,true)
		#modes: 
		#- unknown (temp mode)
		#- commit
		#- meta
		#- submodule_header
		#- submodule
		#- diff_header
		#- hunk
		@colors={meta: [:bold]}
	end

	def output_line(l)
		@output << l.chomp+"\n"
	end
	def output_lines(lines)
		lines.each {|l| output_line l}
	end
	def output
		each {|l| puts l}
	end

	def next_mode(nmode)
		@next_mode=nmode
	end
	def update_mode
		@start_mode=false
		@next_mode && change_mode(@next_mode)
		@next_mode=nil
	end
	def change_mode(nmode)
		@start_mode=true
		send :"end_#{@mode}" unless @mode==:unknown
		@mode=nmode
		send :"new_#{@mode}" unless @mode==:unknown
	end

	def new_commit; @commit={}; end
	def end_commit; end
	def new_meta; end
	def end_meta; end
	def new_hunk; end
	def end_hunk; end
	def new_submodule_header; @submodule={}; end
	def end_submodule_header; end
	def new_submodule; end
	def end_submodule; end
	def new_diff_header; @file={mode: :modify} end
	def end_diff_header; end

	def detect_new_diff_header
		@line =~ /^diff\s/
	end
	def detect_end_diff_header
		@line =~ /^\+\+\+\s/
	end

	def detect_new_hunk
		@line.match(/^@@+\s.*\s@@/)
	end
	def detect_end_hunk
		@hunk[:lines_seen].each_with_index.all? { |v,i| v==@hunk[:lines][i].first }
	end

	def handle_meta
		handle_line
	end

	def parse_hunk_header
		m=@line.match(/^@@+\s(.*)\s@@\s*(.*)/)
		hunks=m[1]
		@hunk={lines: []}
		@hunk[:header]=m[2]
		filenumber=0
		hunks.split.each do |hunk|
			hunkmode=hunk[0]
			hunk=hunk[1..-1]
			line,length=hunk.split(',').map(&:to_i)
			#handle hunks of the form @@ -1 +0,0 @@
			length,line=line,length unless length
			case hunkmode
			when '-'
				filenumber+=1
				@hunk[:lines][filenumber]=[length,line]
			when '+'
				@hunk[:lines][0]=[length,line]
			end
		end
		@hunk[:n]=@hunk[:lines].length
		@hunk[:lines_seen]=Array.new(@hunk[:n],0)
	end

	def handle_hunk
		if @start_mode
			parse_hunk_header
		else
			#'The 'No new line at end of file' is sort of part of the hunk, but
			#is not considerer in the hunkheader
			unless @line == NoNewLine
				#we need to wait for a NoNewLine to be sure we are at the end of the hunk
				return reparse(:unknown) if detect_end_hunk
				linemodes=@line[0...@hunk[:n]-1]
				newline=true
				#the line is on the new file unless there is a '-' somewhere
				if linemodes=~/-/
					newline=false
				else
					@hunk[:lines_seen][0]+=1
				end
				(1...@hunk[:n]).each do |i|
					linemode=linemodes[i-1]
					case linemode
					when '-'
						@hunk[:lines_seen][i]+=1
					when ' '
						@hunk[:lines_seen][i]+=1 if newline
					end
				end
			end
		end
		handle_line
	end

	def get_file_name(file)
		#remove prefix (todo handle the no-prefix option)
		file.gsub(/^[abciow12]\//,'')
	end

	def detect_filename
		if m=@line.match(/^---\s(.*)/)
			@file[:old_name]=get_file_name(m[1])
			return true
		end
		if m=@line.match(/^\+\+\+\s(.*)/)
			@file[:name]=get_file_name(m[1])
			return true
		end
		false
	end

	def detect_perm
		if m=@line.match(/^old mode\s+(.*)/)
			@file[:old_perm]=m[1]
			return true
		end
		if m=@line.match(/^new mode\s+(.*)/)
			@file[:new_perm]=m[1]
			return true
		end
		false
	end

	def detect_index
		if m=@line.match(/^index\s+(.*)\.\.(.*)/)
			@file[:oldhash]=m[1].split(',')
			@file[:hash],perm=m[2].split
			@file[:perm]||=perm
			return true
		end
		false
	end

	def detect_delete
		if m=@line.match(/^deleted file mode\s+(.*)/)
			@file[:old_perm]=m[1]
			@file[:mode]=:delete
			return true
		end
		false
	end

	def detect_newfile
		if m=@line.match(/^new file mode\s+(.*)/)
			@file[:new_perm]=m[1]
			@file[:mode]=:new
			return true
		end
		false
	end

	def detect_rename_copy
		if m=@line.match(/^similarity index\s+(.*)/)
			@file[:similarity]=m[1]
			return true
		end
		if m=@line.match(/^dissimilarity index\s+(.*)/)
			@file[:mode]=:rewrite
			@file[:dissimilarity]=m[1]
			return true
		end
		#if we have a rename with 100% similarity, there won't be any hunks so
		#we need to detect the filenames there
		if m=@line.match(/^(?:rename|copy) from\s+(.*)/)
			@file[:old_name]=m[1]
		end
		if m=@line.match(/^(?:rename|copy) to\s+(.*)/)
			@file[:name]=m[1]
		end
		if m=@line.match(/^rename\s+(.*)/)
			@file[:mode]=:rename
			return true
		end
		if m=@line.match(/^copy\s+(.*)/)
			@file[:mode]=:copy
			return true
		end
		false
	end

	def detect_diff_header
		if @start_mode
			if m=@line.chomp.match(/^diff\s--git\s(.*)\s(.*)/)
				@file[:old_name]=get_file_name(m[1])
				@file[:name]=get_file_name(m[2])
			elsif
				m=@line.match(/^diff\s--(?:cc|combined)\s(.*)/)
				@file[:name]=get_file_name(m[1])
			end
			true
		end
	end

	def handle_diff_header
		if detect_diff_header
		elsif detect_filename
		elsif detect_perm
		elsif detect_index
		elsif detect_delete
		elsif detect_newfile
		elsif detect_rename_copy
		else
			return reparse(:unknown)
		end
		next_mode(:unknown) if detect_end_diff_header
		handle_line
	end

	def detect_new_submodule_header
		if m=@line.chomp.match(/^Submodule\s(.*)\s(.*)/)
			subname=m[1];
			return not(@submodule && @submodule[:name]==subname)
		end
		false
	end

	def handle_submodule_header
		if m=@line.chomp.match(/^Submodule\s(\S*)\s(.*)/)
			subname=m[1]
			if @submodule[:name]
				#we may be dealing with a new submodule
				#require 'pry'; binding.pry
				return reparse(:submodule_header) if subname != @submodule[:name]
			else
				@submodule[:name]=m[1]
			end
			subinfo=m[2]
			if subinfo == "contains untracked content"
				@submodule[:untracked]=true
			elsif subinfo == "contains modified content"
				@submodule[:modified]=true
			else
				(@submodule[:info]||="") << subinfo
				next_mode(:submodule) if subinfo =~ /^.......\.\.\.?........*:$/
			end
			handle_line
		else
			return reparse(:unknown)
		end
	end

	def handle_submodule
		#we have lines indicating new commits
		#they always end by a new line
		handle_line
		next_mode(:unknown) if @line.chomp.empty?
	end

	def detect_new_commit
		@line=~/^commit\b/
	end

	def handle_commit
		if m=@line.match(/^(\w+):\s(.*)/)
			@commit[m[1]]=m[2]
			handle_line
		else
			@start_mode ? handle_line : reparse(:unknown)
		end
	end

	def reparse(nmode)
		change_mode(nmode)
		parse_line
	end

	def handle_line
	end


	def parse_line
		case @mode
		when :unknown, :meta
			if detect_new_hunk
				return reparse(:hunk)
			elsif detect_new_diff_header
				return reparse(:diff_header)
			elsif detect_new_submodule_header
				return reparse(:submodule_header)
			elsif detect_new_commit
				return reparse(:commit)
			else
				change_mode(:meta) if @mode==:unknown
				handle_meta
			end
		when :commit
			handle_commit
		when :submodule_header
			handle_submodule_header
		when :submodule
			handle_submodule
		when :diff_header
			handle_diff_header
			#=> mode=unknown if we detect we are not a diff header anymore
		when :hunk
			handle_hunk
			#=> mode=unknown at end of hunk
		end
	end

	def prepare_new_line(line)
		@orig_line=line
		@line=@orig_line.uncolor
		update_mode
	end

	def parse
		Enumerator.new do |y|
			@output=y
			@diff.each do |line|
				prepare_new_line(line)
				parse_line
				yield if block_given?
			end
			change_mode(:unknown) #to trigger the last end_* hook
		end
	end

	def each(&b)
		parse.each(&b)
	end
end

class GitDiffDebug < GitDiff
	def initialize(*args,&b)
		super
		@cols=`tput cols`.to_i
	end

	def center(msg)
		msg.center(@cols,'─')
	end

	def handle_line
		super
		output_line "#{@mode}: #{@orig_line}"
		#p @hunk if @mode==:hunk
	end

	%i(commit meta diff_header hunk submodule_header submodule).each do |meth|
		define_method(:"new_#{meth}") do |*a,&b|
			super(*a,&b)
			output_line(center("New #{meth}"))
		end
		define_method(:"end_#{meth}") do |*a,&b|
			super(*a,&b)
			output_line(center("End #{meth}"))
		end
	end
end

#stolen from diff-highlight git contrib script
class GitDiffHighlight < GitDiff
	def new_hunk
		super
		@accumulator=[[],[]]
	end
	def end_hunk
		super
		show_hunk
	end

	def highlight_pair(old,new)
		oldc=SimpleColor.color_entities(old).each_with_index
		newc=SimpleColor.color_entities(new).each_with_index
		seen_pm=false
		#find common prefix
		loop do
			a=oldc.grep {|c| ! SimpleColor.color?(c)}
			b=newc.grep {|c| ! SimpleColor.color?(c)}
			if !seen_pm and a=="-" and b=="+"
				seen_pm=true
			elsif a==b
			else
				last
			end
		#rescue StopIteration
		end
	end

	def show_hunk
		old,new=@accumulator
		if old.length != new.length
			output_lines(old+new)
		else
			newhunk=[]
			(0...old.length).each do |i|
				oldi,newi=highlight_pair(old[i],new[i])
				output_line oldi
				newhunk << newi
			end
			output_lines(newhunk)
		end
	end

	def handle_line
		if @mode == :hunk && @hunk[:n]==2
			linemode=@line[0]
			case linemode
			when "-"
				@accumulator[0] << @orig_line
			when "+"
				@accumulator[1] << @orig_line
			else
				show_hunk
				@accumulator=[[],[]]
				output_line @orig_line
			end
		else
			output_line @orig_line
		end
	end
end

class GitFancyDiff < GitDiff

	def initialize(*args,&b)
		super
		#when run inside a pager I get one more column so the line overflow
		#I don't know why
		@cols=`tput cols`.to_i-1
	end

	def hline
		'─'*@cols
	end
	def hhline
		#'⬛'*@cols
		#"━"*@cols
		"═"*@cols
	end

	def short_perm_mode(m, prefix: '+')
		case m
		when "040000"
			prefix+"d" #directory
		when "100644"
			"" #file
		when "100755"
			prefix+"x" #executable
		when "120000"
			prefix+"l" #symlink
		when "160000"
			prefix+"g" #gitlink
		end
	end
	def perm_mode(m, prefix: ' ')
		case m
		when "040000"
			prefix+"directory"
		when "100644"
			"" #file
		when "100755"
			prefix+"executable"
		when "120000"
			prefix+"symlink"
		when "160000"
			prefix+"gitlink"
		end
	end

	def diff_header_summary
		r=case @file[:mode]
			when :modify
				"modified: #{@file[:name]}"
			when :rewrite
				"rewrote: #{@file[:name]} (dissimilarity: #{@file[:dissimilarity]})"
			when :new
				"added#{perm_mode(@file[:new_perm])}: #{@file[:name]}"
			when :delete
				"deleted#{perm_mode(@file[:old_perm])}: #{@file[:old_name]}"
			when :rename
				"renamed: #{@file[:old_name]} to #{@file[:name]} (similarity: #{@file[:similarity]})"
			when :copy
				"copied: #{@file[:old_name]} to #{@file[:name]} (similarity: #{@file[:similarity]})"
			end
		r<<" [#{short_perm_mode(@file[:old_perm],prefix:'-')}#{short_perm_mode(@file[:new_perm])}]" if @file[:old_perm] && @file[:new_perm]
		r
	end

	def meta_colorize(l)
		if @opts[:color]
			l.color(*@colors[:meta])
		else
			l
		end
	end

	def new_diff_header
		super
		output_line meta_colorize(hline)
	end

	def end_diff_header
		super
		output_line meta_colorize(diff_header_summary)
		output_line meta_colorize(hline)
	end

	def submodule_header_summary
		r="Submodule #{@submodule[:name]}"
		r << " #{@submodule[:info]}"
		extra=[@submodule[:modified] && "modified", @submodule[:untracked] && "untracked"].compact.join("+")
		r<<" [#{extra}]" unless extra.empty?
		r
	end

	def new_submodule_header
		super
		output_line meta_colorize(hline)
	end

	def end_submodule_header
		super
		output_line meta_colorize(submodule_header_summary)
		output_line meta_colorize(hline)
	end

	def nonewline_clean
			@mode==:hunk && @file && (@file[:perm]=="120000" or @file[:old_perm]=="120000" or @file[:new_perm]=="120000") && @line==NoNewLine
	end

	def new_commit
		super
		output_line meta_colorize(hhline)
	end
	def end_commit
		super
		output_line meta_colorize(hhline)
	end

	def clean_hunk_col
		if @opts[:color] && @mode==:hunk && !@start_mode && @hunk[:n]==2
			bcolor,ecolor,line=SimpleColor.current_colors(@orig_line)
			m=line.match(/^([+-])?(.*)/)
			mode=m[1]
			cline=m[2]
			if mode && cline !~ /[^[:space:]]/ #detect blank line
				output_line SimpleColor.color(bcolor.to_s + (cline.empty? ? " ": cline)+ecolor.to_s,:inverse)
			else
				cline.sub!(/^\s/,'') unless mode #strip one blank character
				output_line bcolor.to_s+cline+ecolor.to_s
			end
			true
		end
	end

	def hunk_header
		if @mode==:hunk && @start_mode
			if @hunk[:lines][0][1] && @hunk[:lines][0][1] != 0
				header="#{@file[:name]}:#{@hunk[:lines][0][1]}"
				output_line @orig_line.sub(/(@@+\s)(.*)(\s@@+)/,"\\1#{header}\\3")
			end
			true
		end
	end

	def handle_line
		super
		#:diff_header and submodule_header are handled at end_*
		case @mode
		when :meta
			output_line @orig_line
		when :hunk
			if hunk_header
			elsif nonewline_clean
			elsif clean_hunk_col
			else
				output_line @orig_line
			end
		when :submodule,:commit
			output_line @orig_line
		end
	end
end

if __FILE__ == $0
	require 'optparse'

	@opts={pager: true, diff_highlight: true, color: true, debug: false}
	optparse = OptionParser.new do |opt|
		opt.banner = "fancy git diff"
		opt.on("--[no-]pager", "launch the pager [true]") do |v|
			@opts[:pager]=v
		end
		opt.on("--[no-]highlight", "run the diff through diff-highlight [true]") do |v|
			@opts[:diff_highlight]=v
		end
		opt.on("--[no-]color", "color output [true]") do |v|
			@opts[:color]=v
		end
		opt.on("--raw", "Only parse diff headers") do |v|
			@opts[:color]=false
			@opts[:pager]=false
			@opts[:diff_highlight]=false
		end
		opt.on("--[no-]debug", "Debug mode") do |v|
			@opts[:debug]=v
		end
	end
	optparse.parse!
	@opts[:pager]=false unless Module.const_defined?('ShellHelpers')
	@opts[:pager] && ShellHelpers.run_pager

	diff_highlight=ENV['DIFF_HIGHLIGHT']||"#{File.dirname(__FILE__)}/contrib/diff-highlight"

	args=ARGF
	if @opts[:debug]
		GitDiffDebug.new(args,**@opts).output
	elsif @opts[:diff_highlight]
		IO.popen(diff_highlight,'r+') do |f|
			Thread.new do
				args.each_line do |l|
					f.write(l)
				end
				f.close_write
			end
			GitFancyDiff.new(f,**@opts).output
		end
	else
		#diff=GitDiffHighlight.new(args,**@opts).parse
		GitFancyDiff.new(args,**@opts).output
	end
end
