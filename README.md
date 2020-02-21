# git_helpers

* [Homepage](https://github.com/DamienRobert/git_helpers#readme)
* [Issues](https://github.com/DamienRobert/git_helpers/issues)
* [Documentation](http://rubydoc.info/gems/git_helpers)
* [Email](mailto:Damien.Olivier.Robert+gems at gmail.com)

[![Gem Version](https://img.shields.io/gem/v/git_helpers.svg)](https://rubygems.org/gems/git_helpers)
[![Build Status](https://travis-ci.org/DamienRobert/git_helpers.svg?branch=master)](https://travis-ci.org/DamienRobert/git_helpers)

## Description

Librairies to help with interacting with git repositories.

This package provides the following binaries:
- diff-fancy.rb: like [diff so fancy](https://github.com/so-fancy/diff-so-fancy) but in ruby and with more features
- gitsatus.rb: lie [zsh git prompt](https://github.com/olivierverdier/zsh-git-prompt) but in ruby and with more features too!

## Diff Fancy

The output is very similar to diff-fancy.rb. With the following
differences:
- diff-fancy.rb implement a parser of git diff. It is then very easy to
  tweak the output afterwards. The original diff-fancy relies on regexp,
  which makes it harder to customize.
- support for submodules change in the diff
- support for octopus merge
- clean up 'No new line at end of file' for symlinks (which never have a new line)

TODO:
- support 'git log -p --graph'
- support git config to activate features on a repo basis

## gitsttatus.rb

~~~
gitstatus.rb [options] git_dirs
    -p, --[no-]prompt                To be used in shell prompt
                                     This ensure that color ansi sequence are escaped so that they are not counted as text by the shell
    -s, --[no-]status[=options]      List file
                                     Print the output of git status additionally of what this program parse
    -c, --[no-]color                 Color output
                                     on by default
        --[no-]sequencer             Show sequencer data (and also look for bare directory)
                                     on by default
        --indent spaces              Indent to use if showing git status
                                     2 by default, 0 for empty ARGV
        --describe sha1/describe/contains/branch/match/all/magic
                                     How to describe a detached HEAD
                                     'branch-fb' by default
    -i, --[no-]ignored[=full]        Show ignored files
    -u, --[no-]untracked[=full]      Show untracked files
        --[no-]branch                Get branch infos (true by default)
        --[no-]files                 Get files infos (true by default)
        --use=branch_name            Show a different branch than HEAD
        --[no-]raw                   Show raw status infos
        --sm                         Recurse on each submodules
        --max-length=length          Maximum status length
        --[no-]debug                 Debug git calls
~~~

## Examples

- `gitstatus.rb folders`
- `git diff | diff-fancy.rb`

Here is my .gitconfig using diff-fancy.rb:

~~~
	highlight = "!f() { [ \"$GIT_PREFIX\" != \"\" ] && cd \"$GIT_PREFIX\"; GIT_PAGER=\"diff-fancy.rb\" git $@; }; f"
	di = "!f() { [ \"$GIT_PREFIX\" != \"\" ] && cd \"$GIT_PREFIX\"; GIT_PAGER=\"diff-fancy.rb\" git diff -B $@; }; f"
	dc = "!f() { [ \"$GIT_PREFIX\" != \"\" ] && cd \"$GIT_PREFIX\"; GIT_PAGER=\"diff-fancy.rb\" git diff -B --staged $@; }; f"
	dw = "!f() { [ \"$GIT_PREFIX\" != \"\" ] && cd \"$GIT_PREFIX\"; GIT_PAGER=\"diff-fancy.rb --no-highlight\" git diff -B --color-words $@; }; f"
	dcw = "!f() { [ \"$GIT_PREFIX\" != \"\" ] && cd \"$GIT_PREFIX\"; GIT_PAGER=\"diff-fancy.rb --no-highlight\" git diff -B --staged --color-words $@; }; f"
~~~

## Install

    $ gem install git_helpers

## Copyright

Copyright © 2016–2020 Damien Robert

MIT License. See [LICENSE.txt](./LICENSE.txt) for details.
