require File.expand_path('../spec_helper', __FILE__)
require 'cocoapods-imy-bin/post_install_hook'

module Pod
  describe 'imy-bin post-install hook' do
    it 'accepts a Podfile-like object without the optional use_hmap? DSL' do
      podfile = Object.new
      podfile.respond_to?(:use_hmap?).should == false
      Config.instance.stubs(:podfile).returns(podfile)

      HooksManager.run(:post_install, Object.new, 'cocoapods-imy-bin' => {})
    end
  end
end
