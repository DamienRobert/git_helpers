require 'helper'
require 'git_helpers'

class TestGitHelpers < Minitest::Test

  def test_version
    version = GitHelpers.const_get('VERSION')

    assert(!version.empty?, 'should have a VERSION constant')
  end

end
