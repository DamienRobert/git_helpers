# git_helpers

* [Homepage](https://github.com/DamienRobert/git_helpers#readme)
* [Issues](https://github.com/DamienRobert/git_helpers/issues)
* [Documentation](http://rubydoc.info/gems/git_helpers)
* [Email](mailto:Damien.Olivier.Robert+gems at gmail.com)

[![Gem Version](https://img.shields.io/gem/v/git_helpers.svg)](https://rubygems.org/gems/git_helpers)
[![Build Status](https://travis-ci.org/DamienRobert/git_helpers.svg?branch=master)](https://travis-ci.org/DamienRobert/git_helpers)

## Description

- diff-fancy.rb: like [diff so fancy](https://github.com/so-fancy/diff-so-fancy) but in ruby and with more features
- gitsatus.rb: lie [zsh git prompt](https://github.com/olivierverdier/zsh-git-prompt) but in ruby and with more features too!

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

    #TODO: release the gem
    $ gem install git_helpers

## Copyright

Copyright © 2016–2017 Damien Robert

MIT License. See [LICENSE.txt](./LICENSE.txt) for details.
